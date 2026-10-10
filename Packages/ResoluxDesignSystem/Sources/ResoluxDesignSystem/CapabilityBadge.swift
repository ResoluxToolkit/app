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
        HStack(spacing: 6) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? Palette.cyan : Palette.muted)
            Text(capability.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(available ? .white : Palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(CapabilityBadgeGlassModifier(available: available))
    }
}

private struct CapabilityBadgeGlassModifier: ViewModifier {
    let available: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear.tint(available ? Palette.cyan.opacity(0.12) : Color.white.opacity(0.04)), in: Capsule())
                .overlay(Capsule().strokeBorder(available ? Palette.cyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
        } else {
            content
                .background(Capsule().fill(available ? Palette.cyan.opacity(0.12) : Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(available ? Palette.cyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}
