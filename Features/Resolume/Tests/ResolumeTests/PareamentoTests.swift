import Foundation
import Testing
import Resolume
@testable import ResoluxServer

@Suite("Pareamento do celular")
struct PareamentoTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("código nasce estável, expira em 5 min e gira depois")
    func codigoRotativo() async {
        let pareamento = Pareamento(duracaoCodigo: 300)
        let primeiro = await pareamento.codigo(agora: t0)
        #expect(primeiro.expiraEm == 1_700_000_300)
        #expect(primeiro.valor.count == 22)
        #expect(!primeiro.valor.contains("="))
        #expect(!primeiro.valor.contains("+"))
        #expect(!primeiro.valor.contains("/"))

        let mesmo = await pareamento.codigo(agora: t0.addingTimeInterval(299))
        #expect(mesmo == primeiro)

        let novo = await pareamento.codigo(agora: t0.addingTimeInterval(300))
        #expect(novo.valor != primeiro.valor)
        #expect(novo.expiraEm == 1_700_000_600)
    }

    @Test("parear consome o código e entrega token válido")
    func parearEntregaToken() async throws {
        let pareamento = Pareamento()
        let codigo = await pareamento.codigo(agora: t0)
        let token = try await pareamento.parear(
            codigo: codigo.valor,
            cliente: "192.168.0.50",
            agora: t0)

        #expect(token.count == 43)
        #expect(await pareamento.tokenValido(token))
        #expect(await !pareamento.tokenValido(nil))
        #expect(await !pareamento.tokenValido(""))
        #expect(await !pareamento.tokenValido("outro-token"))

        await #expect(throws: Pareamento.Falha.invalido) {
            _ = try await pareamento.parear(
                codigo: codigo.valor,
                cliente: "192.168.0.50",
                agora: t0)
        }

        let proximo = await pareamento.codigo(agora: t0)
        #expect(proximo.valor != codigo.valor)
    }

    @Test("código vencido não pareia e conta como falha")
    func codigoVencido() async {
        let pareamento = Pareamento(duracaoCodigo: 10)
        let codigo = await pareamento.codigo(agora: t0)

        await #expect(throws: Pareamento.Falha.invalido) {
            _ = try await pareamento.parear(
                codigo: codigo.valor,
                cliente: "192.168.0.50",
                agora: t0.addingTimeInterval(11))
        }
    }

    @Test("limite de tentativas erradas por cliente")
    func limiteTentativas() async throws {
        let pareamento = Pareamento(maximoFalhas: 2, janelaFalhas: 60)
        let codigo = await pareamento.codigo(agora: t0)

        for _ in 0..<2 {
            await #expect(throws: Pareamento.Falha.invalido) {
                _ = try await pareamento.parear(
                    codigo: "errado",
                    cliente: "192.168.0.50",
                    agora: t0)
            }
        }

        await #expect(throws: Pareamento.Falha.excessoTentativas) {
            _ = try await pareamento.parear(
                codigo: codigo.valor,
                cliente: "192.168.0.50",
                agora: t0)
        }

        // Outro cliente não herda o bloqueio.
        _ = try await pareamento.parear(
            codigo: codigo.valor,
            cliente: "192.168.0.51",
            agora: t0)

        // Passada a janela, o cliente volta a poder tentar.
        let novo = await pareamento.codigo(agora: t0.addingTimeInterval(61))
        await #expect(throws: Pareamento.Falha.invalido) {
            _ = try await pareamento.parear(
                codigo: novo.valor + "x",
                cliente: "192.168.0.50",
                agora: t0.addingTimeInterval(61))
        }
    }

    @Test("revogar invalida o token do aparelho")
    func revogarToken() async throws {
        let pareamento = Pareamento()
        let codigo = await pareamento.codigo(agora: t0)
        let token = try await pareamento.parear(
            codigo: codigo.valor,
            cliente: "192.168.0.50",
            agora: t0)
        #expect(await pareamento.tokenValido(token))

        await pareamento.revogar(token)
        #expect(await !pareamento.tokenValido(token))
    }

    @Test("comparação de código em tempo constante")
    func comparacaoConstante() {
        #expect(Pareamento.iguaisEmTempoConstante("abc", "abc"))
        #expect(Pareamento.iguaisEmTempoConstante("", ""))
        #expect(!Pareamento.iguaisEmTempoConstante("abc", "abd"))
        #expect(!Pareamento.iguaisEmTempoConstante("abc", "ab"))
        #expect(!Pareamento.iguaisEmTempoConstante("", "a"))
    }

    @Test("endereço local e X-Forwarded-For só valem no peer loopback")
    func acessoLocal() {
        #expect(AcessoDaemon.normalizar("::ffff:192.168.0.10") == "192.168.0.10")
        #expect(AcessoDaemon.normalizar("[::1]") == "::1")
        #expect(AcessoDaemon.normalizar("fe80::1%en0") == "fe80::1")
        #expect(AcessoDaemon.normalizar("LOCALHOST") == "localhost")

        #expect(AcessoDaemon.ehLoopback("127.0.0.1"))
        #expect(AcessoDaemon.ehLoopback("127.8.9.10"))
        #expect(AcessoDaemon.ehLoopback("::1"))
        #expect(AcessoDaemon.ehLoopback("localhost"))
        #expect(!AcessoDaemon.ehLoopback("192.168.0.10"))
        #expect(!AcessoDaemon.ehLoopback("8.8.8.8"))

        #expect(AcessoDaemon.clienteReal(
            peer: "127.0.0.1",
            encaminhado: " 8.8.8.8, 10.0.0.1 ") == "8.8.8.8")
        #expect(AcessoDaemon.clienteReal(
            peer: "192.168.0.20",
            encaminhado: "1.2.3.4") == "192.168.0.20")
        #expect(AcessoDaemon.ehLocal("192.168.0.10", locais: ["192.168.0.10"]))
        #expect(!AcessoDaemon.ehLocal("8.8.8.8", locais: ["192.168.0.10"]))
    }

    @Test("host do painel vira base de rede no QR")
    func baseDeRede() {
        #expect(AcessoDaemon.decomporHost("localhost:3003").nome == "localhost")
        #expect(AcessoDaemon.decomporHost("localhost:3003").porta == "3003")
        #expect(AcessoDaemon.decomporHost("[::1]:1980").nome == "::1")
        #expect(AcessoDaemon.decomporHost("mac.local").porta == nil)

        #expect(AcessoDaemon.baseDeRede(
            host: "localhost:3003",
            locais: ["192.168.0.10"]) == "http://192.168.0.10:3003")
        #expect(AcessoDaemon.baseDeRede(
            host: "192.168.0.10:1980",
            locais: []) == "http://192.168.0.10:1980")
        #expect(AcessoDaemon.baseDeRede(host: nil, locais: []) == nil)
    }

    @Test("token sai do header Bearer ou da query")
    func tokenDoPedido() {
        let header = PedidoHttp(
            metodo: "GET",
            caminho: "/api/v1/session",
            cabecalhos: ["authorization": "Bearer abc-_9"],
            corpo: Data())
        #expect(AcessoDaemon.tokenDoPedido(header) == "abc-_9")

        let query = PedidoHttp(
            metodo: "GET",
            caminho: "/api/v1/ws?token=abc-_9",
            cabecalhos: [:],
            corpo: Data())
        #expect(AcessoDaemon.tokenDoPedido(query) == "abc-_9")

        let semToken = PedidoHttp(
            metodo: "GET",
            caminho: "/api/v1/health",
            cabecalhos: [:],
            corpo: Data())
        #expect(AcessoDaemon.tokenDoPedido(semToken) == nil)
    }

    @Test("rotas públicas e privadas do daemon")
    func exigenciaDeToken() {
        #expect(!AcessoDaemon.exigeToken(pedido("GET", "/api/v1/health")))
        #expect(!AcessoDaemon.exigeToken(pedido("GET", "/")))
        #expect(!AcessoDaemon.exigeToken(pedido("GET", "/assets/app.js")))
        #expect(!AcessoDaemon.exigeToken(pedido("GET", "/manifest.webmanifest")))
        #expect(AcessoDaemon.exigeToken(pedido("GET", "/api/v1/session")))
        #expect(AcessoDaemon.exigeToken(pedido("GET", "/monitor")))
        #expect(AcessoDaemon.exigeToken(pedido("POST", "/monitor/processes/1/terminate")))
    }

    @Test("GET /pareamento só responde no Mac e devolve código")
    func getPareamento() async throws {
        let pareamento = Pareamento()
        let local = pedido("GET", "/api/v1/pareamento", cabecalhos: ["host": "localhost:3003"])
        let resposta = await ResoluxServerMain.responderPareamento(
            local,
            pareamento: pareamento,
            local: true,
            cliente: "127.0.0.1")
        #expect(resposta.status == 200)

        let corpo = try JSONDecoder().decode([String: MCPValue].self, from: resposta.corpo)
        let codigo = try #require(corpo["codigo"]?.stringValue)
        #expect(!codigo.isEmpty)
        #expect(corpo["expiraEm"]?.intValue != nil)

        let remoto = pedido("GET", "/api/v1/pareamento")
        let recusado = await ResoluxServerMain.responderPareamento(
            remoto,
            pareamento: pareamento,
            local: false,
            cliente: "8.8.8.8")
        #expect(recusado.status == 403)
    }

    @Test("POST /pareamento troca código por token e recusa repetição")
    func postPareamento() async throws {
        let pareamento = Pareamento()
        let codigo = await pareamento.codigo()

        let valido = pedido(
            "POST",
            "/api/v1/pareamento",
            corpo: Data(#"{"codigo":"\#(codigo.valor)"}"#.utf8))
        let resposta = await ResoluxServerMain.responderPareamento(
            valido,
            pareamento: pareamento,
            local: false,
            cliente: "192.168.0.50")
        #expect(resposta.status == 200)

        let corpo = try JSONDecoder().decode([String: MCPValue].self, from: resposta.corpo)
        let token = try #require(corpo["token"]?.stringValue)
        #expect(await pareamento.tokenValido(token))

        let repetido = await ResoluxServerMain.responderPareamento(
            valido,
            pareamento: pareamento,
            local: false,
            cliente: "192.168.0.50")
        #expect(repetido.status == 401)

        let invalido = pedido(
            "POST",
            "/api/v1/pareamento",
            corpo: Data(#"{"codigo":"errado"}"#.utf8))
        let recusado = await ResoluxServerMain.responderPareamento(
            invalido,
            pareamento: pareamento,
            local: false,
            cliente: "192.168.0.51")
        #expect(recusado.status == 401)

        let corpoRuim = pedido(
            "POST",
            "/api/v1/pareamento",
            corpo: Data(#"{"codigo":1}"#.utf8))
        let ruim = await ResoluxServerMain.responderPareamento(
            corpoRuim,
            pareamento: pareamento,
            local: false,
            cliente: "192.168.0.52")
        #expect(ruim.status == 400)

        let metodo = pedido("PUT", "/api/v1/pareamento")
        let naoPermitido = await ResoluxServerMain.responderPareamento(
            metodo,
            pareamento: pareamento,
            local: true,
            cliente: "127.0.0.1")
        #expect(naoPermitido.status == 405)
    }
}

private func pedido(
    _ metodo: String,
    _ caminho: String,
    corpo: Data = Data(),
    cabecalhos: [String: String] = [:]) -> PedidoHttp {
    PedidoHttp(metodo: metodo, caminho: caminho, cabecalhos: cabecalhos, corpo: corpo)
}
