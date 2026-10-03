import Foundation
import Testing
@testable import Resolume

/// Cada teste ganha pasta propria. O diario e append no disco, entao compartilhar
/// diretoria deixaria um teste lendo as linhas do outro e o resultado mentiria.
private func diarioTemporario(sessionID: String = "teste") -> (WriteJournal, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resolux-journal-" + UUID().uuidString)
    return (WriteJournal(directory: root, sessionID: sessionID), root)
}

/// Motor com backend de roteiro: primeira resposta e uma chamada de ferramenta,
/// segunda e a resposta final. `FakeMCPServer` aceita qualquer tools/call e devolve
/// "ok de <tool>", entao a pre-leitura do valor antigo tambem responde -- o que
/// deixa visivel se ela saiu ou nao.
private func motor(
    script: [String],
    policy: ToolPolicy,
    journal: WriteJournal?
) async throws -> (ChatEngine, FakeMCPServer) {
    let server = FakeMCPServer()
    let mcp = MCPClient(transport: server)
    try await mcp.connect()
    let engine = ChatEngine(
        config: .init(apiKey: "test", model: "fake-model"),
        transport: ScriptedChatTransport(script: script),
        mcp: mcp,
        policy: policy,
        journal: journal)
    return (engine, server)
}

/// Somente as chamadas de ferramenta, na ordem em que chegaram ao servidor.
///
/// O `JSONEncoder` da Foundation escapa a barra (`"tools\/call"`), entao comparar
/// texto cru com `tools/call` nunca casa e o filtro devolve vazio -- o que faria um
/// teste de "nao registrou" passar por acidente em vez de por motivo. Normalizamos
/// a barra antes de olhar.
private func chamadasDeFerramenta(_ server: FakeMCPServer) async -> [String] {
    await server.receivedLines
        .map { $0.replacingOccurrences(of: "\\/", with: "/") }
        .filter { $0.contains("tools/call") }
}

