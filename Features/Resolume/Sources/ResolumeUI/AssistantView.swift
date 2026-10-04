import FoundationModels
import BorderBeamKit
import ResoluxDesignSystem
import Resolume
import SwiftUI

/// Conversa com o gateway local (MCP completo) e Foundation Models como fallback.
@available(macOS 26.0, *)
@Observable
@MainActor
public final class AssistantModel {
    public enum MCPPhase: Equatable {
        case idle
        case connecting
        case ready(toolCount: Int)
        case failed(String)
    }

    public struct Line: Identifiable, Equatable {
        public let id = UUID()
        public let role: String
        public let text: String

        public init(role: String, text: String) {
            self.role = role
            self.text = text
        }
    }

    public private(set) var lines: [Line] = []
    public var draft = ""
    public private(set) var isBusy = false
    public private(set) var unavailableMessage: String?
    public private(set) var mcpPhase: MCPPhase = .idle
    public private(set) var activeGateway: LocalChatBackend?
    public private(set) var isFMFallbackActive = false
    public private(set) var fmToolCount = 0
    public var canSend: Bool {
        (fmSession != nil || isMCPReady) && !isBusy && !draft.isEmpty
    }
    private var fmSession: LanguageModelSession?
    private var gatewayEngine: ChatEngine?
    private var gatewayPolicyMode: ToolPolicy.Mode?
    private var mcpTask: Task<Void, Never>?
    private var mcpClient: MCPClient?
    private var mcpTransport: ProcessMCPTransport?
    private var fmToolInfos: [MCPToolInfo] = []
    private var fmPolicyMode: ToolPolicy.Mode?
    // Um diário por sessão do Assistente: gateway configurado, gateway local e
    // fallback FM escrevem no mesmo arquivo. Toda escrita permitida tem rastro.
    private let writeJournal = WriteJournal()

    private var isMCPReady: Bool {
        if case .ready = mcpPhase { true } else { false }
    }

    private enum AssistantError: LocalizedError {
        case gatewayUnavailable
        case fmUnavailable
        var errorDescription: String? {
            switch self {
            case .gatewayUnavailable: "Gateway local não respondeu na porta 8317."
            case .fmUnavailable: "Foundation Models não está disponível neste momento."
            }
        }
    }

