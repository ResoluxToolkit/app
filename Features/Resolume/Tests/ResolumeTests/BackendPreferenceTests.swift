import Foundation
import Testing
@testable import Resolume

/// Prende o voto do operador sobre backend default (DUVIDAS 3 / HANDOFF 0).
/// A preferencia e Apple FM de cara; Ollama e a rede de seguranca de quem nao
/// configurou o `fm serve`. Inverter isso de novo sem voto é exatamente o que
/// este arquivo impede.

private func apple() -> LocalChatBackend {
    LocalChatBackend(kind: .appleFoundationModels,
                     baseURL: URL(string: "http://127.0.0.1:1976/v1")!, model: "system")
}

private func ollama() -> LocalChatBackend {
    LocalChatBackend(kind: .ollama,
                     baseURL: URL(string: "http://127.0.0.1:11434/v1")!, model: "qwen3:1.7b")
}

@Test("de cara é Apple FM, com os dois respondendo")
func appleWinsWhenBothAreUp() {
    let ordem = LocalChatBackend.preferredOrder([ollama(), apple()])
    #expect(ordem.map(\.kind) == [.appleFoundationModels, .ollama])
}

@Test("sem Apple configurado, Ollama assume (nenhum usuário fica sem bot)")
func ollamaCarriesTheProductWhenAppleIsMissing() {
    let ordem = LocalChatBackend.preferredOrder([ollama()])
    #expect(ordem.map(\.kind) == [.ollama])
}

@Test("Apple sozinho responde o que pode")
func appleAloneIsEnough() {
    let ordem = LocalChatBackend.preferredOrder([apple()])
    #expect(ordem.map(\.kind) == [.appleFoundationModels])
}

@Test("nada vira download: a ordem só reordena o que já está de pé")
func orderingNeverInventsABackend() {
    #expect(LocalChatBackend.preferredOrder([]).isEmpty)
    let tres = [ollama(), apple(), ollama()]
    #expect(LocalChatBackend.preferredOrder(tres).count == 3)
}
