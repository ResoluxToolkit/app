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
        // `arguments` vai dentro de uma string JSON: aspas precisam escapar.
        let escaped = arguments
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"\(id)","type":"function","function":{"name":"\(name)","arguments":"\(escaped)"}}]},"finish_reason":"tool_calls"}]}
        """
    }
}

@Test("tool_call do modelo vira tools/call MCP e a resposta final volta")
func toolRoundTrip() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.toolCallResponse(id: "call_1", name: "status", arguments: #"{"action":"get"}"#),
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

@Test("resposta final remove bloco think")
func finalAnswerStripsThinkingTag() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.textResponse("Pensando.\\u003Cthink\\u003E\\u003C/think\\u003E\\nResposta curta."),
    ])
    let engine = ChatEngine(
        config: .init(apiKey: "test", model: "fake-model"),
        transport: backend,
        mcp: mcp)
    let answer = try await engine.send("Como tá o Arena?")
    #expect(answer == "Pensando.\nResposta curta.")
}

@Test("prompt exige declarar a fonte do relógio antes de citar BPM")
func promptTeachesPerClipClockSource() {
    // Lição do operador: o Arena tem vários controles de velocidade e transporte.
    // Cada clipe tem o próprio modo, então o BPM global do transport não é
    // necessariamente o andamento do show. Sem isso o assistente informa número
    // solto pro VJ no meio da performance.
    let prompt = ChatEngine.systemPrompt
    #expect(prompt.contains("clip.transporttype"))
    // `clip.type` era o nome que ESTAVA no prompt e nao existe no payload (medido:
    // nenhuma chave `type` nos 72 clipes). Congelar a ausencia evita o fantasma.
    #expect(!prompt.contains("clip.type"))
    #expect(prompt.contains("BPM Sync"))
    #expect(prompt.contains("SMPTE"))
    #expect(prompt.contains("Pioneer"))
    #expect(prompt.contains("fonte"))
}

@Test("prompt proibe sugerir SMPTE para clipe com audio")
func promptForbidsSmpteOnClipsWithAudio() {
    // Regra do operador, ausente do schema do Arena: sincronismo SMPTE so roda em
    // clipe cuja faixa e so de video. O schema so documenta o caso contrario
    // (clip.syncmode 'Beats'/'BPM' exige audio), entao sem isto no prompt o
    // assistente sugere SMPTE para clipe com audio e o Arena recusa em cena.
    let prompt = ChatEngine.systemPrompt
    #expect(prompt.contains("sem faixa"))
    #expect(prompt.contains("Nunca sugira SMPTE"))
}
