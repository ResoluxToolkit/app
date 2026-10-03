import Foundation

/// Le a grade crua do REST e responde a pergunta que ele sempre quis: "coloquei
/// 10 videos um do lado do outro -- quanto tempo isso deu?"
///
/// Por que isso nao existe no Arena: num editor linear o operador olha a posicao
/// no fim da montagem e ve a duracao. O Arena nao e linear -- acesso aleatorio --
/// e todo mundo monta *como se* fosse, sem nunca saber o total. A gente faz a
/// conta que o produto nao faz.
///
/// Trava dura que ja sai daqui: **nenhum numero de slider entra como grandeza
/// fisica.** Ele avisou duas vezes -- posicionamento vai de -32768 a 32768 e "esse
/// tamanho e um metro ou um km" depende do venue; tem slider normalizado de 0 a 1.
/// Projecao mapeada e onde isso passaria a importar, e essa gente a gente nao
/// atende (decisao dele: "simplesmente uma coisa que nao oferecemos"). Entao so
/// usamos campo que o **documento dele nomeia com unidade**:
/// `transport.controls.duration` (segundos) e `file-info.duration_ms`
/// (milissegundos).
public enum TimelineCalculator {

    /// Duracao que a casa da a uma imagem sem linha do tempo propia, em ms.
    /// Preferencia declarada por ele: eram 5 s, hoje **1 s**. Ultima fonte, usada
    /// so quando nem o transporte nem o arquivo dizem nada.
    public static let imagemPadraoMS: Double = 1_000

    /// Extrai os slots da resposta de `GET /composition`, camada por camada, na
    /// ordem em que o Arena devolve. Indices viram endereco `camada.coluna`
    /// (1-based, igual ao REST). Nome nunca e chave: medido na composicao viva
    /// "Spike", "Line Scape" aparece tres vezes em camadas diferentes.
    public static func slots(from composition: MCPValue) -> [SlotState] {
        guard let layers = composition["layers"]?.arrayValue else { return [] }
        let bpm = bpmDaComposicao(composition)
        var saida: [SlotState] = []
        for (layerIndex, layer) in layers.enumerated() {
            let ativoID = layer["active_clip"]?["id"]?.intValue
            let pilotoCamada = layer["autopilot"]?["target"]?.parameterValue?.stringValue
            let vocabularioCamada = layer["autopilot"]?["duration_type"]?
                .parameterValue?.stringValue
            guard let clips = layer["clips"]?.arrayValue else { continue }
            for (columnIndex, clip) in clips.enumerated() {
                let videoFileInfo = clip["video"]?["fileinfo"]
                let audioFileInfo = clip["audio"]?["fileinfo"]
                let transporte = clip["transport"]?.objectValue
                let controle = transporte?["controls"]?.objectValue
                let nome = clip["name"]?.parameterValue?.stringValue ?? ""
                let conteudoAuxiliar = conteudo(videoFileInfo: videoFileInfo,
                                               audioFileInfo: audioFileInfo,
                                               transporte: transporte != nil,
                                               nome: nome)
                let avanca = autoPiloto(do: clip, pilotoDaCamada: pilotoCamada)
                // Sem trilho nao ha regime: o tempo volta a ser do clipe. amarrar
                // regime a piloto ligado e o que impede um set manual de ser lido
                // como se estivesse no relogio do autopilot.
                let regime = avanca
                    ? Self.regime(do: clip, daCamada: vocabularioCamada) : nil
                let fonte = fonteDuracao(do: clip, content: conteudoAuxiliar, regime: regime)
                saida.append(SlotState(
                    layer: layerIndex + 1,
                    column: columnIndex + 1,
                    name: nome,
                    content: conteudoAuxiliar,
                    state: estado(do: clip, ativoID: ativoID),
                    bus: .desconhecido,
                    durationMS: duracao(do: clip, content: conteudoAuxiliar,
                                        regime: regime, bpm: bpm),
                    durationSource: fonte,
                    speed: controle?["speed"]?.parameterValue?.doubleValue ?? 1,
                    playMode: controle?["playmode"]?.parameterValue?.stringValue,
                    transportType: clip["transporttype"]?.parameterValue?.stringValue,
                    autoAvanca: avanca,
                    regime: regime))
            }
        }
        return saida
    }

