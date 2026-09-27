import Foundation
import Testing
@testable import Resolume

/// Backend de chat que reproduz um roteiro fixo de respostas OpenAI-compatíveis.
actor ScriptedChatTransport: ChatBackendTransport {
    private var script: [String]
    private(set) var requestBodies: [Data] = []

    init(script: [String]) { self.script = script }

    func complete(endpoint: URL, apiKey: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        requestBodies.append(body)
        guard !script.isEmpty else { throw ChatError.noChoices }
        let json = script.removeFirst()
        let http = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), http)
    }

    nonisolated static func textResponse(_ text: String) -> String {
        """
        {"choices":[{"message":{"role":"assistant","content":"\(text)"},"finish_reason":"stop"}]}
        """
    }

    nonisolated static func toolCallResponse(id: String, name: String, arguments: String) -> String {
        """
        {"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"\(id)","type":"function","function":{"name":"\(name)","arguments":"\(arguments)"}}]},"finish_reason":"tool_calls"}]}
        """
    }
}

@Test("tool_call do modelo vira tools/call MCP e a resposta final volta")
func toolRoundTrip() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.toolCallResponse(id: "call_1", name: "status", arguments: "{}"),
        ScriptedChatTransport.textResponse("Arena rodando."),
    ])
    let engine = ChatEngine(
        config: .init(apiKey: "test", model: "fake-model"),
        transport: backend,
        mcp: mcp)
    let answer = try await engine.send("Como tá o Arena?")
    #expect(answer == "Arena rodando.")

    // Segunda chamada ao backend deve carregar o resultado da ferramenta MCP no histórico.
    let bodies = await backend.requestBodies
    #expect(bodies.count == 2)
    let secondBody = String(data: bodies[1], encoding: .utf8) ?? ""
    #expect(secondBody.contains("ok de status"))
    #expect(secondBody.contains("\"tool\""))
}

@Test("sem ferramentas o modelo responde direto")
func plainAnswerWithoutTools() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    // Sem connect(): listTools falha e o engine deve propagar erro de sessão.
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.textResponse("oi"),
    ])
    let engine = ChatEngine(
        config: .init(apiKey: "test", model: "fake-model"),
        transport: backend,
        mcp: mcp)
    await #expect(throws: MCPError.notInitialized) {
        _ = try await engine.send("oi")
    }
}
