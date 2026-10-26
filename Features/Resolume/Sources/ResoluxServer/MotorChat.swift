import Foundation
import Pulse
import Resolume

/// Fachada do chat no daemon v1: transforma o backend escolhido na sessão em
/// um `ChatEngine.Config` OpenAI-compatível, mantém um `MCPClient` vivo contra
/// o servidor MCP do Arena e executa um turno por vez.
///
/// O backend "spike" é o novo padrão robusto: lê token e baseUrl do
/// `~/.spike/account.json` — nada no repo, nada na UI, nada digitado à mão.
public actor MotorChat {
    public enum Falha: Error, Equatable {
        case turnoOcupado
        case backendIndisponivel(String)
        case tokenAusente(String)
        case arenaMcpIndisponivel(String)
        case modeloFalhou(String)
    }

    private struct ListaModelos: Decodable {
        struct Entrada: Decodable { let id: String }
        let data: [Entrada]
    }

    private struct ContaSpike: Decodable {
        let baseUrl: String?
        let token: String
    }

    /// Teto do turno em segundos: o front corta em 5 min; sem este teto um
    /// backend travado deixaria o motor ocupado para sempre (`busy` eterno).
    static let tetoTurnoSegundos: UInt64 = 270

    private var mcp: MCPClient?
    private var engine: ChatEngine?
    private var backendAtual: String?
    private var modelAtual: String?
    private var contagemFerramentas = 0
    private var ferramentas: [(nome: String, descricao: String?)] = []
    private var turnoEmAndamento = false

    private let caminhoAccount: String
    private let transporteInjetado: (any ChatBackendTransport)?
    private let configFixa: ChatEngine.Config?
    private let mcpInjetado: MCPClient?
    private let proxySondas: URLSessionProxy = PulseAudit.shared().makeProxy()

    public init(
        caminhoAccount: String = NSHomeDirectory() + "/.spike/account.json",
        transporte: (any ChatBackendTransport)? = nil,
        configFixa: ChatEngine.Config? = nil,
        mcp: MCPClient? = nil) {
        self.caminhoAccount = caminhoAccount
        self.transporteInjetado = transporte
        self.configFixa = configFixa
        self.mcpInjetado = mcp
    }

    // MARK: - Estado para o contrato (toolsAllowed e GET /tools)

    public func totalFerramentas() -> Int { contagemFerramentas }

    public func listaFerramentas() -> [[String: String]] {
        ferramentas.map { item in
            var entrada = ["name": item.nome]
            if let descricao = item.descricao, !descricao.isEmpty {
                entrada["description"] = descricao
            }
            return entrada
        }
    }

    // MARK: - Turno

    public func responder(_ texto: String, sessao: SessaoV1) async throws -> String {
        guard !turnoEmAndamento else { throw Falha.turnoOcupado }
        turnoEmAndamento = true
        defer { turnoEmAndamento = false }

        let motor = try await preparar(sessao: sessao)
        do {
            return try await enviarComTeto(motor, texto)
        } catch {
            // Turno quebrado não tem estado confiável: descarta a conversa e
            // deixa o próximo turno reabrir MCP e backend do zero.
            engine = nil
            await mcp?.disconnect()
            mcp = nil
            contagemFerramentas = 0
            ferramentas = []
            if let falha = error as? Falha { throw falha }
            throw Falha.modeloFalhou(String(describing: error))
        }
    }

    private func preparar(sessao: SessaoV1) async throws -> ChatEngine {
        if mcp == nil {
            if let mcpInjetado {
                mcp = mcpInjetado
            } else {
                try await conectarMCP()
            }
        }
        if contagemFerramentas == 0 { await registrarFerramentas() }

        let backend = sessao.backend
        let model = sessao.model
        if engine == nil || backend != backendAtual || model != modelAtual {
            let config: ChatEngine.Config
            if let configFixa {
                config = configFixa
            } else {
                config = try await resolverConfig(backend: backend, model: model)
            }
            if let transporteInjetado {
                engine = ChatEngine(
                    config: config,
                    transport: transporteInjetado,
                    mcp: mcp!)
            } else {
                engine = ChatEngine(config: config, mcp: mcp!)
            }
            backendAtual = backend
            modelAtual = model
        }
        guard let engine else {
            throw Falha.modeloFalhou("Motor não foi inicializado.")
        }
        return engine
    }

    /// Serializa o turno contra um teto rígido: quem terminar primeiro leva.
    private func enviarComTeto(_ motor: ChatEngine, _ texto: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { grupo in
            grupo.addTask { try await motor.send(texto) }
            grupo.addTask {
                try await Task.sleep(nanoseconds: Self.tetoTurnoSegundos * 1_000_000_000)
                throw Falha.modeloFalhou("Turno passou de \(Self.tetoTurnoSegundos)s.")
            }
            guard let primeiro = try await grupo.next() else {
                throw Falha.modeloFalhou("Turno terminou sem resposta.")
            }
            grupo.cancelAll()
            return primeiro
        }
    }

    // MARK: - MCP do Arena

    private func conectarMCP() async throws {
        let produto = ResolumeProduct.arena
        guard FileManager.default.isExecutableFile(atPath: produto.mcpExecutablePath) else {
            throw Falha.arenaMcpIndisponivel(
                "Servidor MCP do Arena não encontrado: \(produto.mcpExecutablePath)")
        }
        guard produto.isResponsive() else {
            throw Falha.arenaMcpIndisponivel(
                "O \(produto.appName) precisa estar aberto e respondendo ao REST API.")
        }
        let transportador = ProcessMCPTransport(
            executableURL: URL(fileURLWithPath: produto.mcpExecutablePath),
            responseTimeout: 15)
        let client = MCPClient(transport: transportador)
        do {
            try await client.connect()
            await registrarFerramentas()
            mcp = client
        } catch {
            await client.disconnect()
            throw Falha.arenaMcpIndisponivel(
                "MCP do Arena não respondeu ao handshake: \(String(describing: error))")
        }
    }

    /// Anuncia as ferramentas do servidor no estado do daemon (`toolsAllowed`
    /// e `GET /tools`). Sem contar, a UI mostraria zero com o chat rodando.
    private func registrarFerramentas() async {
        guard let mcp, let infos = try? await mcp.listTools() else { return }
        contagemFerramentas = infos.count
        ferramentas = infos.map { ($0.name, $0.description) }
    }

    // MARK: - Resolução de backend

    func resolverConfig(backend: String, model: String) async throws -> ChatEngine.Config {
        switch backend {
        case "spike":
            let conta = try lerAccountSpike()
            let base = (conta.baseUrl ?? "https://spikeai.de").trimmingCharacters(
                in: CharacterSet(charactersIn: "/"))
            return ChatEngine.Config(
                baseURL: URL(string: "\(base)/v1")!,
                apiKey: conta.token,
                model: model.isEmpty ? "Spike" : model,
                toolAllowlist: nil)
        case "ollama":
            let base = "http://127.0.0.1:11434/v1"
            let ids = await sondarModelos(base: base, apiKey: "resolux-local")
            guard !ids.isEmpty else {
                throw Falha.backendIndisponivel("Ollama não respondeu em 127.0.0.1:11434.")
            }
            let escolhido = ids.contains(model) ? model : ids[0]
            return ChatEngine.Config(
                baseURL: URL(string: base)!,
                apiKey: "resolux-local",
                model: escolhido,
                toolAllowlist: nil)
        case "applefm":
            let base = "http://127.0.0.1:1976/v1"
            let ids = await sondarModelos(base: base, apiKey: "resolux-local")
            guard !ids.isEmpty else {
                throw Falha.backendIndisponivel("Apple FM (fm serve) não respondeu em 127.0.0.1:1976.")
            }
            let escolhido = model.isEmpty ? (ids.contains("system") ? "system" : ids[0]) : model
            return ChatEngine.Config(
                baseURL: URL(string: base)!,
                apiKey: "resolux-local",
                model: escolhido,
                toolAllowlist: LocalChatBackend.appleToolSubset)
        default:
            throw Falha.backendIndisponivel("Backend desconhecido: \(backend)")
        }
    }

    private func sondarModelos(base: String, apiKey: String) async -> [String] {
        guard let url = URL(string: "\(base)/models") else { return [] }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 1.2
        pedido.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (dados, resposta) = try? await proxySondas.data(for: pedido),
              let http = resposta as? HTTPURLResponse,
              http.statusCode == 200,
              let lista = try? JSONDecoder().decode(ListaModelos.self, from: dados)
        else { return [] }
        return lista.data.map(\.id)
    }

    private func lerAccountSpike() throws -> ContaSpike {
        guard let dados = FileManager.default.contents(atPath: caminhoAccount),
              let conta = try? JSONDecoder().decode(ContaSpike.self, from: dados),
              !conta.token.isEmpty
        else {
            throw Falha.tokenAusente("Token do Spike ausente em \(caminhoAccount).")
        }
        return conta
    }
}
