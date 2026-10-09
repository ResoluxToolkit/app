import FoundationModels
import AppKit
import ResoluxDesignSystem
import Resolume
import ThinkingOrbsKit
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
        public let createdAt = Date()

        public init(role: String, text: String) {
            self.role = role
            self.text = text
        }

        public var tokenEstimate: Int {
            max(1, (text.count + 3) / 4)
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
                lines.append(Line(role: "system", text: "Erro: \(error.localizedDescription)"))
            }
        }
    }

    public func startNewConversation() {
        lines.removeAll()
        draft = ""
        isFMFallbackActive = false

        let systemModel = SystemLanguageModel.default
        guard case .available = systemModel.availability else { return }

        if let mcpClient, !fmToolInfos.isEmpty {
            let tools = MCPFoundationModelToolFactory.makeTools(
                from: fmToolInfos,
                client: mcpClient,
                policy: ProviderSettingsStore.shared.toolPolicy,
                journal: writeJournal)
            fmSession = LanguageModelSession(model: systemModel, tools: tools)
            fmPolicyMode = ProviderSettingsStore.shared.toolPolicy.mode
        } else {
            fmSession = LanguageModelSession(
                model: systemModel,
                instructions: """
                Você é o Assistente Resolux. Responda em português do Brasil, \
                direto ao ponto e sem inventar estado do Arena.
                """)
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
    @State private var isMemoryReviewActive = false
    @FocusState private var isMessageFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            AssistantBackdrop()

            VStack(spacing: 0) {
                header

                HStack(alignment: .top, spacing: 16) {
                    sidebar
                        .frame(width: 260)
                        .frame(maxHeight: .infinity, alignment: .top)

                    Spacer(minLength: 0)

                    VStack(spacing: 16) {
                        transcript
                        contextBar
                        inputBar
                    }
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)

                    Spacer(minLength: 0)

                    contextPanel
                        .frame(width: 320)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(minWidth: 1080, minHeight: 700)
        .preferredColorScheme(.dark)
        .onAppear {
            Task { model.connectMCP() }
            Task { @MainActor in
                isMessageFocused = true
            }
        }
    }

    private var header: some View {
        GlassEffectGroup(spacing: 12) {
            HStack(spacing: 12) {
                ToneIcon(symbol: "sparkles", tone: .violet, size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistente")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 8)
                StatusPill(text: status, tone: statusTone)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .modifier(AssistantGlassModifier(cornerRadius: 20))
        }
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
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.lines.isEmpty {
                    GeometryReader { proxy in
                        emptyState
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                ForEach(model.lines) { line in
                    bubble(for: line)
                        .id(line.id)
                }
                if model.isBusy {
                    HStack(alignment: .center, spacing: 10) {
                        ThinkingOrb(
                            state: model.isFMFallbackActive ? .composing : .working,
                            size: .px20,
                            displaySize: 20)
                        Text("Analisando o monitor do Arena…")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 0)
                        assistantChip("working", systemImage: "cpu", tint: Palette.accentViolet)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .modifier(AssistantGlassModifier(cornerRadius: 14))
                } else if !model.lines.isEmpty {
                    HStack(spacing: 12) {
                        suggestionChip("Verificar câmera", symbol: "camera.viewfinder")
                        suggestionChip("Status do monitor", symbol: "display")
                        suggestionChip("Ver atualizações", symbol: "arrow.triangle.2.circlepath")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(
            UnitPoint(x: 0.5, y: model.lines.isEmpty ? 0.5 : 1.0))
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
        .modifier(AssistantGlassModifier(cornerRadius: 20))
    }

    private func scrollToEndIfEnabled() {
        guard settings.isAutoScrollEnabled, let last = model.lines.last else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            scrolledToLineID = last.id
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ThinkingOrb(state: .breathing, size: .px64)

            VStack(spacing: 6) {
                Text("Nova conversa")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(model.unavailableMessage ?? "Fale, pergunte e peça leitura do Arena. O gateway local tem MCP completo e o Apple FM entra como fallback.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                suggestionChip("Verificar câmera", symbol: "camera.viewfinder")
                suggestionChip("Status do monitor", symbol: "display")
                suggestionChip("Ver atualizações", symbol: "arrow.triangle.2.circlepath")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(for line: AssistantModel.Line) -> some View {
        HStack(alignment: .bottom) {
            if line.role == "user" { Spacer(minLength: 56) }

            message(for: line)
                .frame(maxWidth: .infinity, alignment: line.role == "user" ? .trailing : .leading)

            if line.role != "user" { Spacer(minLength: 56) }
        }
    }

    @ViewBuilder
    private func message(for line: AssistantModel.Line) -> some View {
        if line.role == "user" {
            VStack(alignment: .trailing, spacing: 5) {
                Text(NSUserName().isEmpty ? "VOCÊ" : NSUserName().uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.brand)

                Text(line.text)
                    .textSelection(.enabled)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 620, alignment: .leading)
                    .modifier(AssistantBubbleModifier(role: line.role))

                Text(line.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
        } else if line.role == "assistant" {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ThinkingOrb(
                        state: .breathing,
                        size: .px20,
                        displaySize: 20)

                    Text("RESOLUX")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.textSecondary)

                    Spacer(minLength: 12)

                    assistantChip("Pro", systemImage: "checkmark.seal", tint: Palette.accentViolet)
                }

                bubbleContent(for: line)
                    .foregroundStyle(Palette.textPrimary)

                Rectangle()
                    .fill(Palette.assistantBorder)
                    .frame(height: 1)

                HStack(spacing: 12) {
                    Text(
                        "\(line.createdAt.formatted(date: .omitted, time: .shortened)) · ≈ \(line.tokenEstimate) tokens"
                    )
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)

                    Spacer(minLength: 12)

                    messageActionButton(
                        symbol: "doc.on.doc",
                        accessibilityLabel: "Copiar resposta") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(line.text, forType: .string)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AssistantGlassModifier(cornerRadius: 20))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.alert)
                Text(line.text)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .modifier(AssistantGlassModifier(cornerRadius: 14))
        }
    }

    private func messageActionButton(
        symbol: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.05), in: Circle())
                .overlay(Circle().strokeBorder(Palette.assistantBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)

            TextField("Pergunte ao Resolux ou peça uma ação…", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isMessageFocused)
                .foregroundStyle(Palette.textPrimary)
                .onSubmit {
                    Task { await model.sendDraft() }
                }

            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        model.canSend
                            ? AnyShapeStyle(Palette.assistantBackground)
                            : AnyShapeStyle(Palette.textTertiary))
                    .frame(width: 32, height: 32)
                    .background(
                        model.canSend
                            ? Palette.brand
                            : Palette.textTertiary.opacity(0.18),
                        in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 56)
        .modifier(AssistantGlassModifier(cornerRadius: 28))
        .overlay {
            Capsule()
                .strokeBorder(isMessageFocused ? Palette.brand : Palette.assistantBorder, lineWidth: 1)

            if model.isBusy {
                BeamStroke(cornerRadius: 28, lineWidth: 2, active: true, duration: 3.2)
                    .clipShape(Capsule())
            }
        }
        .padding(.bottom, 24)
    }

    private var contextBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.brand)

            Text("Contexto")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            ProgressView(value: 0.09)
                .tint(Palette.brand)

            Text("9%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.brand)

            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(AssistantGlassModifier(cornerRadius: 20))
    }

    private var composerOrbState: OrbState {
        if model.isBusy {
            return model.isFMFallbackActive ? .composing : .working
        }
        if case .connecting = model.mcpPhase {
            return .searching
        }
        return .breathing
    }

    private var sessionTitle: String {
        guard let firstUser = model.lines.first(where: { $0.role == "user" }) else {
            return "Nova conversa"
        }

        let title = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.count > 36 ? "\(title.prefix(36))…" : title
    }

    private var sessionDetail: String {
        guard let firstLine = model.lines.first else { return "Resolux" }
        return "Assistente · \(firstLine.createdAt.formatted(date: .omitted, time: .shortened))"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                model.startNewConversation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Nova conversa")
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.brand.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Text("HOJE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Resolux")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.assistantBorder, lineWidth: 1))
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Label("Capabilities", systemImage: "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                HStack(spacing: 8) {
                    assistantChip("Captura", systemImage: "camera.viewfinder", tint: Palette.info)
                    assistantChip("Compartilhar", systemImage: "square.and.arrow.up", tint: Palette.info)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.assistantBorder, lineWidth: 1))
        }
        .padding(12)
        .modifier(AssistantGlassModifier(cornerRadius: 20))
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "circle.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                Text("Contexto ativo")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Text("9% · 18 mil tokens")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Janela de contexto")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("9% usado")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.brand)
                }

                ProgressView(value: 0.09)
                    .tint(Palette.brand)
            }

            Rectangle()
                .fill(Palette.assistantBorder)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Label("Fontes", systemImage: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    sourceRow("Câmera", symbol: "video.fill", active: true)
                    sourceRow("Monitor", symbol: "display", active: true)
                    sourceRow("Quick Play", symbol: "play.rectangle.on.rectangle", active: false)
                    sourceRow("Starter", symbol: "wrench.and.screwdriver", active: false)
                }
            }

            Rectangle()
                .fill(Palette.assistantBorder)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Label("Memória", systemImage: "brain")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                memoryRow("Prefere respostas em português", symbol: "text.bubble")
                memoryRow("Projeto ativo: Resolux macOS + iOS", symbol: "shippingbox")

                Button {
                    isMemoryReviewActive.toggle()
                } label: {
                    Label(
                        isMemoryReviewActive ? "Fechar revisão" : "Revisar memória",
                        systemImage: "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.brand)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .background(
                            Palette.brand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.brand.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if isMemoryReviewActive {
                    Text("As notas são locais nesta sessão.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AssistantGlassModifier(cornerRadius: 20))
    }

    private func suggestionChip(_ title: String, symbol: String) -> some View {
        Button {
            model.draft = title
            isMessageFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.assistantBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func assistantChip(
        _ title: String,
        systemImage: String,
        tint: Color = Palette.textSecondary
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.assistantBorder, lineWidth: 1))
        .fixedSize()
    }

    private func sourceRow(
        _ title: String,
        symbol: String,
        active: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Palette.textSecondary : Palette.textTertiary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)

            Spacer(minLength: 8)

            Circle()
                .fill(active ? Palette.success : Palette.textTertiary.opacity(0.5))
                .frame(width: 6, height: 6)

            Text(active ? "Ativa" : "Inativa")
                .font(.caption2.weight(.medium))
                .foregroundStyle(active ? Palette.success : Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.assistantBorder, lineWidth: 1))
    }

    private func memoryRow(_ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.brand)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

private struct AssistantBubbleModifier: ViewModifier {
    let role: String

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if role == "user" {
            content
                .background(Palette.brand.opacity(0.15), in: shape)
                .overlay(shape.strokeBorder(Palette.brand.opacity(0.35), lineWidth: 1))
        } else {
            content.modifier(AssistantGlassModifier(cornerRadius: 18))
        }
    }
}

private struct AssistantGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(Palette.assistantBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Palette.assistantBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
        }
    }
}

private struct AssistantBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height)

            ZStack {
                Palette.assistantBackground

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.brand.opacity(0.07), .clear],
                            center: UnitPoint(x: 0.18, y: 0.12),
                            startRadius: 0,
                            endRadius: radius * 0.85))
                    .frame(width: radius * 1.7, height: radius * 1.7)
                    .blur(radius: 64)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.accentViolet.opacity(0.07), .clear],
                            center: UnitPoint(x: 0.86, y: 0.22),
                            startRadius: 0,
                            endRadius: radius * 0.75))
                    .frame(width: radius * 1.5, height: radius * 1.5)
                    .blur(radius: 72)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.info.opacity(0.05), .clear],
                            center: UnitPoint(x: 0.38, y: 0.92),
                            startRadius: 0,
                            endRadius: radius * 0.8))
                    .frame(width: radius * 1.6, height: radius * 1.6)
                    .blur(radius: 80)
            }
        }
        .ignoresSafeArea()
    }
}
