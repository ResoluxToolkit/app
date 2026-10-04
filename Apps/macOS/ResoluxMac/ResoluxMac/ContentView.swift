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
            if #available(macOS 26.0, *) {
                AssistantView()
                    .tabItem { Label("Assistente", systemImage: "sparkles") }
            } else {
                Text("Assistente requer macOS 26 ou mais novo.")
                    .tabItem { Label("Assistente", systemImage: "sparkles") }
            }
            NavigationStack {
                StarterView(report: report)
                    .navigationTitle("Resolux")
            }
            .tabItem { Label("Starter", systemImage: "wrench.and.screwdriver") }
            ProviderSettingsView()
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .navigationTitle("Resolux")
    }
}

#Preview {
    ContentView()
}
