import Foundation
import Testing
@testable import Resolume

/// Monta um clipe cru no formato exato que o `GET /composition` devolve
/// (embrulhadura `{"valuetype":..., "value":...}` em todo param). Copiado do
/// payload vivo da composicao "Spike", Arena 7.28.0-rev24303.
private func param(_ valor: MCPValue) -> MCPValue { .object(["valuetype": .string("ParamRange"), "value": valor]) }
private func escolha(_ valor: String) -> MCPValue {
    .object(["valuetype": .string("ParamChoice"), "value": .string(valor)])
}

private func clipe(id: Int = 1, nome: String = "", caminhoVideo: String? = nil,
                   caminhoAudio: String? = nil, duracaoSegundos: Double? = nil,
                   speed: Double = 1, playmode: String = "Loop",
                   transportType: String = "Timeline", piloto: String? = nil,
                   tipoDuracaoPiloto: String? = nil, segundosPiloto: Double? = nil,
                   batidasPiloto: Double? = nil) -> MCPValue {
    var transporte: MCPValue? = nil
    var controles: [String: MCPValue] = [
        "speed": param(.double(speed)),
        "playmode": escolha(playmode),
    ]
    if let duracaoSegundos { controles["duration"] = param(.double(duracaoSegundos)) }
    if duracaoSegundos != nil {
        transporte = .object(["position": param(.double(0)), "controls": .object(controles)])
    }
    if nome.isEmpty && duracaoSegundos == nil && caminhoVideo == nil { transporte = nil }

    var video: [String: MCPValue] = [:]
    if let caminhoVideo {
        video["fileinfo"] = .object(["path": .string(caminhoVideo), "exists": .bool(true),
                                     "duration_ms": .double(20_000)])
    }
    var audio: [String: MCPValue] = [:]
    if let caminhoAudio {
        audio["fileinfo"] = .object(["path": .string(caminhoAudio), "exists": .bool(true),
                                     "duration_ms": .double(30_000)])
    }
    var objeto: [String: MCPValue] = [
        "id": .int(id),
        "name": .object(["valuetype": .string("ParamString"), "value": .string(nome)]),
        "video": .object(video),
        "audio": .object(audio),
        "transporttype": escolha(transportType),
        "thumbnail": .object(["is_default": .bool(nome.isEmpty)]),
    ]
    if let transporte { objeto["transport"] = transporte }
    var pilotoObj: [String: MCPValue] = [:]
    if let piloto { pilotoObj["target"] = escolha(piloto) }
    // Medido: o vocabulario do CLIPE he "Layer Determined"/"Transport"/"Beats"/
    // "Seconds" -- diferente do da camada. Os testes usam o nome cru de proposito.
    if let tipoDuracaoPiloto { pilotoObj["duration_type"] = escolha(tipoDuracaoPiloto) }
    if let segundosPiloto { pilotoObj["seconds"] = param(.double(segundosPiloto)) }
    if let batidasPiloto { pilotoObj["beats"] = param(.double(batidasPiloto)) }
    if !pilotoObj.isEmpty { objeto["autopilot"] = .object(pilotoObj) }
    return .object(objeto)
}

/// `tipoDuracao` usa o vocabulario DA CAMADA: "Clip Transport"/"Beats"/"Seconds"
/// (medido no payload vivo -- nao e o mesmo vocabulario do clipe).
private func camada(_ clipes: [MCPValue], piloto: String = "Off",
                    tipoDuracao: String = "Clip Transport") -> MCPValue {
    .object(["id": .int(1), "name": .string("L"),
             "autopilot": .object(["target": escolha(piloto),
                                   "duration_type": escolha(tipoDuracao)]),
             "active_clip": .null,
             "clips": .array(clipes)])
}

