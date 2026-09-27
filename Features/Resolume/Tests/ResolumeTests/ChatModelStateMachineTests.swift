import Foundation
import Testing
@testable import Resolume
@testable import ResolumeUI

/// Regressão do botão preso: o `connect()` exigia `phase == .idle`, então depois
/// de qualquer falha o modelo ficava em `.failed` sem maneira de tentar de novo.
@MainActor
private func settle(
    _ model: ResolumeChatModel,
    outOf phase: ResolumeChatModel.Phase,
    timeout: Duration = .seconds(20)
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if model.phase != phase { return true }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
    return false
}

private final class ReadinessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) { self.value = value }

    var current: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

@Test("prontidão falsa derruba a conexão com motivo claro", .timeLimit(.minutes(1)))
@MainActor
func unreadyInstallationFailsWithReason() {
    let box = ReadinessBox(false)
    let model = ResolumeChatModel(product: .arena) { _ in box.current }
    model.connect(settings: .init(apiKey: "sk-teste"))

    guard case .failed(let reason) = model.phase else {
        Issue.record("esperava .failed, veio \(model.phase)")
        return
    }
    #expect(reason.contains("REST"))
}

/// O produto nao tem campo de API key -- o app descobre o provedor local
/// sozinho. Entao a falha que este teste cobre passou a ser outra: nenhum
/// provedor de pe. Continua sendo o lugar exato onde a pessoa fica presa sem
/// botao de tentar de novo, que era o bug original.
@Test("sem provedor local a falha diz as portas sondadas e nao prende o modelo",
      .timeLimit(.minutes(1)))
@MainActor
func undiscoveredProviderFailsCleanlyAndStaysRetryable() async {
    let box = ReadinessBox(true)
    let model = ResolumeChatModel(
        product: .arena,
        readiness: { _ in box.current },
        discovery: { [] })

    model.connect()
    // A descoberta roda em Task: sem esperar aqui, a fase ainda seria
    // .connecting e a assercao abaixo seria mentira.
    let saiu = await settle(model, outOf: .connecting)
    #expect(saiu, "modelo ficou preso em connecting sem provedor nenhum")

    guard case .failed(let reason) = model.phase else {
        Issue.record("esperava .failed, veio \(model.phase)")
        return
    }
    // Motivo acionavel: tem que dizer o que ele procurou.
    #expect(reason.contains("1976") && reason.contains("11434"),
            "motivo nao aponta os dois provedores sondados: \(reason)")

    // Segunda tentativa tem que ser reavaliada, nao engolida por um guarda de
    // fase: aqui o Arena some do meio do caminho entre uma tentativa e outra.
    box.current = false
    model.connect()
    guard case .failed(let segundoMotivo) = model.phase else {
        Issue.record("reconexao ignorada: fase continua \(model.phase)")
        return
    }
    #expect(segundoMotivo.contains("REST"))

    model.disconnect()
    #expect(model.phase == .idle)
}

@Test("depois de falhar dá para reconectar até ficar pronto", .timeLimit(.minutes(2)))
@MainActor
func retryAfterFailureReachesReady() async throws {
    try #require(
        ResolumeProduct.arena.isResponsive(),
        "Arena não está atendendo o socket REST"
    )
    let box = ReadinessBox(true)
    let model = ResolumeChatModel(product: .arena) { _ in box.current }

    // Falha deliberada primeiro, para sair de .idle.
    box.current = false
    model.connect(settings: .init(apiKey: "sk-inexistente"))
    guard case .failed = model.phase else {
        Issue.record("esperava falha deliberada, veio \(model.phase)")
        return
    }

    // Agora abre o portão: a mesma chamada precisa evoluir além de .failed.
    box.current = true
    model.connect(settings: .init(apiKey: "sk-inexistente"))
    let moved = await settle(model, outOf: .failed(""))
    #expect(moved)

    let reached = await waitUntil(timeout: .seconds(25)) {
        if case .ready = model.phase { return true }
        if case .failed = model.phase { return true }
        return false
    }
    #expect(reached)
    guard case .ready(let tools) = model.phase else {
        Issue.record("sessão real não ficou pronta: \(model.phase)")
        return
    }
    #expect(tools > 0)

    model.disconnect()
    #expect(model.phase == .idle)
    #expect(model.engine == nil)
}

@MainActor
private func waitUntil(
    timeout: Duration,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
    return condition()
}
