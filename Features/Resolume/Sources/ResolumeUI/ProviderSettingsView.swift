import BorderBeamKit
import ResoluxDesignSystem
import Resolume
import SwiftUI

public struct ProviderSettingsView: View {
    @State private var model = ProviderSettingsStore.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        GlassCard(cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Provedor / modelo", systemImage: "cpu")
                                    .font(.headline)
                                    .foregroundStyle(Palette.foreground)

                                providerField("Endpoint URL") {
                                    TextField("https://provedor.local/v1", text: $model.endpointText)
                                }
                                providerField("Token") {
                                    SecureField("token do provedor", text: $model.token)
                                }
                                providerField("ID do Modelo") {
                                    TextField("nome-do-modelo", text: $model.modelID)
                                }

                                Toggle(isOn: $model.isReadOnly) {
                                    Text("Somente-leitura")
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.foreground)
                                }
                                .toggleStyle(.switch)

                                HStack {
                                    Text(model.isReadOnly ? "MCP fica read-only" : "MCP pode escrever")
                                        .font(.caption)
                                        .foregroundStyle(Palette.muted)
                                    Spacer()
                                    GlowButton(title: "Salvar", symbol: "checkmark.circle") {
                                        do {
                                            try model.save()
                                        } catch {
                                            model.saveMessage = error.localizedDescription
                                        }
                                    }
                                }

                                if let message = model.saveMessage {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("O provedor precisa expor `/chat/completions` compatível com OpenAI.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Ajustes")
        }
    }

    @ViewBuilder
    private func providerField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(0.7)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}