    /// Soma uma linha na ordem recebida. Quem chama decide a sequencia (normal
    /// mente uma camada, colunas 1..N) -- a calculadora nao inventa ordem porque
    /// o Arena nao tem ordem.
    ///
    /// Regra que ele deu e que manda aqui: bloco em alto piloto e como um
    /// **Merge** -- "ele quer que aquilo toque de uma vez". Entao rolo consecutivo
    /// com autopilot ligado vira UM passo, e o total dele e a soma do rolo. Sem
    /// piloto cada clipe e um passo avulso, e continua rotulado como avulso pra
    /// ninguem ler aquilo como promessa de sequencia.
    public static func linha(_ slots: [SlotState]) -> TimelineResult {
        var blocos: [TimelineBlock] = []
        var semTempo: [String] = []
        var rolo: [SlotState]?

        func fechaRolo(_ atual: [SlotState]) {
            guard !atual.isEmpty else { return }
            var total = 0.0
            var descobertos: [String] = []
            for slot in atual {
                if let ms = slot.effectiveMS { total += ms }
                else { descobertos.append(slot.address) }
            }
            blocos.append(TimelineBlock(
                enderecos: atual.map(\.address),
                titulos: atual.map { $0.name.isEmpty ? $0.address : $0.name },
                totalMS: total,
                origem: atual.count > 1 ? .autoPilot : .avulso,
                semDuracao: descobertos))
        }

        for slot in slots {
            // Sintetico/generator fica fora: decisao dele, "synth nao tem
            // duracao, synth e performance". Somar o `duration` nominal do
            // transporte aqui seria inventar tempo de show.
            guard slot.content.temMidia else {
                if slot.content == .gerador { semTempo.append(slot.address) }
                continue
            }
            if slot.autoAvanca {
                rolo = (rolo ?? []) + [slot]
                continue
            }
            fechaRolo(rolo ?? [])
            rolo = nil
            if let ms = slot.effectiveMS {
                blocos.append(TimelineBlock(
                    enderecos: [slot.address], titulos: [slot.name.isEmpty ? slot.address : slot.name],
                    totalMS: ms, origem: .avulso))
            } else {
                semTempo.append(slot.address)
            }
        }
        fechaRolo(rolo ?? [])

        let total = blocos.reduce(0) { $0 + $1.totalMS }
        return TimelineResult(blocos: blocos, semTempo: semTempo, totalMS: total)
    }

    /// Detectou intencao de linha? Alto piloto diz "quero que toque sozinho/em
    /// sequencia", entao faz sentido oferecer a conta. Com tudo desligado o cara
    /// esta escolhendo na mao e calcular ali e ruido. Medido nas 3 camadas da
    /// composicao viva: `autopilot.target = "Off"`. NAO olhamos tamanho de grade:
    /// 3x9 com 27 slots vagos e o berco do projeto, nao escolha.
    public static func intencaoDeLinha(from composition: MCPValue) -> Bool {
        guard let layers = composition["layers"]?.arrayValue else { return false }
        return layers.contains { layer in
            guard let alvo = layer["autopilot"]?["target"]?.parameterValue?.stringValue
            else { return false }
            return Self.autopilotLigado(alvo)
        }
    }

    // MARK: - classificacao

    static func conteudo(videoFileInfo: MCPValue?, audioFileInfo: MCPValue?,
                         transporte: Bool, nome: String) -> SlotContent {
        if let caminho = videoFileInfo?["path"]?.stringValue, !caminho.isEmpty {
            return Self.extensaoDeMidia(caminho).isImagem ? .imagem : .video
        }
        if let caminho = audioFileInfo?["path"]?.stringValue, !caminho.isEmpty,
           Self.extensaoDeMidia(caminho).isAudio { return .audio }
        // Sem caminho em disco: ou e generator do Arena, ou o slot esta vazio.
        guard transporte, !nome.isEmpty else { return .vazio }
        return .gerador
    }

    /// So `active_clip` por camada e legivel no REST (medido). `pausado` nao
    /// existe na API dele -- nao inventamos estado que a maquina nao conta.
    static func estado(do clip: MCPValue, ativoID: Int?) -> PlaybackState {
        guard clip["transport"]?.objectValue != nil else { return .desconhecido }
        if let id = clip["id"]?.intValue, let ativoID, id == ativoID { return .reproduzindo }
        return .parado
    }

    /// Transporte ganha sobre midia: e decisao do operador e vale pra imagem, que
    /// nao tem duracao propria. Midia cobre quando o transporte nao diz nada.
    /// Em ultimo caso, imagem herda o padrao da casa. Nunca devolvemos 0.
    static func duracao(do clip: MCPValue, content: SlotContent,
                        regime: RegimeDePiloto? = nil, bpm: Double? = nil) -> Double? {
        switch fonteDuracao(do: clip, content: content, regime: regime) {
        case .piloto:
            return tempoDoPiloto(do: clip, regime: regime, bpm: bpm)
        case .transporte:
            guard let segundos = clip["transport"]?["controls"]?["duration"]?
                .parameterValue?.doubleValue else { return nil }
            return segundos * 1_000
        case .midia:
            return clip["video"]?["fileinfo"]?["duration_ms"]?.doubleValue
                ?? clip["audio"]?["fileinfo"]?["duration_ms"]?.doubleValue
        case .presumida:
            return imagemPadraoMS
        case .nenhuma:
            return nil
        }
    }

