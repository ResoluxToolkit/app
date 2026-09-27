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

    public init(transport: any MCPTransport, clientName: String = "Resolux") {
        self.transport = transport
        self.clientName = clientName
    }

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
        _ = try await request(method: "initialize", params: params)
        try await transport.notify(encode(MCPNotification(method: "notifications/initialized")))
        initialized = true
    }

    public func disconnect() async {
        await transport.stop()
        initialized = false
    }

    public func listTools() async throws -> [MCPToolInfo] {
        let result = try await request(method: "tools/list")
        let tools = result["tools"]?.arrayValue ?? []
        return tools.compactMap { tool in
            guard let name = tool["name"]?.stringValue else { return nil }
            return MCPToolInfo(
                name: name,
                description: tool["description"]?.stringValue,
                inputSchema: tool["inputSchema"] ?? .object(["type": .string("object")]))
        }
    }

    @discardableResult
    public func callTool(_ name: String, arguments: [String: MCPValue] = [:]) async throws -> MCPCallResult {
        let result = try await request(
            method: "tools/call",
            params: ["name": .string(name), "arguments": .object(arguments)])
        let content = result["content"]?.arrayValue ?? []
        let isError = result["isError"].map { if case .bool(let flag) = $0 { flag } else { false } } ?? false
        let outcome = MCPCallResult(content: content, isError: isError)
        if isError { throw MCPError.toolFailed(outcome.text) }
        return outcome
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
