import Testing

@testable import ResoluxCore

private let capture = Capability(
    id: "capture", title: "Captura", availability: [.macOS])
private let share = Capability(
    id: "share", title: "Compartilhar", availability: [.macOS, .iOS])

@Test("filtra capacidades pela plataforma")
func filtersByPlatform() {
    var catalog = CapabilityCatalog([capture, share])
    #expect(catalog.capabilities(for: .iOS).map(\.id) == ["share"])
    #expect(catalog.capabilities(for: .macOS).map(\.id) == ["capture", "share"])
    catalog.register(Capability(id: "air", title: "Air", availability: [.iOS]))
    #expect(catalog.capabilities(for: .iOS).count == 2)
}

@Test("lista o que falta para a plataforma")
func listsUnsupported() {
    let catalog = CapabilityCatalog([share])
    #expect(catalog.unsupported(from: ["share", "capture"], on: .iOS) == ["capture"])
    #expect(catalog.unsupported(from: ["share"], on: .iOS).isEmpty)
}
