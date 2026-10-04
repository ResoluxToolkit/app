import Foundation
import Observation
import Resolume

@Observable
@MainActor
public final class ProviderSettingsStore {
    public static let shared = ProviderSettingsStore()

    public var endpointText: String
    public var token: String
    public var modelID: String
    public var isReadOnly: Bool
    public var saveMessage: String?

    private let defaults: UserDefaults
    private let tokenStore: any ProviderTokenStore

    public init(
        defaults: UserDefaults = .standard,
        tokenStore: any ProviderTokenStore = KeychainProviderTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        endpointText = defaults.string(forKey: ProviderSettingsStore.endpointKey) ?? ""
        modelID = defaults.string(forKey: ProviderSettingsStore.modelKey) ?? ""
        token = (try? tokenStore.loadToken()) ?? ""
        isReadOnly = defaults.object(forKey: ProviderSettingsStore.readOnlyKey) as? Bool ?? true
    }

    public var settings: ProviderSettings {
        ProviderSettings(
            endpointText: endpointText,
            token: token,
            modelID: modelID,
            isReadOnly: isReadOnly)
    }

    public var persistedSettings: ProviderSettings {
        ProviderSettings(
            endpointText: defaults.string(forKey: ProviderSettingsStore.endpointKey) ?? "",
            token: (try? tokenStore.loadToken()) ?? "",
            modelID: defaults.string(forKey: ProviderSettingsStore.modelKey) ?? "",
            isReadOnly: defaults.object(forKey: ProviderSettingsStore.readOnlyKey) as? Bool ?? true)
    }

    public func save() throws {
        guard settings.isConfigured else {
            saveMessage = "Preencha Endpoint URL, Token e ID do Modelo."
            return
        }
        try tokenStore.saveToken(token)
        defaults.set(endpointText, forKey: ProviderSettingsStore.endpointKey)
        defaults.set(modelID, forKey: ProviderSettingsStore.modelKey)
        defaults.set(isReadOnly, forKey: ProviderSettingsStore.readOnlyKey)
        saveMessage = "Configuração salva."
    }

    private static let endpointKey = "resolux.provider.endpoint"
    private static let modelKey = "resolux.provider.model"
    private static let readOnlyKey = "resolux.provider.readOnly"
}
