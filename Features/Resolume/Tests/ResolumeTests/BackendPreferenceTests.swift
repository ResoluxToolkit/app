import Foundation
import Testing
@testable import Resolume

/// Prende o voto do operador sobre backend default (DUVIDAS 3 / HANDOFF 0).
/// A preferencia (voto 2026-10-03) e o gateway local de cara, com as 22
/// ferramentas; o Apple FM e a rede de seguranca quando o gateway nao responde.
/// configurou o `fm serve`. Inverter isso de novo sem voto é exatamente o que
/// este arquivo impede.

private func apple() -> LocalChatBackend {
    LocalChatBackend(kind: .appleFoundationModels,
                     baseURL: URL(string: "http://127.0.0.1:1976/v1")!, model: "system")
}

private func gateway() -> LocalChatBackend {
    LocalChatBackend(kind: .localGateway,
                     baseURL: URL(string: "http://127.0.0.1:8317/v1")!, model: "gemini-3.8-flash-high")
}

@Test("de cara é Apple FM, com os dois respondendo")
func gatewayWinsWhenBothAreUp() {
    let ordem = LocalChatBackend.preferredOrder([gateway(), apple()])
    #expect(ordem.map(\.kind) == [.localGateway, .appleFoundationModels])
}

@Test("sem gateway configurado, o Apple FM assume (nenhum usuário fica sem bot)")
func appleCarriesTheProductWhenGatewayIsMissing() {
    let ordem = LocalChatBackend.preferredOrder([apple()])
    #expect(ordem.map(\.kind) == [.appleFoundationModels])
}

@Test("Apple sozinho responde o que pode")
func appleAloneIsEnough() {
    let ordem = LocalChatBackend.preferredOrder([apple()])
    #expect(ordem.map(\.kind) == [.appleFoundationModels])
}

@Test("nada vira download: a ordem só reordena o que já está de pé")
func orderingNeverInventsABackend() {
    #expect(LocalChatBackend.preferredOrder([]).isEmpty)
    let tres = [gateway(), apple(), gateway()]
    #expect(LocalChatBackend.preferredOrder(tres).count == 3)
}