/// `bpm` mora em `tempocontroller.tempo` (medido: ParamRange 20...500, hoje 120).
/// Sem ele o regime "Beats" nao tem como virar tempo -- e e justamente o caso que
/// os testes de ausencia cobrem.
private func composicao(_ camadas: [MCPValue], bpm: Double? = nil) -> MCPValue {
    var objeto: [String: MCPValue] = [
        "name": .string("Spike"),
        "framerate": param(.double(0)),
        "layers": .array(camadas),
    ]
    if let bpm {
        objeto["tempocontroller"] = .object(["tempo": param(.double(bpm))])
    }
    return .object(objeto)
}

@Test("grade nasce 3x9 e todos os 27 slots sao vistos, inclusive os vazios")
func gradeNasceCheia() {
    // O projeto novo tem 3 camadas x 9 colunas por construcao (palavra dele),
    // entao tamanho de grade nao pode ser sinal de nada. Leemos o retangulo todo.
    let c = composicao([camada((1...9).map { _ in clipe() }),
                        camada((1...9).map { _ in clipe() }),
                        camada((1...9).map { _ in clipe() })])
    let slots = TimelineCalculator.slots(from: c)
    #expect(slots.count == 27)
    #expect(slots.filter { $0.content == .vazio }.count == 27)
    #expect(Array(slots.map(\.address).prefix(3)) == ["1.1", "1.2", "1.3"])
}

@Test("duracao vem do transporte em segundos absolutos, nunca de frames")
func transporteFalaEmSegundos() throws {
    // Medido no payload vivo: transport.controls.duration = ParamRange em
    // SEGUNDOS (max 604800 = 7 dias). FPS nao entra na conta -- FrameRate e Auto
    // (`framerate.value = 0.0`) e cada arquivo traz fps proprio.
    let c = composicao([camada([clipe(nome: "V", caminhoVideo: "/m/a.mp4",
                                      duracaoSegundos: 12.5)])])
    let slot = try #require(TimelineCalculator.slots(from: c).first)
    #expect(slot.durationMS == 12_500)
    #expect(slot.durationSource == .transporte)
    #expect(slot.effectiveMS == 12_500)
}

@Test("speed encurta o tempo de tela real")
func velocidadeCorrigeTempo() throws {
    // duration 10 s a 2x = 5 s de tela. Delta time continua sendo o resultado.
    let c = composicao([camada([clipe(nome: "V", caminhoVideo: "/m/a.mp4",
                                      duracaoSegundos: 10, speed: 2)])])
    let slot = try #require(TimelineCalculator.slots(from: c).first)
    #expect(slot.effectiveMS == 5_000)
}

@Test("sem numero de duracao em lugar nenhum NAO soma zero")
func ausenciaNaoViraZero() {
    // Somar zero faria a linha parecer mais curta que o show real -- pior erro
    // possivel pra uma ferramenta cujo unico trabalho e dizer tempo.
    let vazio = clipe()
    #expect(TimelineCalculator.slots(from: composicao([camada([vazio])])).first?.durationMS == nil)
    #expect(TimelineCalculator.slots(from: composicao([camada([vazio])])).first?.durationSource == .nenhuma)
}

@Test("generator do Arena fica fora da conta: synth e performance")
func synthNaoEntraNaLinha() {
    // Palavra dele: "Synth nao tem duracao -- Synth e performance, a gente nem se
    // mete. Essa ferramenta e morta." E medido: `video.fileinfo` e null nos 12
    // clipes da composicao viva, que sao todos generators.
    let c = composicao([camada([clipe(nome: "Metaballs", duracaoSegundos: 5),
                               clipe(nome: "Lips", duracaoSegundos: 5)],
                              piloto: "Play Next Clip")])
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(from: c))
    #expect(resultado.totalMS == 0)
    #expect(resultado.blocos.isEmpty)
    #expect(resultado.semTempo == ["1.1", "1.2"])
}

