import Foundation
import Testing
@testable import Resolume

private func args(_ pairs: [String: MCPValue]) -> [String: MCPValue] { pairs }

@Test("modo leitura bloqueia escrita real que um modelo cometeu")
func readOnlyBlocksTheExactBug() {
    // transport { action: "set", bpm: 120 } mudou o BPM de um set em uso, ao vivo.
    #expect(!ToolPolicy.readOnly.allows(tool: "transport", arguments: args(["action": .string("set")])))
    #expect(ToolPolicy.readOnly.allows(tool: "transport", arguments: args(["action": .string("get")])))
    #expect(ToolPolicy.readWrite.allows(tool: "transport", arguments: args(["action": .string("set")])))
}

@Test("invencao de acao e tratada como escrita")
func unknownActionIsRefused() {
    // transform{action:"move"} nao existe no enum do Arena.
    #expect(!ToolPolicy.readOnly.allows(tool: "transform", arguments: args(["action": .string("move")])))
    // sem action entao nem tentativa de leitura e.
    #expect(!ToolPolicy.readOnly.allows(tool: "monitor", arguments: args([:])))
    // batch executa operacoes quaisquer.
    #expect(!ToolPolicy.readOnly.allows(tool: "batch", arguments: args(["operations": .array([])])))
    // style/technique usam tema criativo como acao: nunca leitura.
    #expect(!ToolPolicy.readOnly.allows(tool: "style", arguments: args(["action": .string("glitch")])))
}

@Test("cobertura de leitura bate com o enum real do servidor")
func safeActionsExistInTheRealSchema() throws {
    // tools/list capturado do Arena 7.28.0-rev24303 vivo, como resource do teste.
    guard let url = Bundle.module.url(forResource: "tools-schema", withExtension: "json") else {
        Issue.record("fixture tools-schema.json ausente no bundle de testes"); return
    }
    let schema = try JSONDecoder().decode(RawToolsList.self, from: Data(contentsOf: url))
    var real: [String: Set<String>] = [:]
    for tool in schema.result.tools {
        var actions: [String] = []
        if let action = tool.inputSchema?["properties"]?["action"]?.objectValue,
           let enums = action["enum"]?.arrayValue {
            actions = enums.compactMap { $0.stringValue }
        }
        real[tool.name] = Set(actions)
    }
    for (tool, actions) in ToolPolicy.safeActions {
        guard let realActions = real[tool] else {
            Issue.record("ferramenta \(tool) nao existe no servidor real")
            continue
        }
        for action in actions where !realActions.contains(action) {
            Issue.record("\(tool).\(action) nao esta no enum real do servidor")
        }
    }
}

@Test("recusa devolve instrucao acionavel para o modelo")
func refusalTellsTheModelWhatToDo() {
    let text = ToolPolicy.refusal(tool: "transport", action: "set")
    #expect(text.contains("blocked"))
    #expect(text.contains("transport.set"))
    #expect(text.contains("confirmação"))
}

@Test("modo escrita NUNCA converte clipe nem reescreve o show")
func writeModeStillBlocksIrreversibleAndRetimedActions() {
    // Caso literal do operador: BPM global ninguém usa; converter o CLIPE "aí fodeu tudo".
    let rw = ToolPolicy.readWrite
    #expect(!rw.allows(tool: "clip", arguments: args(["action": .string("set_transport")])))
    // O .avc é fotografia do estado atual; escrever por cima perde o show do operador.
    #expect(!rw.allows(tool: "composition", arguments: args(["action": .string("save_as")])))
    #expect(!rw.allows(tool: "composition", arguments: args(["action": .string("open")])))
    // batch e a porta dos fundos das duas acima.
    #expect(!rw.allows(tool: "batch", arguments: args(["operations": .array([])])))
    // e destruicao de conteúdo continua barrada
    #expect(!rw.allows(tool: "layer", arguments: args(["action": .string("clear_clips")])))
    // Escrita lícita continua passando: o gate nao virou um readOnly disfarçado.
    #expect(rw.allows(tool: "transport", arguments: args(["action": .string("set")])))
    #expect(rw.allows(tool: "clip", arguments: args(["action": .string("rename")])))
    #expect(rw.allows(tool: "parameter", arguments: args(["action": .string("set")])))
}

@Test("veto permanente nao se confunde com bloqueio de leitura no texto")
func refusalTextMatchesTheRealReason() {
    // Em modo escrita a recusa nao pode alegar "somente leitura": seria mentira
    // e o modelo insistiria achando que basta ligar a permissão.
    let decision = ToolPolicy.readWrite.decide(
        tool: "clip", arguments: args(["action": .string("set_transport")]))
    #expect(decision.isNever)
    let text = ToolPolicy.refusal(tool: "clip", action: "set_transport", alwaysBlocked: decision.isNever)
    #expect(text.contains("proibida em qualquer modo"))
    #expect(!text.contains("Modo somente leitura"))
    let gated = ToolPolicy.refusal(tool: "clip", action: "rename", alwaysBlocked: false)
    #expect(gated.contains("Modo somente leitura"))
}

@Test("nomes do veto permanente existem no enum real do servidor")
func neverActionsExistInTheRealSchema() throws {
    // Mesma guarda dos safeActions: já inventei ferramenta demais nessa história.
    guard let url = Bundle.module.url(forResource: "tools-schema", withExtension: "json") else {
        Issue.record("fixture tools-schema.json ausente no bundle de testes"); return
    }
    let schema = try JSONDecoder().decode(RawToolsList.self, from: Data(contentsOf: url))
    var real: [String: Set<String>] = [:]
    for tool in schema.result.tools {
        var actions: [String] = []
        if let action = tool.inputSchema?["properties"]?["action"]?.objectValue,
           let enums = action["enum"]?.arrayValue {
            actions = enums.compactMap { $0.stringValue }
        }
        real[tool.name] = Set(actions)
    }
    for (tool, actions) in ToolPolicy.neverActions {
        guard let realActions = real[tool] else {
            Issue.record("ferramenta \(tool) nao existe no servidor real")
            continue
        }
        for action in actions where !realActions.contains(action) {
            Issue.record("\(tool).\(action) nao esta no enum real do servidor")
        }
    }
    // safeActions e neverActions precisam ser disjuntos: interseção = regra morta.
    for (tool, never) in ToolPolicy.neverActions {
        if let safe = ToolPolicy.safeActions[tool] {
            let overlap = never.intersection(safe)
            if !overlap.isEmpty {
                Issue.record("\(tool): ação listada como leitura e como veto: \(overlap.sorted())")
            }
        }
    }
}

private struct RawToolsList: Decodable {
    struct Result: Decodable { struct Tool: Decodable { let name: String; let inputSchema: [String: MCPValue]? }
        let tools: [Tool] }
    let result: Result
}
