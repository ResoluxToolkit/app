import Foundation

/// Transporte real: lança o binário do servidor MCP como child process stdio.
public actor ProcessMCPTransport: MCPTransport {
    public enum TimeoutError: Error { case responseTimedOut }

    private let executableURL: URL
    private let arguments: [String]
    private let responseTimeout: TimeInterval
    private let terminationTimeout: TimeInterval

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
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
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
    }

    public func send(requestLine: String) async throws -> String {
        try await writeLine(requestLine)
        do {
            return try await Self.withTimeout(responseTimeout) { [self] in
                try await self.readLine()
            }
        } catch let error as TimeoutError {
            // Leitura bloqueada não é cancelável: derrubar o transporte
            // fecha os pipes e libera o read órfão com transportClosed.
            await stop()
            throw error
        }
    }

    public func notify(_ line: String) async throws {
        try await writeLine(line)
    }

    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        stdinPipe?.fileHandleForWriting.closeFile()
        stdoutPipe?.fileHandleForReading.closeFile()
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(terminationTimeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    static func withTimeout<R: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> R
    ) async throws -> R {
        try await withThrowingTaskGroup(of: R.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.responseTimedOut
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw TimeoutError.responseTimedOut }
            return value
        }
    }

    private func writeLine(_ line: String) async throws {
        guard !isStopped, let stdinPipe, let process, process.isRunning else {
            throw MCPError.transportClosed
        }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(data)
    }

    private func readLine() async throws -> String {
        guard !isStopped, let stdoutPipe else { throw MCPError.transportClosed }
        while true {
            if let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newline]
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
                guard let line = String(data: lineData, encoding: .utf8) else {
                    throw MCPError.malformedResponse
                }
                return line
            }
            let chunk: Data
            do {
                chunk = try stdoutPipe.fileHandleForReading.read(upToCount: 65_536) ?? Data()
            } catch {
                throw MCPError.transportClosed
            }
            guard !chunk.isEmpty else { throw MCPError.transportClosed }
            stdoutBuffer.append(chunk)
        }
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
