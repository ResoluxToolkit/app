import Foundation
import ResoluxCore

public enum ResolumeProduct: String, Sendable, Codable, CaseIterable {
    case arena
    case wire

    public var appName: String {
        switch self {
        case .arena: "Resolume Arena"
        case .wire: "Resolume Wire"
        }
    }

    /// Caminho do executável MCP empacotado pelo fabricante.
    public var mcpExecutablePath: String {
        "/Applications/\(appName)/mcp/resolume_\(rawValue)_mcp_server"
    }

    /// Unix socket do REST API, criado pelo app quando ele está aberto.
    /// O servidor MCP trava em tools/list sem esse socket — é o gate de prontidão.
    public var restSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/\(appName)/rest-api.sock"
    }

    /// Prontidão real: o Arena precisa *atender* o socket REST, não só ter
    /// deixado o arquivo para trás ao fechar.
    public func isResponsive() -> Bool {
        UnixSocketProbe.isAcceptingConnections(atPath: restSocketPath)
    }

    /// O servidor MCP só existe no host macOS (Arena/Wire são apps desktop).
    public var capability: Capability {
        Capability(
            id: "resolume.mcp.\(rawValue)",
            title: "Servidor MCP \(appName)",
            availability: [.macOS])
    }
}

public struct ResolumeInstallation: Sendable, Equatable {
    public let product: ResolumeProduct
    public let executableURL: URL
    public let bundleVersion: String?

    public init(product: ResolumeProduct, executableURL: URL, bundleVersion: String?) {
        self.product = product
        self.executableURL = executableURL
        self.bundleVersion = bundleVersion
    }
}

public enum ResolumeLocator {
    /// Descobre instalações de Arena/Wire com servidor MCP disponível.
    public static func discover(fileManager: FileManager = .default) -> [ResolumeInstallation] {
        ResolumeProduct.allCases.compactMap { product in
            let path = product.mcpExecutablePath
            guard fileManager.isExecutableFile(atPath: path) else { return nil }
            let version = bundleVersion(appName: product.appName, fileManager: fileManager)
            return ResolumeInstallation(
                product: product,
                executableURL: URL(fileURLWithPath: path),
                bundleVersion: version)
        }
    }

    private static func bundleVersion(appName: String, fileManager: FileManager) -> String? {
        let plistURL = URL(fileURLWithPath: "/Applications/\(appName)/Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        return version
    }
}