    /// Ordem de confianca: transporte (decisao do operador) > midia (fato do
    /// arquivo, audio e video) > padrao da casa, so pra imagem > nenhuma. Nunca
    /// devolvemos 0 -- zero faria uma linha parecer mais curta que o show real.
    ///
    /// Imagem NUNCA cai em `.midia`: o `duration_ms` do arquivo de imagem nao e
    /// tempo de tela, e um numero sem significado cronometrico. Tempo de imagem e
    /// o que o transporte disser ou o padrao da casa (1 s). Deixar o arquivo falar
    /// inflaria a linha com tempo que nenhum operador programou.
    static func fonteDuracao(do clip: MCPValue, content: SlotContent,
                             regime: RegimeDePiloto? = nil) -> DurationSource {
        // Trilho manda: comSeconds/Beats ligados o tempo do passo NAO e do clipe.
        if let regime, regime != .transporte { return .piloto }
        if clip["transport"]?["controls"]?["duration"]?.parameterValue?.doubleValue != nil {
            return .transporte
        }
        if content != .imagem,
           clip["video"]?["fileinfo"]?["duration_ms"]?.doubleValue != nil
            || clip["audio"]?["fileinfo"]?["duration_ms"]?.doubleValue != nil { return .midia }
        if content == .imagem { return .presumida }
        return .nenhuma
    }

    /// Alto piloto resolvido. O campo do clipe aceita "Layer Determined", que
    /// delega pra camada -- ignorar isso leria "Off" onde o operador ligou o
    /// encadeamento, ou vice-versa.
    static func autoPiloto(do clip: MCPValue, pilotoDaCamada: String?) -> Bool {
        var alvo = clip["autopilot"]?["target"]?.parameterValue?.stringValue
        if alvo == "Layer Determined" || alvo == nil { alvo = pilotoDaCamada }
        guard let alvo else { return false }
        return autopilotLigado(alvo)
    }

    static func autopilotLigado(_ alvo: String) -> Bool {
        alvo != "Off" && alvo != "Do nothing" && alvo != "Layer Determined"
    }

    /// BPM do set. Mora em `tempocontroller.tempo` (ParamRange 20...500, medido
    /// hoje em 120), NAO no clipe -- e por isso existe: sem ele o regime `Beats`
    /// do alto piloto nao tem como virar tempo de tela. Nil honesto quando nao ha
    /// numero; nesse caso devolvemos `.nenhuma` pra duracao, nunca chutamos 120.
    static func bpmDaComposicao(_ composition: MCPValue) -> Double? {
        composition["tempocontroller"]?["tempo"]?.parameterValue?.doubleValue
    }

    /// Qual vocabulario de duracao vale para este passo. Medido: camada responde
    /// "Clip Transport"/"Beats"/"Seconds" e clipe responde "Layer Determined"/
    /// "Transport"/"Beats"/"Seconds" -- nomes diferentes pra mesma ideia, entao o
    /// clipe so delega quando diz exatamente "Layer Determined".
    static func regime(do clip: MCPValue, daCamada vocabularioCamada: String?)
        -> RegimeDePiloto? {
        let bruto = clip["autopilot"]?["duration_type"]?.parameterValue?.stringValue
        let valido = (bruto == nil || bruto == "Layer Determined") ? vocabularioCamada : bruto
        switch valido {
        case "Seconds": return .segundos
        case "Beats": return .batidas
        case "Clip Transport", "Transport": return .transporte
        default: return nil
        }
    }

    /// Quantos ms o alto piloto reserva para o passo. Seconds e o relogio cru;
    /// Beats precisa do BPM do set pra virar delta time. Sem numero => nil, e o
    /// slot cai em `semTempo` com endereco -- nao inventamos passo mais curto.
    static func tempoDoPiloto(do clip: MCPValue, regime: RegimeDePiloto?,
                              bpm: Double?) -> Double? {
        let autopiloto = clip["autopilot"]
        switch regime {
        case .segundos:
            guard let segundos = autopiloto?["seconds"]?.parameterValue?.doubleValue else {
                return nil
            }
            return segundos * 1_000
        case .batidas:
            guard let batidas = autopiloto?["beats"]?.parameterValue?.doubleValue,
                  let bpm, bpm > 0 else { return nil }
            // 60_000 ms por batida, porque tempo em jogo e delta time absoluto.
            return batidas * (60_000 / bpm)
        case .transporte, .none:
            return nil
        }
    }

    struct Extensao: Sendable {
        var isImagem: Bool
        var isAudio: Bool
    }

    static func extensaoDeMidia(_ path: String) -> Extensao {
        let ext = (path as NSString).pathExtension.lowercased()
        let imagens: Set<String> = ["png", "jpg", "jpeg", "gif", "tif", "tiff",
                                   "bmp", "webp", "heic", "tga", "psd"]
        let audios: Set<String> = ["mp3", "wav", "aif", "aiff", "flac", "ogg",
                                  "m4a", "aac"]
        return Extensao(isImagem: imagens.contains(ext), isAudio: audios.contains(ext))
    }
}
