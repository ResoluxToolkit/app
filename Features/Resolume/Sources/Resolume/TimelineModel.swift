import Foundation

/// Modelo de um slot da grade do Arena, na taxonomia que ele ditou. A grade nao
/// e "quantos clipes existem": e um retangulo fixo onde cada posicao tem estado.
/// Ele foi literal: o projeto nasce com 9 colunas e 3 layers -- 27 slots, e a
/// maioria existe vazia. Tamanho de grade, portanto, nao sinaliza intencao.
///
/// Os tres eixos que ele enumerou: conteudo (vazio/Imagem/Audio/Video), execucao
/// (Parado/Reproduzindo/Pausado) e saida (Preview/PGR).
///
/// Moeda do eixo de tempo e milissegundo absoluto -- delta time, como ele
/// chamou. Frames nunca entram na conta: o projeto novo nasce com FrameRate
/// `Auto` (medido: `framerate.value = 0.0`), entao nao existe fps fixo pra
/// dividir frames, e cada arquivo traz fps proprio. Num editor linear isso seria
/// obrigatorio; aqui nao e. FPS so importa pra imagem nao engasgar -- painel de
/// LED costuma pedir 60 travados -- e isso e assunto do modo Performance.
public enum SlotContent: String, Sendable, Codable, CaseIterable {
    /// Slot existe na grade mas nao carrega nada.
    case vazio
    /// Imagem arrastada pra grade.
    case imagem
    /// Arquivo so de audio.
    case audio
    /// Arquivo com trilha de video.
    case video
    /// Generator/synth do proprio Arena: sem arquivo, sem duracao de midia.
    case gerador

    /// Tem midia em disco pra cronometrar?
    public var temMidia: Bool {
        switch self {
        case .imagem, .audio, .video: return true
        case .vazio, .gerador: return false
        }
    }
}

/// Estado de execucao do slot. `desconhecido` e onesto, nao preguica: nem o REST
/// nem o MCP do Arena expoem "parado x pausado" por clipe (medido em
/// `GET /composition`: existe `active_clip` por camada, e so). Nao inventamos.
public enum PlaybackState: String, Sendable, Codable, CaseIterable {
    case parado, reproduzindo, pausado, desconhecido
}

/// Saida do barramento. De novo `desconhecido` por medida: o Arena nao expoe
/// Preview x PGR por clipe. Chutar saida colocaria gente no ar errado.
public enum OutputBus: String, Sendable, Codable, CaseIterable {
    case fora, preview, pgr, previewEPgr, desconhecido
}

/// De onde veio o numero de tempo, porque a confianca muda. Duracao de midia e
/// fato do arquivo; duracao de transporte e decisao do operador -- e a unica que
/// existe quando a midia nao tem duracao propria (imagem).
public enum DurationSource: String, Sendable, Codable, CaseIterable {
    case midia, transporte, presumida, nenhuma
    /// O tempo nao veio do clipe nem do arquivo: veio do **alto piloto**. Quando o
    /// clipe entra no trilho do piloto, quem diz quanto ele fica na tela e o
    /// `duration_type` da camada -- o `transport.duration` continua la, mas deixa
    /// de ser o relogio da linha. Somar o transporte nesse caso e mentir no total.
    case piloto
}

/// O regime do alto piloto: de onde o Arena tira o tempo de cada passo quando o
/// encadeamento esta ligado. Medido no payload vivo, os tres niveis usam
/// vocabularios DIFERENTES pra mesma ideia -- por isso isso e enum e nao string:
///   camada     -> "Clip Transport" | "Beats" | "Seconds"
///   clipe       -> "Layer Determined" | "Transport" | "Beats" | "Seconds"
///   composicao  -> "Longest Clip" | ... (a gente nao opera aqui)
/// Ler um vocabulario pelo outro leria `nil` onde existe conta, ou vice-versa.
public enum RegimeDePiloto: String, Sendable, Codable, CaseIterable {
    /// Cada passo dura o que o transporte do clipe diz (o default da casa).
    case transporte
    /// Todos os passos duram `autopilot.seconds`, independente do arquivo.
    case segundos
    /// Todos os passos duram `autopilot.beats`, convertidos pelo BPM do set.
    case batidas
}

