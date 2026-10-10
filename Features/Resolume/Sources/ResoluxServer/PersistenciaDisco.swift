import Foundation

/// Disco do daemon: `~/.resolux` guarda a sessão e a conversa. O front
/// nunca toca no sistema de arquivos — lê e escreve pela API v1. Hoje é
/// tudo em disco local; sincronizar na nuvem depois é trocar esta pasta
/// de bandeja, sem mudar o contrato.
public actor PersistenciaDisco {
    public struct Turno: Codable, Equatable, Sendable {
        public var id: Int?
        public var papel: String
        public var texto: String
        public var hora: String

        public init(papel: String, texto: String, hora: String, id: Int? = nil) {
            self.id = id
            self.papel = papel
            self.texto = texto
            self.hora = hora
        }
    }

    private let raiz: URL
    private var turnos: [Turno] = []
    private var publicador: (@Sendable (Data) async -> Void)?

    public init(raiz: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.resolux")) {
        self.raiz = raiz
    }

    private var caminhoSessao: URL { raiz.appendingPathComponent("sessao.json") }
    private var caminhoConversa: URL {
        raiz.appendingPathComponent("conversas", isDirectory: true)
            .appendingPathComponent("conversa.json")
    }

    /// Cria a pasta e carrega o que está no disco. Disco ausente ou
    /// corrompido não derruba o daemon: volta ao padrão sem fingir.
    public func preparar() throws -> SessaoV1? {
        try FileManager.default.createDirectory(
            at: caminhoConversa.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        turnos = Self.lerTurnos(caminhoConversa) ?? []
        return Self.lerSessao(caminhoSessao)
    }

    public func salvarSessao(_ sessao: SessaoV1) {
        Self.gravar(Self.codificar(sessao), em: caminhoSessao)
    }

    /// Quem assina o push de conversa (o WS). O publicador recebe a lista
    /// completa a cada mudança — os clientes reconciliam pelo `id` do turno.
    public func definirPublicador(_ publicador: (@Sendable (Data) async -> Void)?) {
        self.publicador = publicador
    }

    public func registrarEntrada(papel: String, texto: String) async {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let turno = Turno(
            papel: papel,
            texto: texto,
            hora: Self.horaAgora(),
            id: (turnos.last?.id ?? turnos.count) + 1)
        turnos.append(turno)
        let corpo = Self.codificar(["turnos": turnos])
        Self.gravar(corpo, em: caminhoConversa)
        await publicador?(corpo)
    }

    public func conversaJson() -> Data {
        Self.codificar(["turnos": turnos])
    }

    public func limparConversa() async {
        turnos = []
        let corpo = Self.codificar(["turnos": [Turno]()])
        Self.gravar(corpo, em: caminhoConversa)
        await publicador?(corpo)
    }

    // MARK: - Helpers puros (estáticos: testáveis sem actor)

    static func codificar(_ valor: some Encodable) -> Data {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? codificador.encode(valor)) ?? Data("{}".utf8)
    }

    static func gravar(_ dados: Data, em url: URL) {
        try? dados.write(to: url, options: .atomic)
    }

    static func lerSessao(_ url: URL) -> SessaoV1? {
        guard let dados = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessaoV1.self, from: dados)
    }

    static func lerTurnos(_ url: URL) -> [Turno]? {
        guard let dados = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(
            [String: [Turno]].self, from: dados) else { return nil }
        return envelope["turnos"]
    }

    static func horaAgora() -> String {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: Date())
    }
}
