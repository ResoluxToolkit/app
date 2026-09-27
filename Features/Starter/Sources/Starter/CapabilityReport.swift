import Foundation
import ResoluxCore
import ResoluxPlatform

public struct CapabilityReport: Sendable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let capability: Capability
        public let available: Bool

        public var id: String { capability.id }
    }

    public let platform: PlatformTarget
    public let rows: [Row]

    public init(catalog: CapabilityCatalog, descriptor: PlatformDescriptor) {
        platform = descriptor.target
        rows = catalog.allCapabilities().map {
            Row(capability: $0, available: $0.isAvailable(on: descriptor.target))
        }
    }

    public func missing(from requested: [String]) -> [String] {
        CapabilityCatalog(rows.map(\.capability)).unsupported(from: requested, on: platform)
    }
}