@Test("escrita permitida registra linha com o valor anterior capturado")
func escritaPermitidaRegistraComAnterior() async throws {
    let (journal, root) = diarioTemporario()
    defer { try? FileManager.default.removeItem(at: root) }
    let (engine, server) = try await motor(
        script: [
            ScriptedChatTransport.toolCallResponse(
                id: "c1", name: "parameter",
                arguments: #"{"action":"set","path":"/layers/1/volume","value":0.5}"#),
            ScriptedChatTransport.textResponse("Volume ajustado."),
        ],
        policy: .readWrite,
        journal: journal)
    let resposta = try await engine.send("sobe o volume da camada 1")
    #expect(resposta == "Volume ajustado.")

    let linhas = WriteJournal.entries(at: journal.url)
    #expect(linhas.count == 1)
    let registro = try #require(linhas.first)
    #expect(registro.tool == "parameter")
    #expect(registro.action == "set")
    #expect(registro.isError == false)
    #expect(registro.session == "teste")
    // O anterior so vem preenchido porque a leitura espelhada rodou antes.
    #expect(registro.previous != nil)

    // Prova da ordem: um get do parameter ANTES do set, e nada alem disso.
    // #require em vez de indice direto: sem isso um array vazio daría panic e
    // derrubaria a suíte toda, escondendo os outros resultados.
    let enviadas = await chamadasDeFerramenta(server)
    #expect(enviadas.count == 2)
    let primeira = try #require(enviadas.first)
    let segunda = try #require(enviadas.last)
    #expect(primeira.contains("get"))
    #expect(segunda.contains(#""action":"set""#))
}

@Test("recusa de politica nao escreve no Arena nem no diario")
func recusaNaoRegistra() async throws {
    let (journal, root) = diarioTemporario()
    defer { try? FileManager.default.removeItem(at: root) }
    let (engine, server) = try await motor(
        script: [
            ScriptedChatTransport.toolCallResponse(
                id: "c1", name: "parameter",
                arguments: #"{"action":"set","path":"/layers/1/volume","value":0.9}"#),
            ScriptedChatTransport.textResponse("Bloqueado."),
        ],
        policy: .readOnly,
        journal: journal)
    _ = try await engine.send("sobe o volume")

    #expect(WriteJournal.entries(at: journal.url).isEmpty)
    #expect(await chamadasDeFerramenta(server).isEmpty)
}

@Test("leitura simples roda no Arena mas nao entra no diario")
func leituraNaoRegistra() async throws {
    let (journal, root) = diarioTemporario()
    defer { try? FileManager.default.removeItem(at: root) }
    let (engine, server) = try await motor(
        script: [
            ScriptedChatTransport.toolCallResponse(
                id: "c1", name: "layer", arguments: #"{"action":"get","index":0}"#),
            ScriptedChatTransport.textResponse("Tem camadas."),
        ],
        policy: .readWrite,
        journal: journal)
    _ = try await engine.send("quais camadas existem?")

    #expect(WriteJournal.entries(at: journal.url).isEmpty)
    // Uma chamada so: a pre-leitura nao pode ter acontecido em cima de leitura.
    let enviadas = await chamadasDeFerramenta(server)
    #expect(enviadas.count == 1)
    let unica = try #require(enviadas.first)
    #expect(unica.contains("layer"))
}

@Test("leitura espelhada so existe em parameter")
func leituraEspelhadaSoEmParameter() {
    // Ferramenta errada ou leitura pura: nenhuma pre-leitura inventada.
    #expect(WriteJournal.mirroredRead(tool: "transport", arguments: ["action": .string("set")]) == nil)
    #expect(WriteJournal.mirroredRead(tool: "layer", arguments: ["action": .string("set")]) == nil)
    #expect(WriteJournal.mirroredRead(tool: "parameter", arguments: ["action": .string("get")]) == nil)

    let simples = WriteJournal.mirroredRead(
        tool: "parameter", arguments: ["action": .string("set"), "path": .string("/x")])
    #expect(simples?["action"]?.stringValue == "get")
    #expect(simples?["path"]?.stringValue == "/x")

    let animacao = WriteJournal.mirroredRead(
        tool: "parameter", arguments: ["action": .string("set_animation")])
    #expect(animacao?["action"]?.stringValue == "get_animation")
}

@Test("resultado grande e cortado em 200 caracteres")
func cortarResultado() {
    #expect(WriteJournal.cap("  oi \n") == "oi")
    let exato = String(repeating: "x", count: WriteJournal.resultLimit)
    #expect(WriteJournal.cap(exato) == exato)
    let cortado = WriteJournal.cap(String(repeating: "x", count: 500))
    #expect(cortado.count == WriteJournal.resultLimit + 1)
    #expect(cortado.hasSuffix("…"))
}

@Test("diario devolve do mais recente pro mais antigo")
func ordemMaisRecentePrimeiro() async throws {
    let (journal, root) = diarioTemporario(sessionID: "ordem")
    defer { try? FileManager.default.removeItem(at: root) }
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    try await journal.record(
        tool: "parameter", arguments: ["action": .string("set")],
        result: "primeiro", isError: false, previous: nil, now: base)
    try await journal.record(
        tool: "parameter", arguments: ["action": .string("set")],
        result: "segundo", isError: false, previous: "valor antigo",
        now: base.addingTimeInterval(1))

    let linhas = WriteJournal.entries(at: journal.url)
    #expect(linhas.map(\.result) == ["segundo", "primeiro"])
    #expect(linhas.map(\.previous) == ["valor antigo", nil])
    #expect(linhas.allSatisfy { $0.session == "ordem" })
}

@Test("linha ilegivel e pulada sem derrubar o resto da leitura")
func linhaIlegivelEhPulada() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resolux-journal-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let arquivo = root.appendingPathComponent("corrompido.jsonl")
    func linha(_ resultado: String) -> String {
        #"{"timestamp":1790489600,"session":"corrompido","tool":"parameter","action":"set","arguments":{},"isError":false,"result":"\#(resultado)"}"#
    }
    // Meio arquivo ainda conta mais que arquivo nenhum: o meio corrompido nao
    // pode apagar o que veio antes e depois dele.
    let conteudo = [linha("antes"), "--isto-nao-e-json--", linha("depois")].joined(separator: "\n") + "\n"
    try conteudo.write(to: arquivo, atomically: true, encoding: .utf8)
    #expect(WriteJournal.entries(at: arquivo).map(\.result) == ["depois", "antes"])
}


@Test("timestamp do diario e epoch segundos, nunca string de data")
func timestampEEpochSegundos() async throws {
    // Voto dele (checkpoint 7): "Sempre que envolver Data/Hora." epoch segundos,
    // sem fuso, sem locale. A apresentacao e que calcula o relogio humano depois.
    let (journal, root) = diarioTemporario(sessionID: "epoch")
    defer { try? FileManager.default.removeItem(at: root) }
    let instante = Date(timeIntervalSince1970: 1_800_000_000.9)
    try await journal.record(
        tool: "parameter", arguments: ["action": .string("set")],
        result: "gravado", isError: false, previous: nil, now: instante)

    let linha = try #require(WriteJournal.entries(at: journal.url).first)
    #expect(linha.timestamp == 1_800_000_000)

    // O cruento na disk tem que ser numero cru, nao string com fuso.
    let cru = try String(contentsOf: journal.url, encoding: .utf8)
    #expect(cru.contains("\"timestamp\":1800000000"))
    #expect(!cru.contains("Z\""))
}

@Test("duas linhas no mesmo segundo continuam distinguiveis pela ordem")
func mesmoSegundoNaoPerdeOrdem() async throws {
    // Medido na ferramenta de log dele: linhas inteiras no MESMO milissegundo.
    // Relogio nenhum desempata isso; a posicao no arquivo (append) e quem manda,
    // e a leitura inverte. Epoch em segundos so torna o empate mais frequente --
    // por isso a ordem jamais pode vir do timestamp.
    let (journal, root) = diarioTemporario(sessionID: "empate")
    defer { try? FileManager.default.removeItem(at: root) }
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    for rotulo in ["um", "dois", "tres"] {
        try await journal.record(
            tool: "parameter", arguments: ["action": .string("set")],
            result: rotulo, isError: false, previous: nil, now: t)
    }
    let linhas = WriteJournal.entries(at: journal.url)
    #expect(linhas.map(\.result) == ["tres", "dois", "um"])
    #expect(Set(linhas.map(\.timestamp)).count == 1)
}

@Test("nome da sessao comeca em epoch segundos")
func sessaoUsaEpochNoNome() {
    // Arquivo nomeado por data/hora local seria ambiguo lido depois; epoch nao.
    let id = WriteJournal.makeSessionID(now: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(id.hasPrefix("1800000000-"))
}
