import ResoluxCore
import ResoluxPlatform
import Testing
import Starter

@Test("relatório lista apenas capacidades da plataforma")
func reportFiltersPlatform() {
    let catalog = CapabilityCatalog([
        Capability(id: "capture", title: "Captura", availability: [.macOS]),
        Capability(id: "share", title: "Compartilhar", availability: [.macOS, .iOS]),
    ])
    let report = CapabilityReport(catalog: catalog, descriptor: PlatformDescriptor(target: .iOS))
    #expect(report.rows.map(\.capability.id) == ["capture", "share"])
    #expect(report.rows.first(where: { $0.capability.id == "capture"})?.available == false)
    #expect(report.missing(from: ["capture"]) == ["capture"])
}
