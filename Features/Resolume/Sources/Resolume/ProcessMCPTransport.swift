import Foundation

/// Transporte real: lança o binário do servidor MCP como child process stdio.
///
/// Nenhum `read` bloqueante roda dentro do actor: a leitura do stdout vive num
/// `readabilityHandler` em fila privada da Foundation, e a espera pela resposta
/// é uma única suspensão com watchdog próprio. Um servidor mudo faz o timeout
/// disparar de verdade — antes o `FileHandle.read` segurava o executor do actor,
/// o timeout nunca era agendado e o processo filho ficava órfão para sempre.
public actor ProcessMCPTransport: MCPTransport {
    public struct TimeoutError: Error {
        public init() {}
    }

    private let executableURL: URL
    private let arguments: [String]
    private let responseTimeout: TimeInterval
    private let terminationTimeout: TimeInterval

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let lines = LineQueue()
    private let stderrTail = StderrTail(capacity: 4_096)
    private var isStopped = false

    public init(
        executableURL: URL,
        arguments: [String] = [],
        responseTimeout: TimeInterval = 10,
        terminationTimeout: TimeInterval = 5
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.responseTimeout = responseTimeout
        self.terminationTimeout = terminationTimeout
    }

    public func start() async throws {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        // Capturar o stderr é o que dá diagnóstico quando o servidor recusa
        // subir ("Could not start Arena MCP Server" etc.).
        process.standardError = stderrPipe
        try process.run()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [lines] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                lines.close()
                try? handle.close()
            } else {
                lines.feed(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [stderrTail] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
            } else {
                stderrTail.append(String(decoding: data, as: UTF8.self))
            }
        }
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    /// PID do servidor enquanto ele vive; base para provar que `stop()` o matou.
    public var childPID: Int32? { process?.processIdentifier }

    public func send(requestLine: String) async throws -> String {
        try await writeLine(requestLine)
        do {
            return try await lines.next(timeout: responseTimeout)
        } catch let error as ProcessMCPTransport.TimeoutError {
            // Sem resposta não há como parear a próxima linha com o próximo
            // id: derrubar o transporte mantém o estado honesto.
            await stop()
            throw error
        }
    }

    public func notify(_ line: String) async throws {
        try await writeLine(line)
    }

    /// Últimos bytes do stderr do servidor — explica *por que* ele falhou.
    public func stderrDiagnostics() -> String { stderrTail.value }

    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        lines.close()
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(terminationTimeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func writeLine(_ line: String) async throws {
        guard !isStopped, let stdinPipe, let process, process.isRunning else {
            throw MCPError.transportClosed
        }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(data)
    }
}

extension ProcessMCPTransport.TimeoutError: LocalizedError {
    public var errorDescription: String? {
        "O servidor MCP não respondeu dentro do prazo"
    }
}

/// Fila de linhas do stdout, alimentada exclusivamente pelos handlers de
/// leitura — nunca por `read` bloqueante. Quem espera por linha é um waiter
/// reclamado exatamente uma vez (linha, timeout ou cancelamento).
private final class LineQueue: @unchecked Sendable {
    private enum Outcome {
        case timeout
        case cancelled

        func resolve(_ continuation: CheckedContinuation<String, any Error>) {
            switch self {
            case .timeout: continuation.resume(throwing: ProcessMCPTransport.TimeoutError())
            case .cancelled: continuation.resume(throwing: CancellationError())
            }
        }
    }

    /// Estado do waiter é sincronizado exclusivamente pelo lock da fila, o que
    /// autoriza o envio entre isolamentos no Swift 6.
    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<String, any Error>?
        var claimed = false
    }

    private let lock = NSLock()
    private var pending = Data()
    private var waiters: [Waiter] = []
    private var isClosed = false

    func feed(_ chunk: Data) {
        lock.lock()
        pending.append(chunk)
        var deliveries: [() -> Void] = []
        while !waiters.isEmpty, let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            let waiter = waiters.removeFirst()
            if waiter.claimed { continue }
            waiter.claimed = true
            guard let continuation = waiter.continuation else { continue }
            if let line = String(data: lineData, encoding: .utf8) {
                deliveries.append { continuation.resume(returning: line) }
            } else {
                deliveries.append { continuation.resume(throwing: MCPError.malformedResponse) }
            }
        }
        lock.unlock()
        for delivery in deliveries { delivery() }
    }

    func close() {
        lock.lock()
        isClosed = true
        let stranded = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in stranded where !waiter.claimed {
            waiter.claimed = true
            waiter.continuation?.resume(throwing: MCPError.transportClosed)
        }
    }

    /// Espera a próxima linha completa, com timeout real e cancelamento real.
    func next(timeout: TimeInterval) async throws -> String {
        let waiter = Waiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<String, any Error>) in
                lock.lock()
                if isClosed {
                    lock.unlock()
                    continuation.resume(throwing: MCPError.transportClosed)
                    return
                }
                if let newline = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    lock.unlock()
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.resume(returning: line)
                    } else {
                        continuation.resume(throwing: MCPError.malformedResponse)
                    }
                    return
                }
                waiter.continuation = continuation
                waiters.append(waiter)
                lock.unlock()
                armWatchdog(waiter, after: timeout)
            }
        } onCancel: { [self] in
            settle(waiter, with: .cancelled)
        }
    }

    private func armWatchdog(_ waiter: Waiter, after seconds: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.settle(waiter, with: .timeout)
        }
    }

    /// Entrega exactly-once: linha, timeout e cancelamento disputam o waiter
    /// sob o lock; quem reclama primeiro resolve a continuação.
    private func settle(_ waiter: Waiter, with outcome: Outcome) {
        lock.lock()
        if waiter.claimed { lock.unlock(); return }
        waiter.claimed = true
        if let index = waiters.firstIndex(where: { $0 === waiter }) {
            waiters.remove(at: index)
        }
        let continuation = waiter.continuation
        lock.unlock()
        if let continuation { outcome.resolve(continuation) }
    }
}

/// Cauda do stderr do servidor, limitada por capacidade e segura entre filas.
final class StderrTail: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var text = ""

    init(capacity: Int) { self.capacity = capacity }

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        if text.count > capacity { text = String(text.suffix(capacity)) }
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

public enum MCPError: Error, LocalizedError, Equatable {
    case transportClosed
    case malformedResponse
    case serverError(code: Int, message: String)
    case notInitialized
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .transportClosed: "O servidor MCP fechou a conexão"
        case .malformedResponse: "Resposta malformada do servidor MCP"
        case .serverError(let code, let message): "Erro do servidor MCP (\(code)): \(message)"
        case .notInitialized: "Sessão MCP não inicializada"
        case .toolFailed(let message): "Ferramenta MCP falhou: \(message)"
        }
    }
}
