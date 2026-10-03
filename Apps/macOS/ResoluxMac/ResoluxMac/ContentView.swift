import ResoluxCore
import ResoluxPlatform
import ResolumeUI
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
        TabView {
            ArenaMonitorView()
                .tabItem { Label("Monitor", systemImage: "display") }
            NavigationStack {
                StarterView(report: report)
                    .navigationTitle("Resolux")
            }
            .tabItem { Label("Starter", systemImage: "wrench.and.screwdriver") }
        }
        .navigationTitle("Resolux")
    }
}

#Preview {
    ContentView()
}