@Test("bloco em alto piloto e um Merge: rolo consecutivo vira um passo so")
func autopilotFazMerge() {
    // Dele: "os blocos que tiverem em Auto Pilot a gente considera como se ele
    // fizesse um Merge... ele quer que aquilo no toque de uma vez".
    let tres = (1...3).map { i in
        clipe(id: i, nome: "V\(i)", caminhoVideo: "/m/\(i).mp4",
              duracaoSegundos: 20, piloto: "Play Next Clip")
    }
    let c = composicao([camada(tres + [clipe()])])
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(from: c))
    #expect(resultado.blocos.count == 1)
    let bloco = try! #require(resultado.blocos.first)
    #expect(bloco.enderecos == ["1.1", "1.2", "1.3"])
    #expect(bloco.origem == .autoPilot)
    #expect(bloco.totalMS == 60_000)
    #expect(resultado.totalMS == 60_000)
}

@Test("rolo de Merge para onde o piloto desliga")
func mergeParaNoDesligamento() {
    let slots = [clipe(id: 1, nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 10,
                       piloto: "Play Next Clip"),
                 clipe(id: 2, nome: "B", caminhoVideo: "/b.mp4", duracaoSegundos: 10,
                       piloto: "Play Next Clip"),
                 clipe(id: 3, nome: "C", caminhoVideo: "/c.mp4", duracaoSegundos: 30,
                       piloto: "Do nothing")]
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(
        from: composicao([camada(slots)])))
    #expect(resultado.blocos.map(\.enderecos) == [["1.1", "1.2"], ["1.3"]])
    #expect(resultado.blocos.map(\.origem) == [.autoPilot, .avulso])
    #expect(resultado.totalMS == 50_000)
}

@Test("\"Layer Determined\" no clipe herda o piloto da camada")
func pilotoHerdadoDaCamada() throws {
    // Ignorar a delegacao leria "Off" onde o operador ligou o encadeamento.
    let slot = try #require(TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 5,
                    piloto: "Layer Determined")], piloto: "Play Next Clip")]))).first
    #expect(slot?.autoAvanca == true)
    let desligado = TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 5,
                    piloto: "Layer Determined")], piloto: "Off")]))
    #expect(desligado.first?.autoAvanca == false)
}

@Test("intencao de linha so existe com alto piloto ligado")
func deteccaoDeIntencao() {
    // Medido na composicao viva: as 3 camadas estao com `target = "Off"`, entao
    // a calculadora NAO se oferece ali -- o cara esta escolhendo na mao.
    #expect(!TimelineCalculator.intencaoDeLinha(
        from: composicao([camada([clipe()], piloto: "Off")])))
    #expect(!TimelineCalculator.intencaoDeLinha(
        from: composicao([camada([clipe()], piloto: "Do nothing")])))
    #expect(TimelineCalculator.intencaoDeLinha(
        from: composicao([camada([clipe()], piloto: "Play Next Clip")])))
    #expect(!TimelineCalculator.intencaoDeLinha(from: .object([:])))
}

@Test("classifica conteudo pelo caminho do arquivo, nao pelo nome")
func conteudoPeloCaminho() throws {
    let c = composicao([camada([
        clipe(nome: "still", caminhoVideo: "/m/cartaz.PNG"),
        clipe(nome: "movie", caminhoVideo: "/m/show.mov"),
        clipe(nome: "som", caminhoAudio: "/m/trilha.WAV"),
    ])])
    let slots = TimelineCalculator.slots(from: c)
    #expect(slots.map(\.content) == [.imagem, .video, .audio])
    // Nome repetido e normal (medido: "Line Scape" 3x) e nunca serve de chave.
    #expect(slots.map(\.address) == ["1.1", "1.2", "1.3"])
}

@Test("imagem sem duracao propria herda 1 s da casa")
func imagemUsaPadraoDaCasa() throws {
    // Ele corrigiu: eram 5 s na casa, hoje e 1 s.
    let slot = try #require(TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "cartaz", caminhoVideo: "/m/a.png")])]))).first
    #expect(slot?.durationSource == .presumida)
    #expect(slot?.durationMS == 1_000)
    #expect(TimelineCalculator.imagemPadraoMS == 1_000)
}

