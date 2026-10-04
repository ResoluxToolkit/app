import Foundation
import Testing
@testable import Resolume

@Test("endpoint aceita base OpenAI e caminho completo de chat completions")
func endpointNormalization() {
    let base = ProviderSettings(endpointText: "http://127.0.0.1:8317/v1")
    #expect(base.chatEndpointURL?.absoluteString == "http://127.0.0.1:8317/v1/chat/completions")

    let full = ProviderSettings(endpointText: "https://provider.test/v1/chat/completions/")
    #expect(full.chatEndpointURL?.absoluteString == "https://provider.test/v1/chat/completions")
}

@Test("endpoint recusa protocolo sem HTTP")
func endpointRejectsNonHTTPTargets() {
    #expect(ProviderSettings(endpointText: "ftp://provider.test/v1").endpointURL == nil)
    #expect(ProviderSettings(endpointText: "file:///tmp").endpointURL == nil)
}
