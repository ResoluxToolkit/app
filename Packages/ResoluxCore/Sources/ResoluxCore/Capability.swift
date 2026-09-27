public struct Capability: Hashable, Sendable {
    public let id: String
    public let title: String
    public let availability: Set<PlatformTarget>

    public init(id: String, title: String, availability: [PlatformTarget]) {
        self.id = id
        self.title = title
        self.availability = Set(availability)
    }

    public func isAvailable(on platform: PlatformTarget) -> Bool {
        availability.contains(platform)
    }
}
