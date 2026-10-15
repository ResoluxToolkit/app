import Foundation
import Network

public enum MonitorHTTPServerError: Error {
    case requestTimeout
    case connectionClosed
    case requestTooLarge
}

public actor MonitorHTTPServer {
    public static let defaultPort: UInt16 = 8091

    private let hub: MonitorHub
    private let port: UInt16
    private let relayInterval: TimeInterval
    private let queue = DispatchQueue(label: "resolux.monitor.server")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var streams: [UUID: Task<Void, Never>] = [:]

    public private(set) var boundPort: UInt16?

    public static func indexHTML() -> Data? {
        guard let url = Bundle.module.url(forResource: "monitor", withExtension: "html") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static let streamHeaders = Data(
        "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n\r\n".utf8)
    private static let indexHeaders = Data(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n".utf8)
    private static let notFoundResponse = Data(
        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    private static let headerEnd = Data("\r\n\r\n".utf8)

    public init(
        hub: MonitorHub = MonitorHub(),
        port: UInt16 = MonitorHTTPServer.defaultPort,
        relayInterval: TimeInterval = 1.0
    ) {
        self.hub = hub
        self.port = port
        self.relayInterval = relayInterval
    }

    public var activeConnections: Int { connections.count }
    public var isRunning: Bool { listener != nil }

    public func start() throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.atender(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { await self?.recordBoundPort() }
            case .failed:
                Task { await self?.stop() }
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        boundPort = nil
        for stream in streams.values { stream.cancel() }
        for connection in connections.values { connection.cancel() }
        streams.removeAll()
        connections.removeAll()
    }

    private func recordBoundPort() {
        boundPort = listener?.port?.rawValue
    }

    /// Aceita uma conexão já recebida pelo daemon. O `pedido` é opcional para
    /// o listener interno; quando o ResoluxServer repassa o HTTP completo, o
    /// SSE é servido na mesma porta 1980 sem abrir uma porta pública nova.
    public func atender(_ connection: NWConnection, pedido: Data? = nil, iniciar: Bool = true) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                Task { await self.forget(id: id) }
            default:
                break
            }
        }
        if iniciar {
            connection.start(queue: queue)
        }
        streams[id] = Task { await streamMonitor(id: id, connection: connection, pedido: pedido) }
    }

    private func forget(id: UUID) {
        connections.removeValue(forKey: id)
    }

    private func streamMonitor(id: UUID, connection: NWConnection, pedido: Data? = nil) async {
        do {
            let request: Data
            if let pedido {
                request = pedido
            } else {
                guard let lido = try? await Self.readRequest(connection: connection, timeout: 5) else {
                    try? await Self.send(connection: connection, data: Self.notFoundResponse)
                    await drop(id: id)
                    return
                }
                request = lido
            }
            guard let path = Self.requestPath(from: request) else {
                try? await Self.send(connection: connection, data: Self.notFoundResponse)
                await drop(id: id)
                return
            }

            if Self.isTerminatePath(path) && Self.isPostRequest(request) {
                let snapshot = await hub.snapshot()
                let pid = Self.processID(from: path)
                if let pid,
                   snapshot?.processes.contains(where: { $0.pid == pid }) == true,
                   Darwin.kill(pid_t(pid), SIGTERM) == 0 {
                    try? await Self.send(connection: connection, data: Self.respostaProcesso(ok: true))
                } else {
                    try? await Self.send(connection: connection, data: Self.respostaProcesso(ok: false))
                }
                await drop(id: id)
                return
            }

            if Self.isIndexPath(path) {
                if let html = Self.indexHTML() {
                    try? await Self.send(connection: connection, data: Self.indexHeaders + html)
                } else {
                    try? await Self.send(connection: connection, data: Self.notFoundResponse)
                }
                await drop(id: id)
                return
            }

            guard Self.isMonitorPath(path) else {
                try? await Self.send(connection: connection, data: Self.notFoundResponse)
                await drop(id: id)
                return
            }

            let first = await hub.attach()
            try await Self.send(connection: connection, data: Self.streamHeaders)
            try await sendEvent(first, connection: connection)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(relayInterval * 1_000_000_000))
                if Task.isCancelled { break }
                guard let snapshot = await hub.snapshot() else { break }
                try await sendEvent(snapshot, connection: connection)
            }
            await hub.detach()
        } catch {
            await hub.detach()
        }
        await drop(id: id)
    }

    private func drop(id: UUID) {
        if let stream = streams.removeValue(forKey: id) { stream.cancel() }
        if let connection = connections.removeValue(forKey: id) { connection.cancel() }
    }

    private func sendEvent(_ contract: MonitorContract, connection: NWConnection) async throws {
        var event = Data("data: ".utf8)
        event.append(try MonitorContract.json(from: contract))
        event.append(Data("\n\n".utf8))
        try await Self.send(connection: connection, data: event)
    }

    private static func send(connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func readRequest(connection: NWConnection, timeout: TimeInterval) async throws -> Data {
        var accumulated = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while accumulated.range(of: headerEnd) == nil {
            guard Date() < deadline else { throw MonitorHTTPServerError.requestTimeout }
            let (data, isComplete) = try await receiveChunk(connection)
            if let data { accumulated.append(data) }
            if isComplete { throw MonitorHTTPServerError.connectionClosed }
            if accumulated.count > 16_384 { throw MonitorHTTPServerError.requestTooLarge }
        }
        return accumulated
    }

    private static func receiveChunk(_ connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private static func requestPath(from request: Data) -> String? {
        guard let end = request.range(of: Data("\r\n".utf8)) else { return nil }
        guard let line = String(data: request[..<end.lowerBound], encoding: .utf8) else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1]).split(separator: "?").first.map(String.init)
    }

    private static func isPostRequest(_ request: Data) -> Bool {
        guard let end = request.range(of: Data("\r\n".utf8)) else { return false }
        guard let line = String(data: request[..<end.lowerBound], encoding: .utf8) else { return false }
        return line.hasPrefix("POST ")
    }

    private static func respostaProcesso(ok: Bool) -> Data {
        let corpo = Data("{\"ok\":\(ok)}".utf8)
        return Data("HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nContent-Length: \(corpo.count)\r\nConnection: close\r\n\r\n".utf8) + corpo
    }

    private static func isMonitorPath(_ path: String) -> Bool {
        path == "/monitor"
    }

    private static func isTerminatePath(_ path: String) -> Bool {
        path.hasPrefix("/monitor/processes/") && path.hasSuffix("/terminate")
    }

    private static func processID(from path: String) -> Int? {
        let partes = path.split(separator: "/")
        guard partes.count == 4,
              partes[0] == "monitor",
              partes[1] == "processes",
              partes[3] == "terminate",
              !partes[2].isEmpty,
              partes[2].allSatisfy(\.isNumber) else { return nil }
        return Int(partes[2])
    }

    private static func isIndexPath(_ path: String) -> Bool {
        path == "/" || path == "/index.html"
    }
}

public actor MonitorWebService {
    public static let shared = MonitorWebService()
    private var server: MonitorHTTPServer?

    public func start(port: UInt16 = MonitorHTTPServer.defaultPort) async {
        guard server == nil else { return }
        let server = MonitorHTTPServer(port: port)
        do {
            try await server.start()
        } catch {
            return
        }
        self.server = server
    }

    public func stop() async {
        await server?.stop()
        server = nil
    }

    public var boundPort: UInt16? {
        get async { await server?.boundPort }
    }

    public var isRunning: Bool {
        get async { await server?.isRunning ?? false }
    }
}
