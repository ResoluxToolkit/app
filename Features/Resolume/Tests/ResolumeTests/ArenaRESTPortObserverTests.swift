import Foundation
@testable import ResolumeUI
import Testing
@testable import Resolume

@Test("observador devolve a primeira porta que responde, na ordem")
func observadorRespeitaOrdemDosCandidatos() async throws {
    let recorder = ProbeRecorder()
    let observer = ArenaRESTPortObserver(candidates: [8080, 8008, 8088]) { port in
        await recorder.record(port)
        guard port == 8008 else { throw ArenaREST.Failure.http(404) }
    }

    let porta = try await observer.observe()

    #expect(porta == 8008)
    #expect(await recorder.probed == [8080, 8008])
}

@Test("observador falha com as portas tentadas quando ninguem responde")
func observadorFalhaTodasPortas() async {
    let observer = ArenaRESTPortObserver(candidates: [8080, 8008]) { _ in
        throw ArenaREST.Failure.transporte("morto")
    }

    do {
        _ = try await observer.observe()
        Issue.record("observação devia falhar")
    } catch let failure as ArenaRESTPortObserver.Failure {
        #expect(failure.triedPorts == [8080, 8008])
    } catch {
        Issue.record("erro inesperado: \(error)")
    }
}

@MainActor
@Test("monitor observa a porta antes do primeiro poll")
func monitorObservaPortaAntesDePollar() async {
    let compositionData = Data(#"{"layers":[]}"#.utf8)
    let model = ArenaMonitorModel(
        portObserver: ArenaRESTPortObserver(candidates: [8080, 8008]) { port in
            guard port == 8080 else { return }
            throw ArenaREST.Failure.transporte("morto")
        },
        makeREST: { _ in
            ArenaREST(endpoint: .init(
                get: { _ in compositionData },
                post: { _, _ in Data() }))
        })

    await model.pollOnce()

    #expect(model.connected)
    #expect(model.observedPort == 8008)
}

@MainActor
@Test("monitor fica offline quando nenhuma porta responde")
func monitorSemPortaFicaOffline() async {
    let model = ArenaMonitorModel(
        portObserver: ArenaRESTPortObserver(candidates: [8080]) { _ in
            throw ArenaREST.Failure.transporte("morto")
        })

    await model.pollOnce()

    #expect(!model.connected)
    #expect(model.observedPort == nil)
}

private actor ProbeRecorder {
    private(set) var probed: [Int] = []

    func record(_ port: Int) {
        probed.append(port)
    }
}