/// De quem e o relogio daquele clipe. Vocabulario medido no payload vivo
/// (`transporttype`: ParamChoice, 73 ocorrencias, todas "Timeline", e o payload
/// entrega a lista inteira) -- identico ao dropdown que ele fotografou:
///   ["Timeline", "BPM Sync", "SMPTE 1", "SMPTE 2", "Denon DJ", "Pioneer DJ"]
/// Tradugao que ele deu e que manda aqui:
///   Timeline      -> Cronometria.    Relogio nosso: soma vale.
///   BPM Sync      -> Performance.    Relogio da batida do set.
///   SMPTE 1 / 2   -> Evento sincronizado. Relogio do timecode externo.
///   Denon/Pioneer -> Controlado pela musica. Relogio da mesa.
/// Nao e enfeite: somar um clipe em SMPTE como se o relogio fosse nosso promete um
/// total que nenhuma maquina confirma -- o erro que a regra dele ("em set sincrono
/// o play nunca e ato nosso") proibe.
public enum RelogioDoClipe: String, Sendable, Codable, CaseIterable {
    case timeline, batidas, smpte1, smpte2, mesa, desconhecido

    /// Nomes crus que o Arena usa pra esse relogio -- no vocabulario EXATO da
    /// maquina, porque e assim que log e diagnostico tem que falar (a origem, nao
    /// a nossa classe). `.mesa` carrega dois nomes: Denon e Pioneer sao opcoes
    /// distintas no dropdown e a mesma coisa pra gente -- o relogio e da mesa.
    /// `.desconhecido` nao tem nome: e o resto que sobrou, nao um valor do Arena.
    public var nomesNoArena: [String] {
        switch self {
        case .timeline: return ["Timeline"]
        case .batidas: return ["BPM Sync"]
        case .smpte1: return ["SMPTE 1"]
        case .smpte2: return ["SMPTE 2"]
        case .mesa: return ["Denon DJ", "Pioneer DJ"]
        case .desconhecido: return []
        }
    }

    /// A gente pode cronometrar? So quando o relogio e nosso.
    public var relogioENosso: Bool { self == .timeline }

    /// Classifica pelo nome cru. Ausencia vira `.timeline`, nao `.desconhecido`:
    /// medido que `index = 0`/"Timeline" e o valor de fabrica de todo clipe novo,
    /// entao quem nao tem campo nao foi mexido. Ja nome que nao conhecemos vira
    /// `.desconhecido` e fica fora da conta -- nao sabemos de quem e o relogio ali,
    /// e chutar "e Timeline" inflaria a linha.
    public static func classificar(_ bruto: String?) -> RelogioDoClipe {
        switch bruto {
        case "Timeline": return .timeline
        case "BPM Sync": return .batidas
        case "SMPTE 1": return .smpte1
        case "SMPTE 2": return .smpte2
        case "Denon DJ", "Pioneer DJ": return .mesa
        case nil: return .timeline
        default: return .desconhecido
        }
    }
}

/// Um slot da grade, com o que da pra ler dele.
public struct SlotState: Sendable, Equatable {
    /// Camada 1-based, igual ao endereco do REST.
    public var layer: Int
    /// Coluna 1-based.
    public var column: Int
    public var name: String
    public var content: SlotContent
    public var state: PlaybackState
    public var bus: OutputBus
    /// Duracao bruta em ms (`nil` quando nao ha numero algum -- nunca 0).
    public var durationMS: Double?
    public var durationSource: DurationSource
    /// Multiplicador do transporte. Tempo real de tela e `duracao / speed`.
    public var speed: Double
    /// `Loop`, `Bounce`, `Play Once & Hold`... Guarda porque muda a leitura: um
    /// clipe em Loop nao entrega a vez pro vizinho sozinho.
    public var playMode: String?
    /// `Timeline` / `BPM Sync` / SMPTE... So `Timeline` tem tempo independente de
    /// BPM, que e a regra que ele cobrou no modo Timeline.
    public var transportType: String?
    /// Alto piloto resolvido (clipe, caindo na camada quando "Layer Determined").
    /// E o detector de intencao: ligado significa "quero que toque sozinho".
    public var autoAvanca: Bool
    /// Qual regime manda no tempo deste slot. So vem preenchido com piloto LIGADO
    /// e `duration_type` presente; `nil` e o caso honesto -- naochutamos regime.
    public var regime: RegimeDePiloto?

    public init(layer: Int, column: Int, name: String, content: SlotContent,
                state: PlaybackState, bus: OutputBus, durationMS: Double?,
                durationSource: DurationSource, speed: Double, playMode: String?,
                transportType: String?, autoAvanca: Bool,
                regime: RegimeDePiloto? = nil) {
        self.layer = layer
        self.column = column
        self.name = name
        self.content = content
        self.state = state
        self.bus = bus
        self.durationMS = durationMS
        self.durationSource = durationSource
        self.speed = speed
        self.playMode = playMode
        self.transportType = transportType
        self.autoAvanca = autoAvanca
        self.regime = regime
    }

