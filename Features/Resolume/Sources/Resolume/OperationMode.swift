import Foundation

/// A chave do sistema. Dois modos, dois serviços que não se misturam:
///
/// - **Timeline** calcula. Pré-produção: soma durações, diz quanto tempo deu a
///   linha de clipes, aponta gargalo de codec. Aqui a gente lê o set e faz conta.
/// - **Performance** mede. O set está no ar: nada de calcular, nada de abrir
///   arquivo em disco. Roda telemetria (CPU/RAM/GPU) e avisa antes de estourar.
///
/// A referência que ele deu é o Ableton Live (Session vs Arrangement): não é
/// gosto, é a mesma promessa funcional — um modo prepara, o outro executa, e o
/// modo que executa não faz trabalho de escritório no meio do show.
///
/// Não confundir com `ToolPolicy.Mode`. Leitura/escrita é um eixo (o que pode
/// tocar no set); modo de operação é outro (que serviço oferecemos). Performance
/// pode estar em readWrite tranquilamente — ele passa a ser monitorado, não
/// deixa de operar.
public enum OperationMode: String, Sendable, Codable, CaseIterable, Comparable {
    case timeline
    case performance

    /// Rótulo curto para UI. Quem escolhe é o operador, então sem jargão.
    public var label: String {
        switch self {
        case .timeline: "Timeline (calcula)"
        case .performance: "Performance (mede)"
        }
    }

    public var summary: String {
        switch self {
        case .timeline:
            return "Pré-produção: soma durações e mostra quanto tempo deu a linha."
        case .performance:
            return "Ao vivo: não calcula nada, só mede CPU/RAM/GPU e avisa se for estourar."
        }
    }

    /// Ordem lexic por rawValue. Só existe para o `CaseIterable` ser
    /// determinístico em UI; não é hierarquia de valor.
    public static func < (lhs: OperationMode, rhs: OperationMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Serviços que a chave liga e desliga. Separado do `OperationMode` porque isto
/// é política, e política muda sem precisar mudar o nome do modo.
public enum ModeService: String, Sendable, Codable, CaseIterable {
    /// Contas de pré-produção (duração de linha, total de bloco).
    case calculation
    /// Telemetria de carga da máquina.
    case monitoring
}

/// Política da chave. Uma fonte de verdade só, para UI, motor e testes lerem o
/// mesmo veredito.
public struct ModeGate: Sendable, Equatable {
    public var mode: OperationMode
    /// Serviços habilitados. Nomeamos em vez de espalhar `if`: a regra vai
    /// crescer (bloco crítico, posse) e precisa de um lugar onde morar.
    public var enabled: Set<ModeService>

    public init(mode: OperationMode) {
        self.mode = mode
        self.enabled = Self.defaults(for: mode)
    }

    /// Default da casa. Palavra dele: "Timeline: Calcula. Performance: Mede."
    /// Monitorar em Timeline está ligado porque "essa linha cabe na máquina?" é
    /// pergunta de pré-produção também; o que não pode é o contrário — calcular
    /// durante o show. `instavel:` -- e escolha NOSSA, nao do Arena: uma palavra dele
    /// muda isto aqui e mais nada (legenda das tags: HANDOFF §6).
    static func defaults(for mode: OperationMode) -> Set<ModeService> {
        switch mode {
        case .timeline: [.calculation, .monitoring]
        case .performance: [.monitoring]
        }
    }

    public func allows(_ service: ModeService) -> Bool {
        enabled.contains(service)
    }

    /// Recusa acionável, no mesmo espírito da recusa do `ToolPolicy`: sem dizer
    /// o que continua disponível, o modelo insiste na mesma chamada.
    public static func refusal(service: ModeService, mode: OperationMode) -> String {
        let alternativas: String
        switch service {
        case .calculation:
            alternativas = """
            ["medir CPU/RAM/GPU","ler estado do set"]
            """
        case .monitoring:
            alternativas = """
            ["ler estado do set"]
            """
        }
        return """
        {"blocked":true,"reason":"modo \(mode.rawValue) não oferece \(service.rawValue)",\
        "alternatives":\(alternativas)}
        """
    }
}
