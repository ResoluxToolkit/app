import ResoluxCore

/// Único lugar do toolkit onde divergência de plataforma é resolvida em tempo de compilação.
/// Qualquer `#if os(...)` fora deste arquivo é bug de arquitetura.
public struct PlatformDescriptor: Sendable {
    public let target: PlatformTarget
    public let supportsMenus: Bool
    public let supportsHaptics: Bool
    public let windowStyle: WindowStyle

    public enum WindowStyle: String, Sendable {
        case freeform
        case fullscreenOnly
    }

    public init(target: PlatformTarget) {
        self.target = target
        switch target {
        case .macOS:
            supportsMenus = true
            supportsHaptics = false
            windowStyle = .freeform
        case .iOS:
            supportsMenus = false
            supportsHaptics = true
            windowStyle = .fullscreenOnly
        }
    }

    public static var current: PlatformDescriptor {
        PlatformDescriptor(target: .current)
    }
}
