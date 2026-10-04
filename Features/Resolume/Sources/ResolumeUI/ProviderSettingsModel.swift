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
    /// Comportamento da conversa: cada mudança persiste na hora (sem botão
    /// Salvar, porque não é config de provedor).
    public var isAutoScrollEnabled: Bool {
        didSet {
            guard isAutoScrollEnabled != oldValue else { return }
            defaults.set(isAutoScrollEnabled, forKey: Self.autoScrollKey)
        }
    }
    public var saveMessage: String?
    public var isTestingModel = false
    public var testMessage: String?

    private let defaults: UserDefaults
    private let tokenStore: any ProviderTokenStore
    private let transport: any ChatBackendTransport

    public init(
        defaults: UserDefaults = .standard,
        tokenStore: any ProviderTokenStore = KeychainProviderTokenStore(),
        transport: any ChatBackendTransport = URLSessionChatTransport(timeout: 15)
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.transport = transport
        endpointText = defaults.string(forKey: ProviderSettingsStore.endpointKey) ?? ""
        modelID = defaults.string(forKey: ProviderSettingsStore.modelKey) ?? ""
        token = (try? tokenStore.loadToken()) ?? ""
        isReadOnly = defaults.object(forKey: ProviderSettingsStore.readOnlyKey) as? Bool ?? true
        isAutoScrollEnabled = defaults.object(forKey: ProviderSettingsStore.autoScrollKey) as? Bool ?? true
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

    public var toolPolicy: ToolPolicy {
        ToolPolicy(mode: persistedSettings.isReadOnly ? .readOnly : .readWrite)
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

    public func testModel() async {
        let configured = settings
        guard let endpoint = configured.chatEndpointURL else {
            testMessage = "Endpoint URL inválido."
            return
        }
        guard !configured.token.isEmpty, !configured.modelID.isEmpty else {
            testMessage = "Preencha Token e ID do Modelo."
            return
        }

        isTestingModel = true
        defer { isTestingModel = false }
        testMessage = nil

        let request = ChatCompletionRequest(
            model: configured.modelID,
            messages: [.user("Responda apenas: ok")],
            stream: false)

        do {
            let body = try JSONEncoder().encode(request)
            let (data, _) = try await transport.complete(
                endpoint: endpoint,
                apiKey: configured.token,
                body: body)
            let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let answer = response.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
                throw ChatError.noChoices
            }
            testMessage = "Modelo respondeu: \(answer)"
        } catch {
            testMessage = "Teste falhou: \(error.localizedDescription)"
        }
    }

    private static let endpointKey = "resolux.provider.endpoint"
    private static let modelKey = "resolux.provider.model"
    private static let readOnlyKey = "resolux.provider.readOnly"
    private static let autoScrollKey = "resolux.assistant.autoScroll"
}
