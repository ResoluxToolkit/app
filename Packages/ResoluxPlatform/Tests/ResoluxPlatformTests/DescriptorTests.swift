import ResoluxCore
import Testing

@testable import ResoluxPlatform

@Test("cada plataforma declara suas capacidades")
func descriptorMatchesPlatform() {
    let mac = PlatformDescriptor(target: .macOS)
    let phone = PlatformDescriptor(target: .iOS)
    #expect(mac.supportsMenus && !mac.supportsHaptics)
    #expect(phone.supportsHaptics && !phone.supportsMenus)
    #expect(mac.windowStyle == .freeform)
}