@Test("formato de saida nao vira contrato: apresentacao e depois")
func formatoSoQuandoPedido() {
    #expect(TimelineResult.format(60_000) == "1m 00s")
    #expect(TimelineResult.format(3_600_000 + 90_000) == "1h 01m 30s")
    #expect(TimelineResult.format(1_500) == "0m 01.500s")
}

// MARK: - regua do piloto (trilho)
//
// Pergunta dele: "da pra gerarmos uma regua do tempo se guiando pelo Autopilot?"
// A conta aqui e a resposta. O que muda em relacao ao resto da calculadora e que
// com o trilho ligado o relogio do passo NAO e mais o do clipe: quem manda e o
// `duration_type` (+ `seconds`/`beats`) do autopilot, e o BPM do set quando o
// regime e Beats.

@Test("piloto em Seconds manda no passo e ignora o transporte do clipe")
func pilotoEmSecondsMandaNoPasso() throws {
    // O clipe diz 30 s no transporte e esta a 2x. Com o trilho em Seconds, nenhum
    // dos dois vale: o passo dura o que o piloto fixed. E o speed NAO entra --
    // ele muda como a midia roda dentro do passo, nao o relogio da linha.
    let slot = try #require(TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30, speed: 2,
                    piloto: "Play Next Clip", tipoDuracaoPiloto: "Seconds",
                    segundosPiloto: 7)], piloto: "Play Next Clip")]))).first
    #expect(slot?.regime == .segundos)
    #expect(slot?.durationSource == .piloto)
    #expect(slot?.durationMS == 7_000)
    #expect(slot?.effectiveMS == 7_000)
}

@Test("piloto em Beats vira delta time pelo BPM do set")
func pilotoEmBeatsUsaBPM() throws {
    // BPM mora em composition.tempocontroller.tempo -- unica fonte. 4 batidas a
    // 120 = 2000 ms; o mesmo passo a 60 = 4000 ms. Tempo absoluto, frames fora.
    let quatorze = composicao([camada(
        [clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
              piloto: "Play Next Clip", tipoDuracaoPiloto: "Beats", batidasPiloto: 4)],
        piloto: "Play Next Clip")], bpm: 120)
    let doze = composicao([camada(
        [clipe(id: 9, nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
              piloto: "Play Next Clip", tipoDuracaoPiloto: "Beats", batidasPiloto: 4)],
        piloto: "Play Next Clip")], bpm: 60)
    let a120 = try #require(TimelineCalculator.slots(from: quatorze).first)
    let a60 = try #require(TimelineCalculator.slots(from: doze).first)
    #expect(a120.regime == .batidas)
    #expect(a120.durationSource == .piloto)
    #expect(a120.effectiveMS == 2_000)
    #expect(a60.effectiveMS == 4_000)
}

@Test("Beats sem BPM nao chuta 120: entra como passo sem tempo")
func beatsSemBPMNaoChuta() throws {
    // Sem `tempocontroller` nao ha como converter. Chutar 120 produziria uma
    // regulasoma que nenhuma maquina confirma. Entao devolvemos nil e marcamos.
    let c = composicao([camada(
        [clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
              piloto: "Play Next Clip", tipoDuracaoPiloto: "Beats", batidasPiloto: 4)],
        piloto: "Play Next Clip")])  // sem bpm
    let slot = try #require(TimelineCalculator.slots(from: c).first)
    #expect(slot.regime == .batidas)
    // O rotulo diz "a fonte e o piloto" mesmo sem numero: manter .piloto preserva
    // o diagnostico ("faltou o BPM") em vez de apagar a causa com .nenhuma.
    #expect(slot.durationSource == .piloto)
    #expect(slot.durationMS == nil)
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(from: c))
    #expect(resultado.totalMS == 0)
    // O endereco continua la, rotulado: nada foi somado calado.
    #expect(resultado.blocos.first?.semDuracao == ["1.1"])
}

