import Foundation
import Testing
@testable import Resolume

/// Servidor que imita o comportamento da Resolume discovered ao vivo:
/// 1. `initialize` devolve `instructions`;
/// 2. todo `tools/call` e recusado ate o cliente declarar que as leu;
/// 3. traiçoeiro: `tools/list` reseta essa declaracao no meio da sessao.
actor GatedArenaServer: MCPTransport {
    private var acknowledged = false
    private(set) var gateTrips = 0

    func start() async throws {}
    func stop() async {}
    func notify(_ line: String) async throws {}

    func send(requestLine: String) async throws -> String {
        struct RawRequest: Decodable {
            let id: Int
            let method: String
            let params: [String: MCPValue]?
        }
        let request = try JSONDecoder().decode(RawRequest.self, from: Data(requestLine.utf8))
        switch request.method {
        case "initialize":
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"protocolVersion":"2025-03-26","serverInfo":{"name":"gated-fake","version":"7.28.0"},"capabilities":{"tools":{}},"instructions":"Confirmacao obrigatoria antes de salvar."}}
            """
        case "tools/list":
            acknowledged = false
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"tools":[{"name":"status","description":"Status"},{"name":"layer","description":"Camadas"}]}}
            """
        case "tools/call":
            let name = request.params?["name"]?.stringValue ?? "?"
            let action = request.params?["arguments"]?["action"]?.stringValue ?? ""
            let injected = request.params?["arguments"]?["injected"]?.boolValue ?? false
            if name == "status", action == "instructions", injected {
                acknowledged = true
                return #"{"jsonrpc":"2.0","id":\#(request.id),"result":{"content":[{"type":"text","text":"Instructions confirmed. Continue."}],"isError":false}}"#
            }
            guard acknowledged else {
                gateTrips += 1
                return """
                {"jsonrpc":"2.0","id":\(request.id),"result":{"content":[{"type":"text","text":"You must read server instructions first."}],"isError":true}}
                """
            }
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"content":[{"type":"text","text":"ok de \(name)"}],"isError":false}}
            """
        default:
            return """
            {"jsonrpc":"2.0","id":\(request.id),"error":{"code":-32601,"message":"method not found"}}
            """
        }
    }
}

@Test("tools/call sobrevive ao gate de instrucoes mesmo sem tools/list antes")
func callToolSelfHealsThroughTheGate() async throws {
    let client = MCPClient(transport: GatedArenaServer())
    try await client.connect()
    // Sem nenhuma lista de ferramentas antes: o primeiro call esbarra no gate
    // e precisa se recuperar sozinho.
    let result = try await client.callTool("layer")
    #expect(result.text == "ok de layer")
}

@Test("tools/list no meio da conversa nao desarma o gate")
func toolsListAfterAcknowledgementKeepsToolsUsable() async throws {
    let client = MCPClient(transport: GatedArenaServer())
    try await client.connect()
    _ = try await client.listTools()
    // Refrescar a lista e exatamente o que desarma o servidor na Resolume.
    _ = try await client.listTools(forceRefresh: true)
    let result = try await client.callTool("layer")
    #expect(result.text == "ok de layer")
}

@Test("rodada de ferramentas do chat atravessa o gate sem erro")
func chatRoundTripThroughTheGate() async throws {
    let client = MCPClient(transport: GatedArenaServer())
    try await client.connect()
    let backend = ScriptedChatTransport(script: [
        // Leitura real (action get/list) passa na ToolPolicy .readOnly do engine.
        ScriptedChatTransport.toolCallResponse(id: "call_1", name: "layer", arguments: #"{"action":"list"}"#),
        ScriptedChatTransport.toolCallResponse(id: "call_2", name: "status", arguments: #"{"action":"get"}"#),
        ScriptedChatTransport.textResponse("3 camadas ativas."),
    ])
    let engine = ChatEngine(
        config: .init(apiKey: "demo", model: "fake"),
        transport: backend,
        mcp: client)
    let answer = try await engine.send("quais camadas?")
    #expect(answer == "3 camadas ativas.")

    let bodies = await backend.requestBodies
    let third = String(data: bodies[2], encoding: .utf8) ?? ""
    // O bug real: a segunda rodada vinha com "must read server instructions".
    #expect(third.contains("ok de layer"))
    #expect(!third.contains("must read server instructions"))
    #expect(third.contains("Instruções do servidor MCP"))
    #expect(third.contains("Confirmacao obrigatoria antes de salvar."))
}

@Test("base URL sem barra final nao perde o /v1")
func chatCompletionsEndpointNormalization() {
    let plain = ChatEngine.Config.chatCompletionsEndpoint(URL(string: "https://api.openai.com/v1")!)
    #expect(plain.absoluteString == "https://api.openai.com/v1/chat/completions")
    let slashed = ChatEngine.Config.chatCompletionsEndpoint(URL(string: "http://127.0.0.1:8937/v1/")!)
    #expect(slashed.absoluteString == "http://127.0.0.1:8937/v1/chat/completions")
    let bare = ChatEngine.Config.chatCompletionsEndpoint(URL(string: "http://127.0.0.1:11434")!)
    #expect(bare.absoluteString == "http://127.0.0.1:11434/chat/completions")
}