    /// Tempo que esse slot ocupa de tela.
    ///
    /// Com tempo vindo do **clipe** (transporte ou arquivo), o multiplicador entra
    /// na conta: 10 s a 2x sao 5 s de tela -- delta time puro, regra dele.
    ///
    /// Com tempo vindo do **piloto** em `Seconds`/`Beats`, NAO entra: o piloto fixa
    /// quanto o passo segura a tela, e o `speed` muda como a midia roda ai dentro,
    /// nao o relogio da linha. Dividir ali seria encurtar um relogio que nao e do
    /// clipe. `instavel:` -- ainda nao medimos com piloto LIGADO (nesta maquina as 3
    /// camadas estao com o piloto desligado). A medicao que fecha o buraco e um
    /// `GET /composition` com ele ligando o piloto num ensaio, e ele ofereceu:
    /// "podemos fazer a qualquer momento". Ate la, o numero sai rotulado `.piloto`.
    /// Se o piloto acompanhar o speed, e uma linha pra mudar.
    public var effectiveMS: Double? {
        guard let durationMS else { return nil }
        // Trava de sincronia. Com o piloto em Seconds/Beats o relogio do passo e
        // wall-clock e conta; caso contrario, se o relogio nao e nosso (SMPTE, BPM
        // Sync, mesa), nao ha o que prometer: devolvemos nil e o slot aparece em
        // `semTempo` com endereco. Somar ali seria mentir no total.
        if durationSource != .piloto, !relogio.relogioENosso { return nil }
        if durationSource == .piloto, regime != .transporte { return durationMS }
        guard speed > 0, speed != 1 else { return durationMS }
        return durationMS / speed
    }

    /// De quem e o relogio deste clipe, derivado do nome cru. Derivar (e nao
    /// guardar os dois) e de proposito: o vocabulario chega inteiro no payload, e
    /// guardar copia daria duas verdades pra uma coisa so.
    public var relogio: RelogioDoClipe { RelogioDoClipe.classificar(transportType) }

    /// Identidade estavel do slot: camada.coluna. Nunca nome nem indice de
    /// lista -- medido na composicao viva "Spike", "Line Scape" aparece tres
    /// vezes em camadas diferentes, e crescer grade muda indices.
    public var address: String { "\(layer).\(column)" }
}

/// Um bloco da linha: rolo de slots consecutivos em alto piloto. Palavra dele:
/// bloco em autopilot e como um *Merge* -- "ele quer que aquilo toque de uma vez",
/// entao a gente trata o rolo como uma coisa so e devolve o total dele.
public struct TimelineBlock: Sendable, Equatable {
    public enum Origem: String, Sendable, Codable, CaseIterable {
        /// Somado porque o alto piloto encadeia os clipes.
        case autoPilot
        /// Sem alto piloto: acesso aleatorio, entra na conta mas rotulado.
        case avulso
    }

    public var enderecos: [String]
    public var titulos: [String]
    public var totalMS: Double
    public var origem: Origem

    /// Sem duracao legivel em nenhum canto. Continua sendo um passo do show,
    /// mas nao contribui pro total -- e isso que a gente precisa dizer em voz
    /// alta, em vez de somar zero e mentir.
    public var semDuracao: [String]

    public init(enderecos: [String], titulos: [String], totalMS: Double,
                origem: Origem, semDuracao: [String] = []) {
        self.enderecos = enderecos
        self.titulos = titulos
        self.totalMS = totalMS
        self.origem = origem
        self.semDuracao = semDuracao
    }
}

/// Resultado de uma linha: quanto tempo deu, de que ele e feito, e o que ficou
/// de fora por nao ter tempo legivel.
public struct TimelineResult: Sendable, Equatable {
    public var blocos: [TimelineBlock]
    /// Enderecos ocupados sem nenhum numero de duracao.
    public var semTempo: [String]
    /// Tempo previsivel total, em ms. Delta time puro: soma de duracoes
    /// absolutas, sem frames, sem BPM.
    public var totalMS: Double

    public init(blocos: [TimelineBlock], semTempo: [String] = [], totalMS: Double = 0) {
        self.blocos = blocos
        self.semTempo = semTempo
        self.totalMS = totalMS
    }

    /// Apresentação ("isso calcula depois", por ele). Existe so pra nao termos
    /// que montar string espalhado pela UI.
    public var totalFormatado: String { TimelineResult.format(totalMS) }

    public static func format(_ ms: Double) -> String {
        let inteiro = Int(ms.rounded())
        let horas = inteiro / 3_600_000
        let minutos = (inteiro % 3_600_000) / 60_000
        let segundos = (inteiro % 60_000) / 1_000
        let milesimos = inteiro % 1_000
        if horas > 0 {
            return String(format: "%dh %02dm %02ds", horas, minutos, segundos)
        }
        if milesimos > 0 {
            return String(format: "%dm %02d.%03ds", minutos, segundos, milesimos)
        }
        return String(format: "%dm %02ds", minutos, segundos)
    }
}