@Test("duration_type delega para a camada so quando diz Layer Determined")
func vocabularioDelegadoDaCamada() throws {
    // Medido: camada responde "Clip Transport"/"Beats"/"Seconds" e clipe responde
    // "Layer Determined"/"Transport"/"Beats"/"Seconds". Ler um pelo outro daria nil
    // onde existe conta.
    let delegando = TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
                    piloto: "Play Next Clip", tipoDuracaoPiloto: "Layer Determined",
                    segundosPiloto: 3)],
              piloto: "Play Next Clip", tipoDuracao: "Seconds")]))
    #expect(delegando.first?.regime == .segundos)
    #expect(delegando.first?.durationMS == 3_000)

    // Clipe sem `duration_type` algum: cai na camada tambem.
    let mudo = TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
                    piloto: "Play Next Clip")],
              piloto: "Play Next Clip", tipoDuracao: "Seconds")]))
    #expect(mudo.first?.regime == .segundos)

    // Clipe dizendo "Transport" (vocabulario dele) venceu a camada que dizia Seconds.
    let proprio = TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30, speed: 2,
                    piloto: "Play Next Clip", tipoDuracaoPiloto: "Transport",
                    segundosPiloto: 3)],
              piloto: "Play Next Clip", tipoDuracao: "Seconds")]))
    #expect(proprio.first?.regime == .transporte)
    #expect(proprio.first?.durationSource == .transporte)
    // Sob transporte o speed volta a valer: 30 s a 2x sao 15 s de tela.
    #expect(proprio.first?.effectiveMS == 15_000)
}

@Test("piloto desligado devolve o relogio ao clipe")
func pilotoDesligadoDevolveRelogioAoClipe() throws {
    // Amarrar regime a piloto ligado e o que impede um set manual de ser lido como
    // se estivesse no relogio do autopilot -- mesmo com a camada gritando Seconds.
    let slot = try #require(TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 30,
                    tipoDuracaoPiloto: "Seconds", segundosPiloto: 3)],
              piloto: "Off", tipoDuracao: "Seconds")]))).first
    #expect(slot?.regime == nil)
    #expect(slot?.autoAvanca == false)
    #expect(slot?.durationSource == .transporte)
    #expect(slot?.durationMS == 30_000)
}

@Test("regua do piloto soma a linha inteira sem olhar largura de celula")
func reguaSomaLinhaPeloPiloto() throws {
    // Celula do Arena e tamanho fixo: 1 h e 1 s ocupam o mesmo quadrado, entao
    // tempo so pode sair dos dados. Trilho em Seconds de 2.5 s x 3 = 7.5 s, e os
    // transportes de 30 s dos clipes nao entram na conta em lugar nenhum.
    let tres = (1...3).map { i in
        clipe(id: i, nome: "V\(i)", caminhoVideo: "/m/\(i).mp4", duracaoSegundos: 30,
              piloto: "Play Next Clip", tipoDuracaoPiloto: "Seconds", segundosPiloto: 2.5)
    }
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(
        from: composicao([camada(tres, piloto: "Play Next Clip", tipoDuracao: "Seconds")])))
    #expect(resultado.blocos.count == 1)
    #expect(resultado.blocos.first?.enderecos == ["1.1", "1.2", "1.3"])
    #expect(resultado.totalMS == 7_500)
    #expect(resultado.totalFormatado == "0m 07.500s")
}

// MARK: relogio do clipe (trava de sincronia)
//
// Ele fotografou o dropdown de cada clipe e traduziu: Timeline = Cronometria,
// BPM = Performance, SMPTE = Evento Sincronizado, Denon/Pioneer = Controlado pela
// musica. So no primeiro o relogio e nosso, entao so ali a cronometria promete um
// numero. O payload vivo entrega a lista inteira em `transporttype.options`
// (medido: 73 ocorrencias, todas "Timeline"), entao o contrato abaixo e verificado
// contra o que a maquina diz, nao contra chute nosso.

