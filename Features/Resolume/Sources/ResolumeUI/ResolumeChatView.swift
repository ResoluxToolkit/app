import Resolume
import SwiftUI

public struct ResolumeChatView: View {
    private enum Field: Hashable { case key, url, model }

    @State private var model = ResolumeChatModel()
    @State private var apiKey = ""
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var chatModel = "gpt-5.6"

    public init(product: ResolumeProduct = .arena) {
        _model = State(initialValue: ResolumeChatModel(product: product))
    }

    public var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcript
            Divider()
            inputBar
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .idle: Label("Desconectado", systemImage: "circle")
            case .connecting: Label("Conectando…", systemImage: "arrow.triangle.2.circle")
            case .ready(let tools): Label("\(tools) ferramentas MCP", systemImage: "checkmark.circle.fill")
            case .failed(let reason): Label(reason, systemImage: "xmark.octagon.fill")
            }
            Spacer()
            if model.engine != nil {
                Button("Desconectar") { model.disconnect() }
            } else if model.phase != .connecting {
                Button("Conectar") {
                    let settings = ResolumeChatModel.Settings(
                        apiKey: apiKey,
                        baseURL: URL(string: baseURL) ?? URL(string: "https://api.openai.com/v1")!,
                        model: chatModel)
                    model.connect(settings: settings)
                }
                .disabled(model.phase == .idle && (!model.executablePresent || !model.installationReady))
            }
        }
        .padding(8)
        .textFieldStyle(.roundedBorder)
    }

    private var settingsFields: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("API key").gridColumnAlignment(.trailing)
                SecureField("", text: $apiKey, prompt: Text("sk-…"))
                    .accessibilityLabel("API key")
            }
            GridRow {
                Text("Base URL")
                TextField("", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                    .accessibilityLabel("Base URL")
            }
            GridRow {
                Text("Modelo")
                TextField("", text: $chatModel, prompt: Text("gpt-5.6"))
                    .accessibilityLabel("Modelo")
            }
        }
        .padding(8)
    }

    @ViewBuilder private var transcript: some View {
        ScrollViewReader { _ in
            LazyVStack(alignment: .leading, spacing: 8) {
                settingsSection
                ForEach(model.lines) { line in
                    bubble(for: line)
                }
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder private var settingsSection: some View {
        if model.engine == nil {
            GroupBox { settingsFields }
        }
    }

    private func bubble(for line: ResolumeChatModel.Line) -> some View {
        HStack {
            if line.role == "user" { Spacer(minLength: 60) }
            Text(line.text)
                .textSelection(.enabled)
                .padding(8)
                .background(line.role == "user" ? AnyShapeStyle(.blue.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.3)), in: RoundedRectangle(cornerRadius: 8))
            if line.role != "user" { Spacer(minLength: 60) }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Fala com o Arena…", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .onSubmit { Task { await model.sendDraft() } }
                .disabled(model.engine == nil || model.isBusy)
            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(model.engine == nil || model.isBusy || model.draft.isEmpty)
        }
        .padding(8)
    }
}
