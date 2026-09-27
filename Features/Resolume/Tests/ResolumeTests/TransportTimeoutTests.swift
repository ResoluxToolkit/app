import Foundation
import Testing
@testable import Resolume

/// Regressao do -1001: o transporte usava `URLSession.shared`, que corta a
/// request em 60 s, e um turno local com as 22 ferramentas MCP levou ~118 s
/// (medido com qwen3:1.7b). Na UI isso aparecia como "conectou e nada acontece".
@Test("transporte padrao tem timeout acima do teto de 60 s do URLSession.shared")
func defaultTransportBeatsSharedCeiling() {
    let transport = URLSessionChatTransport()
    let configuration = transport.session.configuration  // nao-opcional neste SDK
    #expect(
        configuration.timeoutIntervalForRequest > 60,
        "timeout caiu para o teto do .shared: turno local morre em -1001")
    #expect(
        configuration.timeoutIntervalForResource
            >= URLSessionChatTransport.defaultRequestTimeout)
}

@Test("timeout do transporte e configuravel por backend")
func transportTimeoutIsConfigurable() {
    let transport = URLSessionChatTransport(timeout: 45)
    #expect(transport.session.configuration.timeoutIntervalForRequest == 45)
}
