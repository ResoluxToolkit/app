import Foundation
import Observation
import Resolume

@Observable
@MainActor
public final class ResolumeChatModel {
    public struct Settings {
        public var apiKey: String
        public var baseURL: URL
        public var model: String
        public var policyMode: ToolPolicy.Mode
        /// `nil` = oferecer as 22 ferramentas do Arena. Existe porque o `fm
        /// serve` da Apple estoura a janela com o conjunto inteiro (medido).
        public var toolAllowlist: Set<String>?

        public init(
            apiKey: String = "",
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            model: String = "gpt-5.6",
            policyMode: ToolPolicy.Mode = .readOnly,
            toolAllowlist: Set<String>? = nil
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.model = model
            self.policyMode = policyMode
            self.toolAllowlist = toolAllowlist
        }

        /// Backend local descoberto sozinho -- o caminho normal, sem campo.
        public init(local backend: LocalChatBackend, policyMode: ToolPolicy.Mode = .readOnly) {
            self.apiKey = backend.apiKey
            self.baseURL = backend.baseURL
            self.model = backend.model
            self.policyMode = policyMode
            self.toolAllowlist = backend.toolAllowlist
        }
    }

    public enum Phase: Equatable {
        case idle
        case connecting
        case ready(toolCount: Int)
        case failed(String)
    }

    public struct Line: Identifiable, Equatable {
        public let id = UUID()
        public let role: String
        public let text: String
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lines: [Line] = []
    public var draft: String = ""
    public var isBusy = false
    /// O que foi escolhido na descoberta automática. A UI mostra pra pessoa
    /// saber qual cérebro está respondendo, sem ter que escolher nada.
    public private(set) var backend: LocalChatBackend?

    private let product: ResolumeProduct
    private let readiness: @MainActor () -> Bool
    private let discovery: @MainActor () async -> [LocalChatBackend]
    private var mcpTask: Task<Void, Never>?
    private var client: MCPClient?
    private var transport: ProcessMCPTransport?

    public init(product: ResolumeProduct = .arena) {
        self.product = product
        self.readiness = { product.isResponsive() }
        self.discovery = { await LocalChatBackend.discover() }
    }

    /// Prontidão injetável: permite exercitar a máquina de estados sem depender
    /// do Arena estar aberto na máquina de quem roda os testes.
    package init(
        product: ResolumeProduct,
        readiness: @escaping @MainActor (ResolumeProduct) -> Bool,
        discovery: @escaping @MainActor () async -> [LocalChatBackend] = { [] }
    ) {
        self.product = product
        self.readiness = { readiness(product) }
        self.discovery = discovery
    }

    /// Não basta o socket existir no disco — ele sobrevive ao fechamento do app.
    public var installationReady: Bool { readiness() }
    /// Nome do produto ("Resolume Arena"), para a tela dizer com quem está
    /// falando sem adivinhar.
    public var productName: String { product.appName }
    public var executablePresent: Bool {
        FileManager.default.isExecutableFile(atPath: product.mcpExecutablePath)
    }

    public func connect(settings: Settings) {
        // .failed tem que permitir nova tentativa: foi justamente onde o bug
        // prendia o usuário, sem botão de reconectar.
        guard phase != .connecting else { return }
        guard executablePresent, installationReady else {
            phase = .failed("\(product.appName) precisa estar aberto e respondendo ao REST API")
            return
        }
        begin(with: settings, backend: nil)
    }

    /// Caminho normal do produto: nenhum campo preenchido. Descobre o provedor
    /// local que estiver de pé (Apple FM na 1976, Ollama na 11434) e conecta.
    /// "Abre o Arena, abre nosso aplicativo e a gente dá o nosso jeito."
    public func connect(policyMode: ToolPolicy.Mode = .readOnly) {
        guard phase != .connecting else { return }
        guard executablePresent, installationReady else {
            phase = .failed("\(product.appName) precisa estar aberto e respondendo ao REST API")
            return
        }
        phase = .connecting
        mcpTask = Task { [weak self] in
            let found = await self?.discovery() ?? []
            guard let chosen = found.first else {
                self?.phase = .failed(
                    """
                    Nenhum provedor local respondeu. Abra um dos dois: \
                    Apple Foundation Models (fm serve, porta 1976) ou Ollama (porta 11434).
                    """)
                return
            }
            self?.begin(with: .init(local: chosen, policyMode: policyMode), backend: chosen)
        }
    }

    private func begin(with settings: Settings, backend: LocalChatBackend?) {
        phase = .connecting
        self.backend = backend
        let transport = ProcessMCPTransport(
            executableURL: URL(fileURLWithPath: product.mcpExecutablePath),
            responseTimeout: 15)
        let client = MCPClient(transport: transport)
        self.transport = transport
        self.client = client
        mcpTask = Task { [weak self] in
            do {
                try await client.connect()
                let tools = try await client.listTools()
                self?.engine = ChatEngine(
                    config: .init(baseURL: settings.baseURL, apiKey: settings.apiKey,
                                  model: settings.model,
                                  // Sem isto, o backend Apple recebe as 22 ferramentas e
                                  // derruba HTTP 500 na janela curta -- o subset medido do
                                  // `Settings` ia embora justo no único caso que precisa dele.
                                  toolAllowlist: settings.toolAllowlist),
                    mcp: client,
                    policy: ToolPolicy(mode: settings.policyMode))
                await MainActor.run { self?.phase = .ready(toolCount: tools.count) }
            } catch {
                // O stderr do servidor costuma dizer o que o código de erro não diz.
                let detail = await transport.stderrDiagnostics().trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = detail.isEmpty ? error.localizedDescription : "\(error.localizedDescription) — \(detail)"
                await client.disconnect()
                await MainActor.run {
                    guard let self else { return }
                    self.client = nil
                    self.transport = nil
                    self.phase = .failed(reason)
                }
            }
        }
    }

    public func disconnect() {
        mcpTask?.cancel()
        mcpTask = nil
        // Sem isto o servidor MCP filho sobreviveria ao "Desconectar".
        if let client {
            Task { await client.disconnect() }
        }
        client = nil
        transport = nil
        engine = nil
        phase = .idle
    }

    private(set) var engine: ChatEngine?

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let engine else { return }
        draft = ""
        lines.append(Line(role: "user", text: text))
        isBusy = true
        defer { isBusy = false }
        do {
            let answer = try await engine.send(text)
            lines.append(Line(role: "assistant", text: answer))
        } catch {
            lines.append(Line(role: "system", text: "⚠️ \(error.localizedDescription)"))
        }
    }
}
