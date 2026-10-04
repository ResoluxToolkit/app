import Foundation
import Security

public struct ProviderSettings: Equatable, Sendable {
    public var endpointText: String
    public var token: String
    public var modelID: String
    public var isReadOnly: Bool

    public init(
        endpointText: String = "",
        token: String = "",
        modelID: String = "",
        isReadOnly: Bool = true
    ) {
        self.endpointText = endpointText
        self.token = token
        self.modelID = modelID
        self.isReadOnly = isReadOnly
    }

    public var endpointURL: URL? {
        guard let url = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    public var chatEndpointURL: URL? {
        guard let baseURL = endpointURL else { return nil }
        var text = baseURL.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        guard let cleanURL = URL(string: text) else { return nil }
        if cleanURL.path(percentEncoded: false)
            .lowercased()
            .hasSuffix("/chat/completions") {
            return cleanURL
        }
        return URL(string: "\(text)/chat/completions")
    }

    public var isConfigured: Bool {
        chatEndpointURL != nil && !token.isEmpty && !modelID.isEmpty
    }
}

public enum ProviderSettingsError: LocalizedError, Equatable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain retornou \(status)."
        }
    }
}

public protocol ProviderTokenStore: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
}

public struct KeychainProviderTokenStore: ProviderTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.smartium.resolux", account: String = "provider-token") {
        self.service = service
        self.account = account
    }

    public func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw ProviderSettingsError.keychain(status)
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveToken(_ token: String) throws {
        if token.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw ProviderSettingsError.keychain(status)
            }
            return
        }

        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard updateStatus != errSecItemNotFound else {
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ProviderSettingsError.keychain(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw ProviderSettingsError.keychain(updateStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
