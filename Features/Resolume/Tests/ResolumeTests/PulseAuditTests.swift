import Foundation
import Network
import Pulse
import Testing
@testable import Resolume

/// Regressao da auditoria de rede: a sessao do Pulse tem que gravar pedido,
/// resposta e metricas sem alterar o trafego — e tem que redigir segredos.
@Test("sessao auditada grava pedido, resposta e cabecalho redigido no store")
func auditedSessionRecordsRequestResponseAndRedactedHeader() async throws {
    let servidor = try ServidorEcho()
    let porta = try await servidor.porta()

    let auditor = try PulseAuditor(
        storeURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "resolux-pulse-testes.pulse"),
        emMemoria: true)
    let proxy = auditor.makeProxy()

    var pedido = URLRequest(
        url: URL(string: "http://127.0.0.1:\(porta)/api/v1/composition")!)
    pedido.setValue("Bearer secreto-123", forHTTPHeaderField: "Authorization")

    let (corpo, resposta) = try await proxy.data(for: pedido)
    #expect((resposta as? HTTPURLResponse)?.statusCode == 200)
    #expect(corpo == Data("{\"ok\":true}".utf8))

    let tarefa = try await aguardarTarefaFinalizada(auditor: auditor,
                                                    sufixoURL: "/api/v1/composition")
    #expect(tarefa.httpMethod == "GET")
    #expect(tarefa.statusCode == 200)
    #expect(tarefa.requestState == NetworkTaskEntity.State.success.rawValue)
    #expect(tarefa.responseBodySize == 11)
    #expect(tarefa.originalRequest?.headers["Authorization"] == "<private>")
    servidor.parar()
}

@Test("POST auditado grava o corpo do pedido (caminho do transporte de chat)")
func auditedPOSTRecordsRequestBody() async throws {
    let servidor = try ServidorEcho()
    let porta = try await servidor.porta()

    let auditor = try PulseAuditor(
        storeURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "resolux-pulse-testes.pulse"),
        emMemoria: true)
    let proxy = auditor.makeProxy()

    var pedido = URLRequest(
        url: URL(string: "http://127.0.0.1:\(porta)/api/v1/chat/completions")!)
    pedido.httpMethod = "POST"
    pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
    pedido.httpBody = Data("{\"model\":\"qwen3\"}".utf8)

    let (_, resposta) = try await proxy.data(for: pedido)
    #expect((resposta as? HTTPURLResponse)?.statusCode == 200)

    let tarefa = try await aguardarTarefaFinalizada(auditor: auditor,
                                                    sufixoURL: "/api/v1/chat/completions")
    #expect(tarefa.httpMethod == "POST")
    #expect(tarefa.requestBodySize == Int64("{\"model\":\"qwen3\"}".utf8.count))
    servidor.parar()
}

/// O store do Pulse grava de forma adiantada (coalesced writes): espera a
/// task aparecer e terminar antes de afirmar qualquer coisa sobre ela.
private func aguardarTarefaFinalizada(
    auditor: PulseAuditor,
    sufixoURL: String,
    teto: TimeInterval = 3) async throws -> NetworkTaskEntity {
    let inicio = Date()
    while Date().timeIntervalSince(inicio) < teto {
        if let tarefa = try auditor.tasks().first(where: {
            $0.url?.hasSuffix(sufixoURL) == true
                && ($0.requestState == NetworkTaskEntity.State.success.rawValue
                    || $0.requestState == NetworkTaskEntity.State.failure.rawValue)
        }) {
            return tarefa
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw PulseTestError.tarefaNaoGravada(sufixoURL)
}

private enum PulseTestError: Error {
    case tarefaNaoGravada(String)
}

/// Servidor HTTP minimo para os testes: responde 200 JSON a qualquer pedido
/// (uma request por conexao, `Connection: close`).
private final class ServidorEcho: @unchecked Sendable {
    private let listener: NWListener
    private let fila = DispatchQueue(label: "resolux.pulse-tests.servidor")
    private let mutex = NSLock()
    private var conexoes: [NWConnection] = []
    private var pronto = false

    init() throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] conexao in
            guard let self else { return }
            mutex.lock()
            conexoes.append(conexao)
            mutex.unlock()
            atender(conexao)
        }
        listener.stateUpdateHandler = { [weak self] estado in
            guard let self, case .ready = estado else { return }
            mutex.lock()
            pronto = true
            mutex.unlock()
        }
        listener.start(queue: fila)
    }

    /// A porta so existe depois do listener chegar em `ready`.
    func porta(teto: TimeInterval = 3) async throws -> UInt16 {
        let inicio = Date()
        while Date().timeIntervalSince(inicio) < teto {
            if estaPronto(), let porta = listener.port, porta.rawValue != 0 {
                return porta.rawValue
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw PulseTestError.tarefaNaoGravada("porta do servidor de teste")
    }

    private func estaPronto() -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return pronto
    }

    private func atender(_ conexao: NWConnection) {
        conexao.start(queue: fila)
        conexao.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
            let corpo = Data("{\"ok\":true}".utf8)
            let resposta = Data("""
            HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\
            Content-Length: \(corpo.count)\r\nConnection: close\r\n\r\n
            """.utf8) + corpo
            conexao.send(content: resposta, completion: .contentProcessed { _ in
                conexao.cancel()
            })
        }
    }

    func parar() {
        mutex.lock()
        let todas = conexoes
        conexoes = []
        mutex.unlock()
        todas.forEach { $0.cancel() }
        listener.cancel()
    }
}
