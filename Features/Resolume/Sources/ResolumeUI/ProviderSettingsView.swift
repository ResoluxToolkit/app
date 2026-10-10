import BorderBeamKit
import ResoluxDesignSystem
import Resolume
import SwiftUI

public struct ProviderSettingsView: View {
    @State private var model = ProviderSettingsStore.shared

    public init() {}

    public var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

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

                                HStack(spacing: 10) {
                                    Text(model.isReadOnly ? "MCP fica read-only" : "MCP pode escrever")
                                        .font(.caption)
                                        .foregroundStyle(Palette.muted)
                                    Spacer()
                                    GlowButton(
                                        title: "Testar modelo",
                                        symbol: "antenna.radiowaves.left.and.right",
                                        spinning: model.isTestingModel
                                    ) {
                                        Task { await model.testModel() }
                                    }
                                    .disabled(model.isTestingModel)
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
                                if let message = model.testMessage {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassCard(cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Conversa", systemImage: "bubble.left.and.bubble.right")
                                    .font(.headline)
                                    .foregroundStyle(Palette.foreground)

                                Toggle(isOn: $model.isAutoScrollEnabled) {
                                    Text("Auto rolagem da conversa")
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.foreground)
                                }
                                .toggleStyle(.switch)

                                Text("Rola pro fim quando chega mensagem nova.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("O provedor precisa expor `/chat/completions` compatível com OpenAI.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: 620)
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 16)
        }
        .foregroundStyle(Palette.foreground)
        .frame(minWidth: 460, minHeight: 440)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        GlassEffectGroup(spacing: 12) {
            HStack(spacing: 12) {
                ToneIcon(symbol: "slider.horizontal.3", tone: .violet)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ajustes")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("provedor local · MCP")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }

                Spacer(minLength: 8)
                StatusPill(
                    text: model.isReadOnly ? "somente-leitura" : "escrita",
                    tone: model.isReadOnly ? .green : .amber)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
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
                .modifier(ProviderFieldGlassModifier())
        }
    }
}

private struct ProviderFieldGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(0.7)
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}
