import ResoluxCore
import ResoluxPlatform
import Starter
import StarterUI
import SwiftUI

struct ContentView: View {
    private let report = CapabilityReport(
        catalog: CapabilityCatalog([
            Capability(id: "capture", title: "Captura", availability: [.macOS]),
            Capability(id: "share", title: "Compartilhar", availability: [.macOS, .iOS]),
        ]),
        descriptor: .current)

    var body: some View {
        NavigationStack {
            StarterView(report: report)
                .navigationTitle("Resolux")
        }
    }
}

#Preview {
    ContentView()
}
