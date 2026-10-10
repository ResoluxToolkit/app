import Foundation
import Testing
import Resolume
@testable import ResoluxServer

@Suite("MotorChat")
struct MotorChatTests {

    @Test("sessão v1 aceita backend spike e recusa valor fora do domínio")
    func backendSpikeNoDominio() throws {
        let aceito = try SessaoV1Regras.aplicar(
            ["backend": .string("spike")],
            em: SessaoV1())
        #expect(aceito.backend == "spike")

        #expect(throws: RecusaSessao.valorInvalido(campo: "backend", valor: "chatgpt")) {
            _ = try SessaoV1Regras.aplicar(
                ["backend": .string("chatgpt")],
                em: SessaoV1())
        }
    }

    @Test("backend spike lê token do account.json e monta endpoint chat/completions")
    func resolverSpike() async throws {
        let pasta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resolux-motor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let caminho = pasta.appendingPathComponent("account.json").path
        let conta = #"{"username":"teste","baseUrl":"https://spike.example","token":"tok-secreto"}"#
        try Data(conta.utf8).write(to: URL(fileURLWithPath: caminho))
        defer { try? FileManager.default.removeItem(at: pasta) }

        let motor = MotorChat(caminhoAccount: caminho)
        let config = try await motor.resolverConfig(backend: "spike", model: "")
        #expect(config.endpoint.absoluteString == "https://spike.example/v1/chat/completions")
        #expect(config.apiKey == "tok-secreto")
        #expect(config.model == "Spike")

        let comModelo = try await motor.resolverConfig(backend: "spike", model: "Outro")
        #expect(comModelo.model == "Outro")

        let semToken = MotorChat(
            caminhoAccount: pasta.appendingPathComponent("inexistente.json").path)
        do {
            _ = try await semToken.resolverConfig(backend: "spike", model: "")
            Issue.record("deveria lançar tokenAusente")
        } catch let falha as MotorChat.Falha {
            guard case .tokenAusente = falha else {
                Issue.record("falha inesperada: \(falha)")
                return
            }
        }
    }

    @Test("turno do MotorChat roda tool call via MCP e devolve resposta final")
    func turnoCompleto() async throws {
        let mcp = MCPClient(transport: FakeMCPServer())
        try await mcp.connect()
        let backend = ScriptedChatTransport(script: [
            ScriptedChatTransport.toolCallResponse(
                id: "call_1", name: "status", arguments: #"{"action":"get"}"#),
            ScriptedChatTransport.textResponse("Arena rodando."),
        ])
        let config = ChatEngine.Config(apiKey: "test", model: "fake-model")
        let motor = MotorChat(transporte: backend, configFixa: config, mcp: mcp)

        let resposta = try await motor.responder(
            "Como tá o Arena?",
            sessao: SessaoV1(backend: "spike", model: "fake"))
        #expect(resposta == "Arena rodando.")

        // toolsAllowed reflete o que o servidor MCP anunciou.
        let total = await motor.totalFerramentas()
        #expect(total == 2)
        let lista = await motor.listaFerramentas()
        #expect(lista.first?["name"] == "status")
        #expect(lista.first?["description"] == "Arena status")
    }

    @Test("ferramentas vazias mantêm GET /tools honesto")
    func listaFerramentasVazia() async {
        let motor = MotorChat()
        let lista = await motor.listaFerramentas()
        let total = await motor.totalFerramentas()
        #expect(lista.isEmpty)
        #expect(total == 0)
    }
}
