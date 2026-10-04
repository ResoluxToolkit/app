import Foundation

/// Backend de chat local descoberto sozinho, sem nenhum campo pra preencher.
///
/// Regra do produto: "abre o Arena, abre nosso app e a gente dá o nosso jeito".
/// Nada de pedir IP, porta ou chave -- os dois provedores que existem nesta
/// máquina já escutam em loopback e se anunciam: `fm serve` da Apple na 1976 e
/// o gateway local do operador na 8317, ambos OpenAI-compatíveis em /v1. Só
/// sondamos 127.0.0.1:
/// nunca varremos a rede, que é o que conflitaria com infra de casa de show.
public struct LocalChatBackend: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case appleFoundationModels
        case localGateway
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let baseURL: URL
    public let model: String

    public init(kind: Kind, baseURL: URL, model: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
    }

    /// Nome curto pra UI ("Apple Foundation · system", "gemini-3.8-flash-high").
    public var displayName: String {
        switch kind {
        case .appleFoundationModels: "Apple Foundation · \(model)"
        case .localGateway: model
        }
    }

    /// Chave fixa por provedor: Apple FM não exige (o campo existe porque o
    /// formato OpenAI-compatível pede) e o gateway usa a chave do operador.
    public var apiKey: String {
        switch kind {
        case .appleFoundationModels: "resolux-local"
        case .localGateway: Self.localGatewayAPIKey
        }
    }

    /// Gateway OpenAI-compatível definido pelo operador, escutando em loopback.
    /// Modelo e chave são dele; nada de catálogo remoto ou nuvem.
    public static let localGatewayBaseURL = URL(string: "http://127.0.0.1:8317/v1")!
    public static let localGatewayModel = "gemini-3.8-flash-high"
    public static let localGatewayAPIKey = "123456"

    /// As 10 ferramentas que cabem na janela do `fm serve`. Lista medida nesta
    /// máquina com o system prompt real e `stream:false`: 3.986 tokens de prompt
    /// e HTTP 200; a 11ª entrada devolve HTTP 500 ("transcript exceeded the
    /// model's context size") mesmo sendo barata -- a janela é do total, não por
    /// ferramenta. Não é ordem de preferência, é o corte da escada.
    public static let appleToolSubset: Set<String> = [
        "diagnose", "status", "transport", "deck", "column", "catalog",
        "composition", "group", "crossfader", "color_code",
    ]

    /// Ferramentas que este backend pode receber. O gateway local leva tudo
    /// (22 ferramentas); o Apple leva o subset acima.
    public var toolAllowlist: Set<String>? {
        switch kind {
        case .appleFoundationModels: Self.appleToolSubset
        case .localGateway: nil
        }
    }

    // MARK: - Descoberta

    /// Ordem de preferencia entre provedores que responderam em loopback.
    ///
    /// Voto do operador (2026-10-03, revoga o de 2026-09-27): o gateway local
    /// (8317, com as 22 ferramentas) entra "de cara" e o Apple FM vira a rede
    /// de seguranca quando o gateway nao responde. Antes era o contrario:
    /// Apple de cara com 10 ferramentas e gateway de rede de seguranca
    /// (DUVIDAS 3).
    ///
    /// Offline e o outro lado desse voto (tem venue sem internet). A regra dele
    /// foi literal: embutir modelo grande aqui "a gente vai foder um software".
    /// Ordem de maquina local, portanto -- nunca download, nunca nuvem.
    public static func preferredOrder(_ found: [LocalChatBackend]) -> [LocalChatBackend] {
        found.sorted { Self.preferenceRank($0) < Self.preferenceRank($1) }
    }

    private static func preferenceRank(_ backend: LocalChatBackend) -> Int {
        switch backend.kind {
        case .appleFoundationModels: 1
        case .localGateway: 0
        }
    }

    struct ModelsResponse: Decodable {
        public struct Entry: Decodable { let id: String }
        var data: [Entry]
    }

    /// Sonda as duas portas conhecidas em loopback e devolve o que respondeu,
    /// na ordem de preferência. Sem porta nossa aberta, sem broadcast, sem
    /// Bonjour por enquanto (sonda local resolve o caso real de hoje).
    public static func discover(timeout: TimeInterval = 1.2) async -> [LocalChatBackend] {
        let appleTask = Task { () async -> LocalChatBackend? in
            await Self.probe(
            kind: .appleFoundationModels,
            url: URL(string: "http://127.0.0.1:1976/v1/models")!,
            modelPick: { ids in ids.contains("system") ? "system" : ids.first },
            timeout: timeout)
        }
        let gatewayTask = Task { () async -> LocalChatBackend? in
            await Self.probe(
            kind: .localGateway,
            url: Self.localGatewayBaseURL.appending(path: "models"),
            modelPick: { _ in Self.localGatewayModel },
            apiKey: Self.localGatewayAPIKey,
            timeout: timeout)
        }
        // As duas sondas rodam em paralelo (não encadeadas): a ordem de chegada
        // não decide nada, decide `preferredOrder` -- que é o voto do operador,
        // não a latência de cada porta. Ver docs/DUVIDAS.md pergunta 3.
        let found = await [appleTask.value, gatewayTask.value]
        return Self.preferredOrder(found.compactMap { $0 })
    }

    static func probe(
        kind: Kind,
        url: URL,
        modelPick: @Sendable ([String]) -> String?,
        apiKey: String? = nil,
        timeout: TimeInterval
    ) async -> LocalChatBackend? {
        var request = URLRequest(url: url, timeout: timeout)
        request.httpMethod = "GET"
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await localSession.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data)
        else { return nil }
        let ids = decoded.data.map(\.id)
        guard let model = modelPick(ids) else { return nil }
        // base URL OpenAI-compatível é o pai de /models
        var base = url.deletingLastPathComponent().absoluteString
        if !base.hasSuffix("/") { base += "/" }
        guard let baseURL = URL(string: base) else { return nil }
        return LocalChatBackend(kind: kind, baseURL: baseURL, model: model)
    }

    /// Sessão dedicada: probe curto nao herda o teto longo do transporte de
    /// chat, e cache nenhum faz sentido em descoberta.
    static let localSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

private extension URLRequest {
    init(url: URL, timeout: TimeInterval) {
        self.init(url: url)
        timeoutInterval = timeout
    }
}
