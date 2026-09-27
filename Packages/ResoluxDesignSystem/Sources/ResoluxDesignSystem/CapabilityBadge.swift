import ResoluxCore
import SwiftUI

public struct CapabilityBadge: View {
    public let capability: Capability
    public var platform: PlatformTarget = .current

    public init(capability: Capability, platform: PlatformTarget = .current) {
        self.capability = capability
        self.platform = platform
    }

    public var body: some View {
        let available = capability.isAvailable(on: platform)
        Label(capability.title, systemImage: available ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(available ? .resoluxAccent : .secondary)
    }
}
