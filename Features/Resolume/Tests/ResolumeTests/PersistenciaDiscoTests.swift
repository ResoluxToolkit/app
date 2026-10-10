import Foundation
import Testing
@testable import ResoluxServer

@Suite("PersistenciaDisco")
struct PersistenciaDiscoTests {
    private func pastaTemporaria() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolux-teste-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("preparar cria a pasta e volta sem sessão em disco vazio")
    func pastaVazia() async throws {
        let raiz = pastaTemporaria()
        let disco = PersistenciaDisco(raiz: raiz)
        let restaurada = try await disco.preparar()
        #expect(restaurada == nil)
        #expect(
            FileManager.default.fileExists(
                atPath: raiz.appendingPathComponent("conversas").path))
    }

    @Test("turnos registram, sobrevivem a novo boot e limpam")
    func cicloConversa() async throws {
        let raiz = pastaTemporaria()
        let disco = PersistenciaDisco(raiz: raiz)
        _ = try await disco.preparar()
        await disco.registrarEntrada(papel: "usuario", texto: "Hello World!")
        await disco.registrarEntrada(papel: "agente", texto: "Pronto.")
        await disco.registrarEntrada(papel: "agente", texto: "   ")

        let json = await disco.conversaJson()
        let decodificado = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: json)
        #expect(decodificado["turnos"]?.count == 2)
        #expect(decodificado["turnos"]?.first?.papel == "usuario")

        let reaberto = PersistenciaDisco(raiz: raiz)
        _ = try await reaberto.preparar()
        let jsonReaberto = await reaberto.conversaJson()
        let turnosReabertos = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: jsonReaberto)
        #expect(turnosReabertos["turnos"]?.count == 2)

        await reaberto.limparConversa()
        let jsonLimpo = await reaberto.conversaJson()
        let vazio = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: jsonLimpo)
        #expect(vazio["turnos"] == [])
    }

    @Test("sessão salva sobrevive a novo boot")
    func cicloSessao() async throws {
        let raiz = pastaTemporaria()
        var sessao = SessaoV1()
        sessao.backend = "spike"
        sessao.model = "Spike"
        sessao.toolAllowlist = ["clip.trigger", "composition.info"]
        let disco = PersistenciaDisco(raiz: raiz)
        _ = try await disco.preparar()
        await disco.salvarSessao(sessao)

        let reaberto = PersistenciaDisco(raiz: raiz)
        let restaurada = try await reaberto.preparar()
        #expect(restaurada == sessao)
    }

    @Test("disco corrompido volta ao padrão sem derrubar o daemon")
    func discoCorrompido() async throws {
        let raiz = pastaTemporaria()
        try FileManager.default.createDirectory(
            at: raiz.appendingPathComponent("conversas"),
            withIntermediateDirectories: true)
        try Data("não sou json".utf8)
            .write(to: raiz.appendingPathComponent("conversas/conversa.json"))
        try Data("lixo".utf8).write(to: raiz.appendingPathComponent("sessao.json"))
        let disco = PersistenciaDisco(raiz: raiz)
        let restaurada = try await disco.preparar()
        #expect(restaurada == nil)
        let json = await disco.conversaJson()
        let vazio = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: json)
        #expect(vazio["turnos"] == [])
    }

    @Test("turnos ganham id sequencial e o publicador recebe cada mudança")
    func idsEPublicador() async throws {
        let raiz = pastaTemporaria()
        let disco = PersistenciaDisco(raiz: raiz)
        _ = try await disco.preparar()

        let publicados = PublicadosColetor()
        await disco.definirPublicador { corpo in
            await publicados.registrar(corpo)
        }

        await disco.registrarEntrada(papel: "usuario", texto: "um")
        await disco.registrarEntrada(papel: "agente", texto: "dois")
        await disco.registrarEntrada(papel: "agente", texto: "   ")

        let json = await disco.conversaJson()
        let decodificado = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: json)
        #expect(decodificado["turnos"]?.compactMap(\.id) == [1, 2])

        var coletados = await publicados.snapshot()
        #expect(coletados.count == 2)

        await disco.limparConversa()
        coletados = await publicados.snapshot()
        #expect(coletados.count == 3)
        let vazio = try JSONDecoder().decode(
            [String: [PersistenciaDisco.Turno]].self, from: coletados[2])
        #expect(vazio["turnos"] == [])
    }

    @Test("ConversaHub entrega a todos e para ao cancelar")
    func hubConversa() async {
        let hub = ConversaHub()
        let coletorA = PublicadosColetor()
        let coletorB = PublicadosColetor()
        _ = await hub.assinar { corpo in
            await coletorA.registrar(corpo)
        }
        let assinaturaB = await hub.assinar { corpo in
            await coletorB.registrar(corpo)
        }
        await hub.publicar(Data("{}".utf8))
        await hub.cancelar(assinaturaB)
        await hub.publicar(Data("[]".utf8))
        #expect(await coletorA.snapshot().count == 2)
        #expect(await coletorB.snapshot().count == 1)
    }
}

private actor PublicadosColetor {
    private var corpos: [Data] = []

    func registrar(_ corpo: Data) {
        corpos.append(corpo)
    }

    func snapshot() -> [Data] {
        corpos
    }
}
