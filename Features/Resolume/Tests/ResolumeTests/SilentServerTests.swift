import Darwin
import Foundation
import Testing
@testable import Resolume

/// Regressão do travamento: com `FileHandle.read` bloqueante dentro do actor, um
/// servidor mudo segurava o executor do actor, o timeout nunca era agendado, o
/// `stop()` nunca rodava e o processo filho ficava órfão para sempre.
/// `sleep` é o servidor mudo honesto — consome nada e nunca escreve
/// (cuidado: `cat` é eco e "responde" de volta a própria linha enviada).
@Test("servidor mudo estoura timeout em vez de travar", .timeLimit(.minutes(1)))
func silentServerTimesOutAndIsReaped() async throws {
    let transport = ProcessMCPTransport(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["30"],
        responseTimeout: 0.4)
    // Start explícito só para fotografar o PID enquanto o filho ainda vive: no
    // timeout o próprio transporte derruba a sessão e limpa o estado.
    try await transport.start()
    guard let childPID = await transport.childPID else {
        Issue.record("transporte sem PID de filho")
        return
    }
    let client = MCPClient(transport: transport)

    let started = ContinuousClock.now
    do {
        try await client.connect()
        Issue.record("esperava timeout, connect passou")
    } catch is ProcessMCPTransport.TimeoutError {
        // esperado: o watchdog respondeu mesmo com o filho calado
    }
    #expect(started.duration(to: .now) < .seconds(5))

    // O filho tem que morrer junto com a sessão.
    #expect(await transport.childPID == nil)
    #expect(await waitForReap(childPID), "servidor MCP ficou órfão vivo")
}

@Test("servidor morto na hora vira transportClosed", .timeLimit(.minutes(1)))
func deadServerReportsClosedTransport() async throws {
    let transport = ProcessMCPTransport(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "exit 1"],
        responseTimeout: 3)
    let client = MCPClient(transport: transport)
    do {
        try await client.connect()
        Issue.record("esperava falha de transporte")
    } catch is MCPError {
        // esperado: transportClosed veio do EOF no stdout
    }
    await client.disconnect()
}

/// `kill(pid, 0)` só devolve ESRCH depois que o filho saiu **e** foi colhido
/// (zumbi ainda responde 0), então essa é a prova de que não sobrou ninguém.
private func waitForReap(_ pid: Int32, timeout: Duration = .seconds(5)) async -> Bool {
    guard pid > 0 else { return false }
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if Darwin.kill(pid, 0) != 0 && errno == ESRCH { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return Darwin.kill(pid, 0) != 0 && errno == ESRCH
}
