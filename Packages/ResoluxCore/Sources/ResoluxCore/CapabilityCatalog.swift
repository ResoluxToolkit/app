public struct CapabilityCatalog: Sendable {
    private var storage: [String: Capability]

    public init(_ capabilities: [Capability] = []) {
        storage = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0) })
    }

    public mutating func register(_ capability: Capability) {
        storage[capability.id] = capability
    }

    public func capability(id: String) -> Capability? {
        storage[id]
    }

    public func capabilities(for platform: PlatformTarget) -> [Capability] {
        storage.values.filter { $0.isAvailable(on: platform) }.sorted { $0.id < $1.id }
    }

    public func allCapabilities() -> [Capability] {
        storage.values.sorted { $0.id < $1.id }
    }

    public func unsupported(from requested: [String], on platform: PlatformTarget) -> [String] {
        requested.filter { capability(id: $0)?.isAvailable(on: platform) != true }
    }
}
