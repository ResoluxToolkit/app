import ResoluxCore
import ResoluxPlatform
import ResolumeUI
import Starter
import StarterUI
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var tabSnapshot: Int?

    private let report = CapabilityReport(
        catalog: CapabilityCatalog([
            Capability(id: "capture", title: "Captura", availability: [.macOS]),
            Capability(id: "share", title: "Compartilhar", availability: [.macOS, .iOS]),
        ]),
        descriptor: .current)

    var body: some View {
        TabView {
            QuickPlayView()
                .tag(0)
                .tabItem { Label("Quick Play", systemImage: "play.rectangle.on.rectangle") }
            ContinuityCameraView()
                .tag(1)
                .tabItem { Label("Câmera", systemImage: "video.fill") }
            ArenaMonitorView()
                .tag(2)
                .tabItem { Label("Monitor", systemImage: "display") }
            if #available(macOS 26.0, *) {
                AssistantView()
                    .tag(3)
                    .tabItem { Label("Assistente", systemImage: "sparkles") }
            } else {
                Text("Assistente requer macOS 26 ou mais novo.")
                    .tag(3)
                    .tabItem { Label("Assistente", systemImage: "sparkles") }
            }
            StarterView(report: report)
                .tag(4)
                .tabItem { Label("Starter", systemImage: "wrench.and.screwdriver") }
            ProviderSettingsView()
                .tag(5)
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .navigationTitle("Resolux")
        .correriaDropTarget(
            snapshot: {
                tabSnapshot = selectedTab
            },
            restore: {
                if let tabSnapshot {
                    selectedTab = tabSnapshot
                }
                tabSnapshot = nil
            }
        )
    }
}

#Preview {
    ContentView()
}
