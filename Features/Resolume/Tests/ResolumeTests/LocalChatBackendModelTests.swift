import Foundation
import Testing
@testable import Resolume

@Test("gateway local usa a URL, o modelo e a chave definidos pelo operador")
func localGatewayUsesOperatorConfig() {
    #expect(LocalChatBackend.localGatewayBaseURL.absoluteString == "http://127.0.0.1:8317/v1")
    #expect(LocalChatBackend.localGatewayModel == "gemini-3.8-flash-high")

    let backend = LocalChatBackend(
        kind: .localGateway,
        baseURL: LocalChatBackend.localGatewayBaseURL,
        model: LocalChatBackend.localGatewayModel)

    #expect(backend.apiKey == "123456")
    #expect(backend.toolAllowlist == nil, "gateway local recebe as 22 ferramentas")
    #expect(backend.displayName == LocalChatBackend.localGatewayModel)
}

@Test("Apple FM mantém chave local e subset medido")
func appleFMKeepsLocalKeyAndSubset() {
    let backend = LocalChatBackend(
        kind: .appleFoundationModels,
        baseURL: URL(string: "http://127.0.0.1:1976/v1")!,
        model: "system")

    #expect(backend.apiKey == "resolux-local")
    #expect(backend.toolAllowlist == LocalChatBackend.appleToolSubset)
}