    public init() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            fmSession = LanguageModelSession(
                model: model,
                instructions: """
                Você é o Assistente Resolux. Responda em português do Brasil, \
                direto ao ponto e sem inventar estado do Arena.
                """)
        case .unavailable(let reason):
            unavailableMessage = Self.message(for: reason)
        }
    }

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        lines.append(Line(role: "user", text: text))
        isBusy = true
        defer { isBusy = false }

        do {
            let answer: String
            if isMCPReady {
                answer = try await sendViaGateway(text)
            } else {
                answer = try await sendViaFM(text)
            }
            lines.append(Line(role: "assistant", text: answer.isEmpty ? "sem resposta" : answer))
        } catch {
            gatewayEngine = nil
            do {
                let answer = try await sendViaFM(text)
                lines.append(Line(role: "assistant", text: answer.isEmpty ? "sem resposta" : answer))
            } catch {
                lines.append(Line(role: "system", text: "⚠️ \(error.localizedDescription)"))
            }
        }
    }

    public func connectMCP(product: ResolumeProduct = .arena) {
        guard case .idle = mcpPhase else { return }
        guard FileManager.default.isExecutableFile(atPath: product.mcpExecutablePath),
              product.isResponsive() else {
            mcpPhase = .failed("\(product.appName) precisa estar aberto e respondendo ao REST API")
            return
        }

        mcpPhase = .connecting
        let transport = ProcessMCPTransport(
            executableURL: URL(fileURLWithPath: product.mcpExecutablePath),
            responseTimeout: 15)
        let client = MCPClient(transport: transport)
        mcpTransport = transport
        mcpClient = client
        mcpTask = Task { [weak self] in
            do {
                try await client.connect()
                let infos = try await client.listTools()
                // O gateway local leva tudo; o Apple FM (fallback) leva o
                // subset medido: a janela dele não aceita 22.
                let filtered = infos.filter {
                    LocalChatBackend.appleToolSubset.contains($0.name)
                }
                let fmTools = MCPFoundationModelToolFactory.makeTools(
                    from: filtered,
                    client: client,
                    policy: await MainActor.run { ProviderSettingsStore.shared.toolPolicy },
                    journal: await MainActor.run { self?.writeJournal })
                await MainActor.run {
                    self?.install(
                        fmTools: fmTools,
                        client: client,
                        toolCount: infos.count,
                        fmToolCount: filtered.count,
                        toolInfos: filtered)
                }
            } catch {
                let diagnostics = await transport.stderrDiagnostics()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = diagnostics.isEmpty
                    ? error.localizedDescription
                    : "\(error.localizedDescription) — \(diagnostics)"
                await client.disconnect()
                await MainActor.run {
                    guard let self else { return }
                    self.mcpClient = nil
                    self.mcpTransport = nil
                    self.mcpPhase = .failed(reason)
                }
            }
        }
    }

    private func install(
        fmTools: [any Tool],
        client: MCPClient,
        toolCount: Int,
        fmToolCount: Int,
        toolInfos: [MCPToolInfo]
    ) {
        if let oldSession = fmSession {
            fmSession = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: fmTools,
                transcript: oldSession.transcript)
        }
        mcpClient = client
        mcpPhase = .ready(toolCount: toolCount)
        self.fmToolCount = fmToolCount
        fmToolInfos = toolInfos
    }

    private func sendViaFM(_ text: String) async throws -> String {
        guard let oldSession = fmSession else {
            throw AssistantError.fmUnavailable
        }
        let policy = ProviderSettingsStore.shared.toolPolicy
        if fmPolicyMode == policy.mode, let session = fmSession {
            let response = try await session.respond(to: text)
            isFMFallbackActive = true
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let client = mcpClient else {
            let response = try await oldSession.respond(to: text)
            isFMFallbackActive = true
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tools = MCPFoundationModelToolFactory.makeTools(
            from: fmToolInfos,
            client: client,
            policy: policy,
            journal: writeJournal)
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            transcript: oldSession.transcript)
        fmSession = session
        fmPolicyMode = policy.mode
        fmToolCount = fmToolInfos.count
        let response = try await session.respond(to: text)
        isFMFallbackActive = true
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendViaGateway(_ text: String) async throws -> String {
        guard let client = mcpClient else {
            throw AssistantError.gatewayUnavailable
        }
        let configured = ProviderSettingsStore.shared.persistedSettings
        let policy = ProviderSettingsStore.shared.toolPolicy
        if configured.isConfigured {
            guard let engine = configuredEngine(
                settings: configured,
                client: client,
                policy: policy) else {
                throw AssistantError.gatewayUnavailable
            }
            gatewayEngine = engine
            gatewayPolicyMode = policy.mode
            let answer = try await engine.send(text)
            activeGateway = nil
            return answer
        }

        if let engine = gatewayEngine, gatewayPolicyMode == policy.mode {
            return try await engine.send(text)
        }

        let found = await LocalChatBackend.discover()
        guard let backend = found.first(where: { $0.kind == .localGateway }) else {
            throw AssistantError.gatewayUnavailable
        }
        let engine = ChatEngine(
            config: .init(
                baseURL: backend.baseURL,
                apiKey: backend.apiKey,
                model: backend.model,
                toolAllowlist: backend.toolAllowlist),
            mcp: client,
            policy: policy,
            journal: writeJournal)
        gatewayEngine = engine
        gatewayPolicyMode = policy.mode
        let answer = try await engine.send(text)
        activeGateway = backend
        return answer
    }

    private func configuredEngine(
        settings: ProviderSettings,
        client: MCPClient,
        policy: ToolPolicy
    ) -> ChatEngine? {
        guard let endpoint = settings.chatEndpointURL else { return nil }
        return ChatEngine(
            config: .init(
                endpoint: endpoint,
                apiKey: settings.token,
                model: settings.modelID),
            mcp: client,
            policy: policy,
            journal: writeJournal)
    }

    private static func message(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            "Este equipamento não tem Foundation Models."
        case .appleIntelligenceNotEnabled:
            "Ative o Apple Intelligence para usar o Assistente."
        case .modelNotReady:
            "O modelo do sistema ainda não está pronto."
        @unknown default:
            "Foundation Models não está disponível neste momento."
        }
    }
}

