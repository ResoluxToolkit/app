import Foundation
import Testing
@testable import Resolume
@testable import ResolumeUI

private final class FakeProviderTokenStore: ProviderTokenStore, @unchecked Sendable {
    private(set) var token: String?

    func loadToken() throws -> String? { token }

    func saveToken(_ token: String) throws {
        self.token = token.isEmpty ? nil : token
    }
}

@MainActor
@Test("auto-rolagem da conversa: habilitada por padrão e persistida na hora")
func autoScrollDefaultsOnAndPersistsImmediately() throws {
    let suiteName = "resolux.provider-settings-store-tests-autoscroll"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = ProviderSettingsStore(defaults: defaults, tokenStore: FakeProviderTokenStore())
    #expect(store.isAutoScrollEnabled == true)
    store.isAutoScrollEnabled = false

    let reloaded = ProviderSettingsStore(defaults: defaults, tokenStore: FakeProviderTokenStore())
    #expect(reloaded.isAutoScrollEnabled == false)
}

@MainActor
@Test("loja persiste config no UserDefaults e token no armazenamento seguro")
func storePersistsConfiguration() throws {
    let suiteName = "resolux.provider-settings-store-tests"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let tokenStore = FakeProviderTokenStore()

    let store = ProviderSettingsStore(defaults: defaults, tokenStore: tokenStore)
    #expect(store.isReadOnly == true)
    store.endpointText = "http://127.0.0.1:8317/v1"
    store.token = "token-secreto"
    store.modelID = "modelo-teste"
    store.isReadOnly = false
    try store.save()

    let reloaded = ProviderSettingsStore(defaults: defaults, tokenStore: tokenStore)
    #expect(reloaded.endpointText == "http://127.0.0.1:8317/v1")
    #expect(reloaded.modelID == "modelo-teste")
    #expect(reloaded.isReadOnly == false)
    #expect(reloaded.token == "token-secreto")

    store.endpointText = "não-salvo"
    store.token = "não-salvo"
    store.modelID = "não-salvo"
    #expect(store.persistedSettings.endpointText == "http://127.0.0.1:8317/v1")
    #expect(store.persistedSettings.token == "token-secreto")
}

@MainActor
@Test("botão de teste chama /chat/completions e mostra a resposta")
func testModelShowsProviderAnswer() async {
    let defaults = UserDefaults.standard
    let transport = ProviderModelTestTransport(response: .success("ok"))
    let store = ProviderSettingsStore(defaults: defaults, tokenStore: FakeProviderTokenStore(), transport: transport)
    store.endpointText = "http://127.0.0.1:9999/v1"
    store.token = "token-teste"
    store.modelID = "modelo-teste"

    await store.testModel()

    #expect(store.testMessage == "Modelo respondeu: ok")
    let request = await transport.lastRequest
    #expect(request?.endpoint.absoluteString == "http://127.0.0.1:9999/v1/chat/completions")
    #expect(String(data: request?.body ?? Data(), encoding: .utf8)?.contains("modelo-teste") == true)
}

@MainActor
@Test("switch Somente-leitura define o ToolPolicy usado no chat")
func readOnlySwitchSetsToolPolicy() throws {
    let suiteName = "resolux.provider-tool-policy-tests"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = ProviderSettingsStore(
        defaults: defaults,
        tokenStore: FakeProviderTokenStore())
    store.endpointText = "http://127.0.0.1:8317/v1"
    store.token = "token"
    store.modelID = "modelo"

    store.isReadOnly = true
    try store.save()
    #expect(store.toolPolicy == ToolPolicy(mode: .readOnly))

    store.isReadOnly = false
    try store.save()
    #expect(store.toolPolicy == ToolPolicy(mode: .readWrite))
}

private actor ProviderModelTestTransport: ChatBackendTransport {
    enum Result {
        case success(String)
        case failure(Error)
    }

    let result: Result
    private(set) var lastRequest: (endpoint: URL, body: Data)?

    init(response: Result) { self.result = response }

    func complete(endpoint: URL, apiKey: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        lastRequest = (endpoint, body)
        switch result {
        case .success(let text):
            let json = """
            {"choices":[{"message":{"role":"assistant","content":"\(text)"},"finish_reason":"stop"}]}
            """
            let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        case .failure(let error):
            throw error
        }
    }
}