@Test("vocabulario do dropdown e exatamente o medido na maquina")
func vocabularioDoDropdown() {
    // Mesma ordem e mesmos nomes do dropdown que ele fotografou. Se uma update do
    // Arena mudar isso aqui, este teste falha e a gente re-lee -- nao ao contrario.
    let esperado = ["Timeline", "BPM Sync", "SMPTE 1", "SMPTE 2", "Denon DJ", "Pioneer DJ"]
    #expect(RelogioDoClipe.classificar("Timeline") == .timeline)
    #expect(RelogioDoClipe.classificar("BPM Sync") == .batidas)
    #expect(RelogioDoClipe.classificar("SMPTE 1") == .smpte1)
    #expect(RelogioDoClipe.classificar("SMPTE 2") == .smpte2)
    #expect(RelogioDoClipe.classificar("Denon DJ") == .mesa)
    #expect(RelogioDoClipe.classificar("Pioneer DJ") == .mesa)
    // Round-trip: todo nome cru do dropdown tem que chegar numa classe e voltar
    // pro mesmo nome. E assim que o contrato se mantem vivo -- se uma update do
    // Arena trocar "BPM Sync" por outra coisa, isso aqui falha e a gente re-lee a
    // maquina, em vez de somar um relogio que nao e nosso achando que e.
    var cobertos: [String] = []
    for classe in RelogioDoClipe.allCases {
        for nome in classe.nomesNoArena {
            cobertos.append(nome)
            #expect(RelogioDoClipe.classificar(nome) == classe)
        }
    }
    #expect(cobertos.sorted() == esperado.sorted())
    // 6 opcoes no dropdown -> 5 relogios nossos + o resto; nada fica de fora.
    #expect(RelogioDoClipe.allCases.count == 6)
}

@Test("so Timeline tem relogio nosso")
func apenasTimelineECronometria() {
    #expect(RelogioDoClipe.timeline.relogioENosso)
    #expect(!RelogioDoClipe.batidas.relogioENosso)
    #expect(!RelogioDoClipe.smpte1.relogioENosso)
    #expect(!RelogioDoClipe.smpte2.relogioENosso)
    #expect(!RelogioDoClipe.mesa.relogioENosso)
    #expect(!RelogioDoClipe.desconhecido.relogioENosso)
}

@Test("clipe sem campo he Timeline de fabrica, nao desconhecido")
func ausenciaHeFabrica() throws {
    // Medido: todo clipe novo sai com index = 0 / "Timeline". Ausencia quer dizer
    // "ninguem mexeu", e la a gente pode cronometrar. Ja nome desconhecido nao.
    let semCampo = SlotState(layer: 1, column: 1, name: "A", content: .video,
                             state: .parado, bus: .desconhecido, durationMS: 5_000,
                             durationSource: .transporte, speed: 1, playMode: nil,
                             transportType: nil, autoAvanca: false)
    #expect(semCampo.relogio == .timeline)
    #expect(semCampo.effectiveMS == 5_000)

    let nomeEstranho = SlotState(layer: 1, column: 1, name: "A", content: .video,
                                 state: .parado, bus: .desconhecido, durationMS: 5_000,
                                 durationSource: .transporte, speed: 1, playMode: nil,
                                 transportType: "Arquivo Novo Desconhecido", autoAvanca: false)
    #expect(nomeEstranho.relogio == .desconhecido)
    #expect(nomeEstranho.effectiveMS == nil)
}

@Test("SMPTE sai da soma: o relogio e do timecode, nao nosso")
func smpteForaDaSoma() throws {
    // Aqui morava o bug: um clipe de 40 s em SMPTE 1 entrava no total como se o
    // play fosse ato nosso. Em set sincronizado nao e -- o trigger e OSC e o
    // transport e LTC (palavra dele).
    let c = composicao([camada([
        clipe(id: 1, nome: "abertura", caminhoVideo: "/a.mp4", duracaoSegundos: 40),
        clipe(id: 2, nome: "hino", caminhoVideo: "/h.mp4", duracaoSegundos: 90,
              transportType: "SMPTE 1"),
    ])])
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(from: c))
    #expect(resultado.blocos.map(\.enderecos) == [["1.1"]])
    #expect(resultado.totalMS == 40_000)
    #expect(resultado.semTempo == ["1.2"])
}

