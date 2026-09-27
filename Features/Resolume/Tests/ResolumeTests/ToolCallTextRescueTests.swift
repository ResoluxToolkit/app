import Foundation
import Testing
@testable import Resolume

/// O `fm serve` da Apple devolve a chamada de ferramenta como TEXTO dentro de
/// ```json com finish_reason "stop". Esses testes congelam o resgate exatamente
/// contra essa forma, fotografada do provedor real nesta máquina.
private let known: Set<String> = ["composition", "layer", "status"]

@Test("bloco json cercado vira tool_call executável")
func fencedBlockBecomesToolCall() {
    let text = """
    Vou verificar isso.
    ```json
    {"tool_calls":[{"name":"composition","arguments":{"action":"list"}}]}
    ```
    """
    let outcome = ToolCallTextRescue.rescue(from: text, knownTools: known)
    let calls = outcome?.calls ?? []
    #expect(calls.count == 1)
    #expect(calls.first?.function.name == "composition")
    #expect(calls.first?.function.arguments == #"{"action":"list"}"#)
    #expect(outcome?.remainingText == "Vou verificar isso.")
}

@Test("formato oficial aninhado function/name também é resgatado")
func nestedFunctionShapeIsRescued() {
    let text = #"""
    {"name":"layer","function":{"name":"layer","arguments":"{\"action\":\"get\"}"}}
    """#
    // O item raiz não tem "arguments": o resgate cai no caminho aninhado e a
    // arguments já chega como string JSON do wire format oficial.
    let calls = ToolCallTextRescue.rescue(from: text, knownTools: known)?.calls ?? []
    #expect(calls.count == 1)
    #expect(calls.first?.function.name == "layer")
    #expect(calls.first?.function.arguments == #"{"action":"get"}"#)
}

@Test("nome fora da lista do servidor nunca roda")
func unknownToolNameIsRefused() {
    let text = """
    ```json
    {"tool_calls":[{"name":"wipe_everything","arguments":{}}]}
    ```
    """
    #expect(ToolCallTextRescue.rescue(from: text, knownTools: known) == nil)
}

@Test("prosa sem JSON não vira chamada")
func plainProseIsNotRescued() {
    let text = "A composição tem três camadas, acho eu."
    #expect(ToolCallTextRescue.rescue(from: text, knownTools: known) == nil)
}

@Test("JSON quebrado no meio não vira chamada")
func malformedJSONIsNotRescued() {
    let text = """
    ```json
    {"tool_calls":[{"name":"composition","arguments":
    ```
    """
    #expect(ToolCallTextRescue.rescue(from: text, knownTools: known) == nil)
}

@Test("chave com chave dentro de string não quebra o balanceamento")
func bracesInsideStringsDoNotBreakBalancing() {
    let text = #"{"tool_calls":[{"name":"status","arguments":{"note":"literal } aqui"}}]}"#
    let calls = ToolCallTextRescue.rescue(from: text, knownTools: known)?.calls ?? []
    #expect(calls.count == 1)
    #expect(calls.first?.function.arguments.contains("literal } aqui") == true)
}

@Test("sem ferramentas conhecidas o resgate fica desligado")
func emptyKnownListDisablesRescue() {
    let text = #"{"tool_calls":[{"name":"composition","arguments":{"action":"list"}}]}"#
    #expect(ToolCallTextRescue.rescue(from: text, knownTools: []) == nil)
}

@Test("resgate roda a ferramenta MCP e só então devolve a resposta final")
func engineExecutesRescuedCallBeforeAnswering() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    let backend = ScriptedChatTransport(script: [
        // Turno 1: o modelo escreve a chamada como texto, finish_reason "stop".
        // Raw string: aqui "\n" e '\"' são o escape do JSON, não do Swift.
        ScriptedChatTransport.textResponse(
            #"Vou olhar.\n```json\n{\"tool_calls\":[{\"name\":\"status\",\"arguments\":{\"action\":\"get\"}}]}\n```"#),
        // Turno 2: com o resultado da ferramenta no histórico, responde de verdade.
        ScriptedChatTransport.textResponse("Arena rodando."),
    ])
    let engine = ChatEngine(
        config: .init(apiKey: "test", model: "fm-local"),
        transport: backend,
        mcp: mcp)
    let answer = try await engine.send("Quantas camadas?")

    #expect(answer == "Arena rodando.")
    let bodies = await backend.requestBodies
    #expect(bodies.count == 2)
    let second = String(data: bodies[1], encoding: .utf8) ?? ""
    // A ferramenta tem que ter rodado de fato: resultado do MCP no histórico.
    #expect(second.contains("ok de status"))
    #expect(second.contains("\"tool\""))
    // E o bloco ```json não pode voltar como content para o modelo.
    let assistantTurns = second.components(separatedBy: "\"role\":\"assistant\"").count - 1
    #expect(assistantTurns >= 1)
    #expect(!second.contains("```json"))
}
