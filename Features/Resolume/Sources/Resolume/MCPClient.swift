import Foundation

public struct MCPToolInfo: Sendable, Equatable {
    public let name: String
    public let description: String?
    public let inputSchema: MCPValue

    public init(name: String, description: String?, inputSchema: MCPValue = .object(["type": .string("object")])) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPCallResult: Sendable, Equatable {
    public let content: [MCPValue]
    public let isError: Bool

    public var text: String {
        content.compactMap { item in
            if item["type"]?.stringValue == "text" { item["text"]?.stringValue } else { nil }
        }.joined(separator: "\n")
    }
}

/// Sessão JSON-RPC 2.0 (newline-delimited) com um servidor MCP stdio.
public actor MCPClient {
    private let transport: any MCPTransport
    private let clientName: String
    private let protocolVersion = "2025-03-26"
    private var nextRequestID = 1
    private var initialized = false
    private var instructions: String?
    private var instructionsAcknowledged = false
    private var cachedTools: [MCPToolInfo]?

    public init(transport: any MCPTransport, clientName: String = "Resolux") {
        self.transport = transport
        self.clientName = clientName
    }

    /// Instruções que o servidor devolveu no `initialize`. A Resolume exige que
    /// o cliente as declare lidas antes de aceitar qualquer `tools/call` — e,
    /// traiçoeiro, `tools/list` reseta essa declaração. Ver `acknowledgeServerInstructions`.
    public var serverInstructions: String? { instructions }

    /// Lança o servidor e completa o handshake initialize/initialized.
    public func connect() async throws {
        try await transport.start()
        let params: [String: MCPValue] = [
            "protocolVersion": .string(protocolVersion),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string("1.0"),
            ]),
            "capabilities": .object([:]),
        ]
        let result = try await request(method: "initialize", params: params)
        instructions = result["instructions"]?.stringValue
        instructionsAcknowledged = false
        cachedTools = nil
        try await transport.notify(encode(MCPNotification(method: "notifications/initialized")))
        initialized = true
    }

    public func disconnect() async {
        await transport.stop()
        initialized = false
    }

    /// Lista as ferramentas uma única vez e cacheia. Repetir `tools/list` a cada
    /// rodada do chat custaria ~70 KB por chamada e, pior, desarma o gate de
    /// instruções do servidor da Resolume no meio do diálogo.
    public func listTools(forceRefresh: Bool = false) async throws -> [MCPToolInfo] {
        if let cachedTools, !forceRefresh { return cachedTools }
        let result = try await request(method: "tools/list")
        let tools = result["tools"]?.arrayValue ?? []
        let infos = tools.compactMap { tool -> MCPToolInfo? in
            guard let name = tool["name"]?.stringValue else { return nil }
            return MCPToolInfo(
                name: name,
                description: tool["description"]?.stringValue,
                inputSchema: tool["inputSchema"] ?? .object(["type": .string("object")]))
        }
        cachedTools = infos
        // Listar ferramentas desarma a declaração de leitura: reafirmar aqui, na
        // mesma respirada, antes de qualquer tools/call.
        instructionsAcknowledged = false
        _ = await acknowledgeServerInstructions()
        return infos
    }

    /// Declara ao servidor que lemos as instruções do `initialize`. A Resolume
    /// devolve `isError` em todo `tools/call` até receber essa declaração.
    ///
    /// Não lança: um servidor sem gate (sem instruções, ou sem ferramenta
    /// `status`) só retorna `false`. Derrubar uma sessão sadia porque o servidor
    /// é mais simples que a Resolume seria um bug nosso.
    @discardableResult
    public func acknowledgeServerInstructions() async -> Bool {
        guard let instructions, !instructions.isEmpty, !instructionsAcknowledged else {
            return false
        }
        guard let outcome = try? await performToolCall(
            "status",
            arguments: ["action": .string("instructions"), "injected": .bool(true)]),
            !outcome.isError
        else { return false }
        instructionsAcknowledged = true
        return true
    }

    @discardableResult
    public func callTool(_ name: String, arguments: [String: MCPValue] = [:]) async throws -> MCPCallResult {
        let first = try await performToolCall(name, arguments: arguments)
        // Se o gate caiu no meio da sessão (um tools/list tardio, um reconnect),
        // reafirmar as instruções e repetir a chamada uma única vez.
        if first.isError, Self.isInstructionsGate(first.text), !isInstructionsAck(name, arguments) {
            instructionsAcknowledged = false
            _ = await acknowledgeServerInstructions()
            let retry = try await performToolCall(name, arguments: arguments)
            return try conclude(retry)
        }
        return try conclude(first)
    }

    private func conclude(_ outcome: MCPCallResult) throws -> MCPCallResult {
        if outcome.isError { throw MCPError.toolFailed(outcome.text) }
        return outcome
    }

    private func performToolCall(
        _ name: String,
        arguments: [String: MCPValue]
    ) async throws -> MCPCallResult {
        let result = try await request(
            method: "tools/call",
            params: ["name": .string(name), "arguments": .object(arguments)])
        let content = result["content"]?.arrayValue ?? []
        let isError = result["isError"].map { if case .bool(let flag) = $0 { flag } else { false } } ?? false
        return MCPCallResult(content: content, isError: isError)
    }

    private func isInstructionsAck(_ name: String, _ arguments: [String: MCPValue]) -> Bool {
        name == "status" && arguments["action"]?.stringValue == "instructions"
    }

    private static func isInstructionsGate(_ text: String) -> Bool {
        text.lowercased().contains("must read server instructions")
    }

    /// Requisição genérica — usada pelo ChatEngine para métodos ad-hoc.
    public func request(
        method: String,
        params: [String: MCPValue]? = nil
    ) async throws -> MCPValue {
        guard initialized || method == "initialize" else { throw MCPError.notInitialized }
        let id = nextRequestID
        nextRequestID += 1
        let responseLine = try await transport.send(
            requestLine: encode(MCPRequest(id: id, method: method, params: params)))
        guard let response = try? JSONDecoder().decode(MCPResponse.self, from: Data(responseLine.utf8)) else {
            throw MCPError.malformedResponse
        }
        if let error = response.error { throw MCPError.serverError(code: error.code, message: error.message) }
        return response.result ?? .null
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let line = String(data: data, encoding: .utf8) else { throw MCPError.malformedResponse }
        return line
    }
}