@available(macOS 26.0, *)
public struct AssistantView: View {
    @State private var model = AssistantModel()
    @State private var settings = ProviderSettingsStore.shared
    @State private var scrolledToLineID: AssistantModel.Line.ID?
    @FocusState private var isMessageFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                transcript
                inputBar
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
        }
        .foregroundStyle(Palette.foreground)
        .frame(minWidth: 460, minHeight: 440)
        .preferredColorScheme(.dark)
        .onAppear {
            Task { model.connectMCP() }
            Task { @MainActor in
                isMessageFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ToneIcon(symbol: "sparkles", tone: .violet, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Assistente")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            Spacer(minLength: 8)
            StatusPill(text: status, tone: statusTone)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
    }

    private var status: String {
        if model.activeGateway != nil || model.isFMFallbackActive { return "pronto" }
        if model.unavailableMessage != nil { return "sem fallback" }
        if case .connecting = model.mcpPhase { return "conectando" }
        return model.isBusy ? "pensando" : "pronto"
    }

    private var statusTone: Tone {
        if (model.activeGateway != nil || model.isFMFallbackActive) && !model.isBusy { return .green }
        if model.unavailableMessage != nil { return .coral }
        if case .connecting = model.mcpPhase { return .amber }
        return model.isBusy ? .amber : .green
    }

    private var statusDetail: String {
        if let gateway = model.activeGateway {
            return "Gateway local · \(gateway.model) · MCP completo"
        }
        if model.isFMFallbackActive {
            return "Apple FM fallback · \(model.fmToolCount) ferramentas"
        }
        if model.unavailableMessage != nil, case .ready = model.mcpPhase {
            return "Gateway local será ativado no próximo envio"
        }
        if let unavailableMessage = model.unavailableMessage { return unavailableMessage }
        switch model.mcpPhase {
        case .idle:
            return "Gateway local · MCP não conectado"
        case .connecting:
            return "Gateway local · conectando MCP"
        case .ready(let count):
            return "Gateway local · MCP com \(count) ferramentas"
        case .failed:
            return "MCP indisponível · Apple FM em conversa direta"
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if model.lines.isEmpty {
                    initialCard
                }
                ForEach(model.lines) { line in
                    bubble(for: line)
                        .id(line.id)
                }
                if model.isBusy {
                    HStack(spacing: 10) {
                        ThinkingOrb()
                        Text("pensando…")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
        .scrollPosition(id: $scrolledToLineID, anchor: .bottom)
        .onChange(of: model.lines.count) {
            scrollToEndIfEnabled()
        }
        .onChange(of: model.isBusy) {
            if model.isBusy {
                scrollToEndIfEnabled()
            }
        }
        .task {
            scrollToEndIfEnabled()
        }
    }

    private func scrollToEndIfEnabled() {
        guard settings.isAutoScrollEnabled, let last = model.lines.last else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            scrolledToLineID = last.id
        }
    }

    private var initialCard: some View {
        GlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Conversa direta com o modelo do sistema", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(model.unavailableMessage ?? "Fale, pergunte e peça leitura do Arena. O Assistente usa o gateway local (porta 8317) com MCP completo e o Apple FM como fallback.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bubble(for line: AssistantModel.Line) -> some View {
        HStack {
            if line.role == "user" { Spacer(minLength: 56) }
            bubbleContent(for: line)
                .textSelection(.enabled)
                .font(.system(size: 14))
                .foregroundStyle(Palette.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleFill(for: line), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1))
            if line.role != "user" { Spacer(minLength: 56) }
        }
    }

    private struct MarkdownItem: Identifiable {
        let id: Int
        let isBullet: Bool
        let content: AttributedString
    }

    private struct MarkdownBlock: Identifiable {
        let id: Int
        let items: [MarkdownItem]
    }

    /// Markdown leve pra conversa: bold/italic/code inline pelo AttributedString,
    /// listas viram bullets e linhas em branco separam parágrafos. Sem parser
    /// externo: o bot manda texto simples, a gente renderiza o que der.
    private func markdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var items: [MarkdownItem] = []

        func attributed(_ raw: String) -> AttributedString {
            (try? AttributedString(
                markdown: raw,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(raw)
        }

        for (offset, raw) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !items.isEmpty {
                    blocks.append(MarkdownBlock(id: blocks.count, items: items))
                    items = []
                }
                continue
            }
            let isBullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
            let body = isBullet ? String(trimmed.dropFirst(2)) : trimmed
            items.append(
                MarkdownItem(id: offset, isBullet: isBullet, content: attributed(body)))
        }
        if !items.isEmpty {
            blocks.append(MarkdownBlock(id: blocks.count, items: items))
        }
        return blocks
    }

    @ViewBuilder
    private func bubbleContent(for line: AssistantModel.Line) -> some View {
        if line.role == "user" {
            Text(line.text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(markdownBlocks(line.text)) { block in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(block.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if item.isBullet {
                                    Text("•")
                                        .foregroundStyle(Palette.muted)
                                }
                                Text(item.content)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func bubbleFill(for line: AssistantModel.Line) -> AnyShapeStyle {
        if line.role == "user" {
            return AnyShapeStyle(Palette.deepViolet.opacity(0.45))
        }
        if line.role == "system" {
            return AnyShapeStyle(Palette.coral.opacity(0.18))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Falar com o Assistente…", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isMessageFocused)
                .foregroundStyle(Palette.foreground)
                .onSubmit {
                    Task { await model.sendDraft() }
                }

            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(model.canSend ? AnyShapeStyle(Palette.primaryGradient) : AnyShapeStyle(Palette.muted))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.72)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .borderBeam(
            .md,
            colorVariant: .colorful,
            theme: .dark,
            active: true,
            borderRadius: 24
        )
        .padding(.vertical, 12)
    }
}