@Test("BPM Sync e mesa do DJ tambem ficam fora da cronometria")
func batidaEMesaForaDaCronometria() throws {
    let c = composicao([camada([
        clipe(id: 1, nome: "A", caminhoVideo: "/a.mp4", duracaoSegundos: 10,
              transportType: "BPM Sync"),
        clipe(id: 2, nome: "B", caminhoVideo: "/b.mp4", duracaoSegundos: 10,
              transportType: "Denon DJ"),
        clipe(id: 3, nome: "C", caminhoVideo: "/c.mp4", duracaoSegundos: 10,
              transportType: "Pioneer DJ"),
    ])], bpm: 120)
    let slots = TimelineCalculator.slots(from: c)
    #expect(slots.map(\.relogio) == [.batidas, .mesa, .mesa])
    let resultado = TimelineCalculator.linha(slots)
    #expect(resultado.blocos.isEmpty)
    #expect(resultado.totalMS == 0)
    #expect(resultado.semTempo == ["1.1", "1.2", "1.3"])
    // O tempo bruto continua legivel -- nao apagamos o numero, so recusamos a soma.
    #expect(slots.map(\.durationMS) == [10_000, 10_000, 10_000])
}

@Test("piloto ligado reassume o relogio mesmo em clipe SMPTE")
func pilotoReassumeRelogio() throws {
    // Regua do trilho: com `duration_type` em Seconds/Beats quem segura a tela e o
    // relogio wall-clock do proprio Arena, nao o timecode externo -- ai a conta
    // volta a ser nossa. `instavel:` -- e a medicao que derruba isso e barata: ele
    // ligar o piloto duma camada com clipe em SMPTE e me mandar o GET /composition.
    // Se num set sincronizado o piloto tambem segue o
    // LTC, a inversao e uma linha em `effectiveMS` -- este teste trava a escolha.
    let slot = try #require(TimelineCalculator.slots(from: composicao([
        camada([clipe(nome: "Hino", caminhoVideo: "/h.mp4", duracaoSegundos: 90,
                    transportType: "SMPTE 1", piloto: "Play Next Clip",
                    tipoDuracaoPiloto: "Seconds", segundosPiloto: 12)],
              piloto: "Play Next Clip", tipoDuracao: "Seconds")]))).first
    #expect(slot?.relogio == .smpte1)
    #expect(slot?.durationSource == .piloto)
    #expect(slot?.effectiveMS == 12_000)
}

@Test("linha mista conta o que e nosso e lista o resto por endereco")
func linhaMistaFalaOLadoDeFora() throws {
    // O caso real de um evento: bloco em cronometria, um step em BPM e um no
    // timecode. O total precisa dizer "isso e o que podemos prometer" sem somar o
    // resto escondido.
    let c = composicao([camada([
        clipe(id: 1, nome: "Vinheta", caminhoVideo: "/v.mp4", duracaoSegundos: 8,
              piloto: "Play Next Clip"),
        clipe(id: 2, nome: "Trilha", caminhoAudio: "/t.wav", duracaoSegundos: 60,
              transportType: "BPM Sync", piloto: "Play Next Clip"),
        clipe(id: 3, nome: "Contagem", caminhoVideo: "/c.mp4", duracaoSegundos: 10,
              transportType: "SMPTE 2", piloto: "Do nothing"),
    ], piloto: "Play Next Clip")], bpm: 128)
    let resultado = TimelineCalculator.linha(TimelineCalculator.slots(from: c))
    // O rolo do piloto continua sendo UM bloco (Merge), mas so o que e nosso soma.
    #expect(resultado.blocos.count == 1)
    #expect(resultado.blocos.first?.enderecos == ["1.1", "1.2"])
    #expect(resultado.blocos.first?.semDuracao == ["1.2"])
    #expect(resultado.blocos.first?.totalMS == 8_000)
    #expect(resultado.totalMS == 8_000)
    #expect(resultado.semTempo == ["1.3"])
}
