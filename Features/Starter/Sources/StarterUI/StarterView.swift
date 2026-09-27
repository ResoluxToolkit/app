import ResoluxCore
import ResoluxDesignSystem
import ResoluxPlatform
import Starter
import SwiftUI

public struct StarterView: View {
    private let report: CapabilityReport

    public init(report: CapabilityReport) {
        self.report = report
    }

    public var body: some View {
        List(report.rows) { row in
            HStack {
                if row.available {
                    CapabilityBadge(capability: row.capability, platform: report.platform)
                } else {
                    Label(row.capability.title + " (indisponível)", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

public struct StarterView_Previews: PreviewProvider {
    public static var previews: some View {
        StarterView(report: .preview(for: .macOS))
        StarterView(report: .preview(for: .iOS))
    }
}

extension CapabilityReport {
    public static func preview(for platform: PlatformTarget) -> CapabilityReport {
        CapabilityReport(
            catalog: CapabilityCatalog([
                Capability(id: "capture", title: "Captura", availability: [.macOS]),
                Capability(id: "share", title: "Compartilhar", availability: [.macOS, .iOS]),
            ]),
            descriptor: PlatformDescriptor(target: platform))
    }
}
