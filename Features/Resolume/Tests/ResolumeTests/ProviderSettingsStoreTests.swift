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
