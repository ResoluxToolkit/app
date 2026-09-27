import Darwin
import Foundation
import Testing
@testable import Resolume

/// Loop homem<->bot de ponta a ponta, sem fake nenhum: modelo local da Apple
/// (`fm serve`, :1976) falando com o binário MCP do Arena aberto. É a prova de
/// que a interação funciona antes de commitar qualquer coisa.
///
/// Roda em `readOnly`: se o modelo tentar escrever no set, o gate bloqueia e o
/// teste continua — assim este arquivo nunca mexe num set em uso.
///
/// `.enabled(if:)` exige valor síncrono, então a sonda é um `connect` TCP de
/// verdade: em localhost a recusa chega na mesma hora, sem precisar de await.
private func portIsListening(_ port: UInt16) -> Bool {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = (0x7F00_0001 as UInt32).bigEndian
    let connected = withUnsafePointerTo(&address) { pointer in
        Darwin.connect(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
    return connected == 0
}

/// `sockaddr_in` e `sockaddr` têm layouts compatíveis no prefixo; o rebind é o
/// jeito seguro de passar o endereço sem copiar para um variável do tipo errado.
private func withUnsafePointerTo(
    _ value: inout sockaddr_in,
    _ body: (UnsafePointer<sockaddr>) -> Int32
) -> Int32 {
    withUnsafePointer(to: &value) { raw in
        raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0) }
    }
}

/// Opt-in: `RESOLUX_FM_LIVE=1 swift test ... --filter LiveLoop`.
///
/// Não é bug nosso: o `fm serve` da Apple tem janela de contexto curta e recusa
/// o conjunto inteiro de ferramentas do Arena. Medido com `tools/list` real e
/// schema já normalizado, custo de prompt por ferramenta (tokens):
/// diagnose 343, status 346, transport 413, crossfader 429, file 453,
/// color_code 552, deck 553, catalog 617, technique 636, transition 693,
/// style 739, group 703, autopilot 740, column 751, composition 836, batch 884,
/// transform 911, monitor 984, layer 1075, effect 1095, parameter 1580, clip 2098
/// -- somando ~17,4k. O teto está entre 2,3k (10 ferramentas, HTTP 200) e 3,1k
/// (12 ferramentas, HTTP 500). Descrição curta não ajuda: cortada a 0, continua
/// 500 -- quem come a janela é o JSON Schema, não o texto.
/// Por isso o loop vivo de referência roda pelo Ollama, abaixo.
@Test("pergunta sobre o set chega ao Arena pela via de texto do fm",
      .enabled(if: ProcessInfo.processInfo.environment["RESOLUX_FM_LIVE"] != nil
                 && ResolumeProduct.arena.isResponsive() && portIsListening(1976)),
      .timeLimit(.minutes(4)))
func liveQuestionReachesArena() async throws {
    let transport = ProcessMCPTransport(
        executableURL: URL(fileURLWithPath: ResolumeProduct.arena.mcpExecutablePath),
        responseTimeout: 15)
    let mcp = MCPClient(transport: transport)
    try await mcp.connect()
    defer { Task { await mcp.disconnect() } }

    let engine = ChatEngine(
        config: .init(
            baseURL: URL(string: "http://127.0.0.1:1976/v1")!,
            apiKey: "local",
            model: "system"),
        mcp: mcp,
        policy: .readOnly)

    let question = "Quantas camadas tem a composicao agora?"
    print("OPERADOR:", question)
    let answer = try await engine.send(question)
    print("BOT:", answer)

    // Prova de que a ferramenta rodou: precisa haver mensagem de ferramenta no
    // histórico. Sem isso o modelo só chutou um número -- exatamente o bug que o
    // resgate veio fechar.
    let usedTool = await engine.transcript.contains { $0.role == "tool" }
    #expect(usedTool, "o modelo respondeu sem consultar o Arena")
    #expect(!answer.isEmpty)
}

/// Mesmo loop pelo Ollama (:11434). Escolhido porque é o backend local que
/// realmente dirige as 22 ferramentas: o `fm` da Apple tem janela curta e
/// recusa o conjunto inteiro (medido: HTTP 500 acima de ~3k tokens de prompt,
/// e as 22 ferramentas custam ~17,4k). O `qwen3:1.7b` devolve `tool_calls` no
/// campo nativo, então este teste também cobre o caminho feliz sem resgate.
@Test("loop completo pelo Ollama usa ferramenta MCP do Arena",
      .enabled(if: ResolumeProduct.arena.isResponsive() && portIsListening(11434)),
      .timeLimit(.minutes(5)))
func liveLoopThroughOllama() async throws {
    let transport = ProcessMCPTransport(
        executableURL: URL(fileURLWithPath: ResolumeProduct.arena.mcpExecutablePath),
        responseTimeout: 15)
    let mcp = MCPClient(transport: transport)
    try await mcp.connect()
    defer { Task { await mcp.disconnect() } }

    let engine = ChatEngine(
        config: .init(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            apiKey: "local",
            model: "qwen3:1.7b"),
        mcp: mcp,
        policy: .readOnly)

    let question = "Quantas camadas tem a composicao agora?"
    print("OPERADOR:", question)
    let answer = try await engine.send(question)
    print("BOT:", answer)

    let usedTool = await engine.transcript.contains { $0.role == "tool" }
    #expect(usedTool, "o modelo respondeu sem consultar o Arena")
    #expect(!answer.isEmpty)
}
