import Foundation
import Testing
import Resolume
@testable import ResoluxServer

@Suite("ResoluxServer")
struct ResoluxServerTests {
    @Test("handshake WebSocket usa o accept canônico do RFC 6455")
    func handshakeWs() {
        #expect(WsHandshake.aceitar(chave: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test("origem do WS aceita loopback, LAN privada e nome de máquina")
    func origemWs() {
        #expect(ResoluxServerMain.origemAceita(nil))
        #expect(ResoluxServerMain.origemAceita("null"))
        #expect(ResoluxServerMain.origemAceita("http://localhost:3003"))
        #expect(ResoluxServerMain.origemAceita("http://127.0.0.1:3003"))
        #expect(ResoluxServerMain.origemAceita("http://mac:3003"))
        #expect(ResoluxServerMain.origemAceita("http://mac.local:3003"))
        #expect(ResoluxServerMain.origemAceita("http://192.168.0.109:3003"))
        #expect(ResoluxServerMain.origemAceita("http://10.0.0.5:3003"))
        #expect(ResoluxServerMain.origemAceita("http://172.16.9.9:3003"))
        #expect(ResoluxServerMain.origemAceita("http://100.115.91.93:3003"))

        #expect(!ResoluxServerMain.origemAceita("http://evil.com:3003"))
        #expect(!ResoluxServerMain.origemAceita("http://8.8.8.8:3003"))
        #expect(!ResoluxServerMain.origemAceita("http://172.32.0.1:3003"))
        #expect(!ResoluxServerMain.origemAceita("http://100.200.0.1:3003"))
        #expect(!ResoluxServerMain.origemAceita("sem-host"))
    }

    @Test("decodificador WS lê frame mascarado canônico")
    func frameMascarado() {
        var decodificador = WsDecodificador()
        var frame = Data([0x81, 0x05])
        frame.append(Data("Hello".utf8))
        let mensagens = decodificador.alimentar(frame)
        #expect(mensagens.count == 1)
        #expect(mensagens[0].opcode == 1)
        #expect(String(decoding: mensagens[0].payload, as: UTF8.self) == "Hello")
    }

    @Test("decodificador WS junta fragmentos de texto")
    func frameFragmentado() {
        var decodificador = WsDecodificador()
        var entrada = Data()
        entrada.append(Data([0x01, 0x03]))
        entrada.append(Data("par".utf8))
        entrada.append(Data([0x80, 0x02]))
        entrada.append(Data("te".utf8))
        let mensagens = decodificador.alimentar(entrada)
        #expect(mensagens.count == 1)
        #expect(String(decoding: mensagens[0].payload, as: UTF8.self) == "parte")
    }

    @Test("PATCH /session aceita, recusa campo desconhecido e aceita null")
    func patchSessao() throws {
        var sessao = SessaoV1()
        sessao = try SessaoV1Regras.aplicar(
            [
                "mode": .string("performance"),
                "backend": .string("applefm"),
                "model": .string("modelo"),
            ],
            em: sessao)
        #expect(sessao.mode == "performance")
        #expect(sessao.backend == "applefm")
        #expect(sessao.model == "modelo")

        #expect(throws: RecusaSessao.campoDesconhecido("journalEnabled")) {
            _ = try SessaoV1Regras.aplicar(
                ["journalEnabled": .bool(true)],
                em: SessaoV1())
        }

        let comLista = try SessaoV1Regras.aplicar(
            ["toolAllowlist": .array([.string("composition.get")])],
            em: SessaoV1())
        #expect(comLista.toolAllowlist == ["composition.get"])

        let limpo = try SessaoV1Regras.aplicar(
            ["toolAllowlist": .null],
            em: comLista)
        #expect(limpo.toolAllowlist == nil)
    }

    @Test("monitor muda só quando o corpo muda e avisa a falha na transição")
    func monitorHub() async throws {
        let fases: [String] = [
            "{\"a\":1}",
            "{\"a\":1}",
            "{\"a\":2}",
            "{\"a\":3}",
        ]
        let provedor = ProvedorContador(fases: fases)
        let hub = MonitorHub(
            provedor: {
                try await provedor.proximo()
            },
            intervalo: 0.01)
        let eventos = EventoColetor()
        let assinatura = await hub.assinar { evento in
            await eventos.registrar(evento)
        }
        try await Task.sleep(nanoseconds: 120_000_000)
        await hub.cancelar(assinatura)
        let coletados = await eventos.snapshot()
        #expect(coletados.contains(.update(Data(#"{"a":1}"#.utf8))))
        #expect(coletados.contains(.update(Data(#"{"a":2}"#.utf8))))
        #expect(coletados.contains(.update(Data(#"{"a":3}"#.utf8))))
        #expect(coletados.contains(.erro(codigo: "arena_unavailable", mensagem: "Arena REST unavailable")))
    }
}

private actor ProvedorContador {
    private let fases: [String]
    private var contador = 0

    init(fases: [String]) {
        self.fases = fases
    }

    func proximo() throws -> Data {
        defer { contador += 1 }
        if contador == 2 {
            throw ArenaGateway.Falha.indisponivel
        }
        return Data(fases[contador % fases.count].utf8)
    }
}

private actor EventoColetor {
    private var eventos: [ResoluxServer.MonitorHub.Evento] = []

    func registrar(_ evento: ResoluxServer.MonitorHub.Evento) {
        eventos.append(evento)
    }

    func snapshot() -> [ResoluxServer.MonitorHub.Evento] {
        eventos
    }
}
