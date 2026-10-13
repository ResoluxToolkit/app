import Foundation
import Testing
@testable import Resolume

@Test("MonitorHTTPServer entrega SSE em /monitor e faz detach ao fechar")
func sseEndpoint() async throws {
    let hub = MonitorHub(
        systemSource: StubServerSystemSource(),
        networkSource: ThrowingNetworkSource(),
        ndiSource: EmptyNDISource(),
        midiSource: EmptyMIDISource(),
        artNetSource: EmptyArtNetSource(),
        captureSource: EmptyCaptureSource(),
        audioSource: EmptyAudioSource(),
        displaySource: EmptyDisplaySource(),
        pollInterval: 0.05)
    let server = MonitorHTTPServer(hub: hub, port: 0, relayInterval: 0.05)
    try await server.start()

    let portDeadline = Date().addingTimeInterval(2)
    var bound: UInt16?
    while bound == nil && Date() < portDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        bound = await server.boundPort
    }
    let port = try #require(bound, "listener não ficou pronto")

    let collector = SSECollector()
    let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
    let url = URL(string: "http://127.0.0.1:\(port)/monitor")!
    let task = session.dataTask(with: url)
    task.resume()

    let eventDeadline = Date().addingTimeInterval(2)
    while !collector.hasFirstEvent && Date() < eventDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    let event = try #require(collector.firstEvent, "primeiro evento SSE não chegou")
    #expect(event.hasPrefix("data: {"))
    #expect(event.contains(#""contractVersion":1"#))
    #expect(event.contains(#""cpuModel":"stub-server""#))

    task.cancel()
    session.finishTasksAndInvalidate()

    let closeDeadline = Date().addingTimeInterval(2)
    var clients = await hub.clientCount()
    while clients != 0 && Date() < closeDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        clients = await hub.clientCount()
    }
    #expect(clients == 0)

    await server.stop()
}

@Test("MonitorHTTPServer responde 404 fora de /monitor")
func notFoundPath() async throws {
    let server = MonitorHTTPServer(hub: MonitorHub(), port: 0, relayInterval: 0.05)
    try await server.start()
    let portDeadline = Date().addingTimeInterval(2)
    var bound: UInt16?
    while bound == nil && Date() < portDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        bound = await server.boundPort
    }
    let port = try #require(bound, "listener não ficou pronto")

    let url = URL(string: "http://127.0.0.1:\(port)/errado")!
    let (_, response) = try await URLSession.shared.data(from: url)
    #expect((response as? HTTPURLResponse)?.statusCode == 404)

    await server.stop()
}

@Test("MonitorHTTPServer serve a página web em /")
func indexPage() async throws {
    let server = MonitorHTTPServer(hub: MonitorHub(), port: 0, relayInterval: 0.05)
    try await server.start()
    let portDeadline = Date().addingTimeInterval(2)
    var bound: UInt16?
    while bound == nil && Date() < portDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        bound = await server.boundPort
    }
    let port = try #require(bound, "listener não ficou pronto")

    let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 200)
    #expect(http.value(forHTTPHeaderField: "Content-Type")?.contains("text/html") == true)
    let html = String(decoding: data, as: UTF8.self)
    #expect(html.contains("EventSource"))
    #expect(html.contains("'/monitor'"))

    await server.stop()
}

final class SSECollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var hasFirstEvent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.range(of: Data("data: {".utf8)) != nil
    }

    var firstEvent: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let range = buffer.range(of: Data("\n\n".utf8)) else { return nil }
        return String(data: buffer[..<range.lowerBound], encoding: .utf8)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}

private struct StubServerSystemSource: SystemMonitorSource {
    func hardware() async throws -> SystemHardware {
        SystemHardware(cpuModel: "stub-server", coreCount: 1, physicalMemoryBytes: 1)
    }

    func cpuLoad() async throws -> CPULoad? {
        CPULoad(usagePercent: 10, userPercent: 4, systemPercent: 2, idlePercent: 86)
    }

    func gpuMetrics() async throws -> GPUMetrics? { nil }
    func ports() async throws -> [SystemPortEndpoint] { [] }

    func processes() async throws -> [SystemProcessInfo] { [] }

    func memoryUsage() async throws -> MemoryUsage {
        MemoryUsage(totalBytes: 1, usedBytes: 0, activeBytes: 0, wiredBytes: 0, compressorBytes: 0, freeBytes: 1)
    }
}

private struct ThrowingNetworkSource: NetworkMonitorSource {
    func sample() async throws -> NetworkSample {
        throw NetworkMonitorError.interfacesUnavailable
    }
}

private struct EmptyNDISource: NDIMonitorSource {
    func status() async -> NDIStatus {
        NDIStatus(isAvailable: false, libraryPath: nil, version: nil, sources: [])
    }
}

private struct EmptyMIDISource: MIDIMonitorSource {
    func status() async -> MIDIStatus {
        MIDIStatus(isAvailable: false, error: nil, sources: [])
    }
}

private struct EmptyArtNetSource: ArtNetMonitorSource {
    func poll() async -> ArtNetPollResult {
        ArtNetPollResult(nodes: [], replyCount: 0, error: nil)
    }
}

private struct EmptyCaptureSource: CaptureDeviceSource {
    func devices() async -> [CaptureDeviceInfo] { [] }
}

private struct EmptyAudioSource: AudioDeviceSource {
    func devices() async -> [AudioDeviceInfo] { [] }
}

private struct EmptyDisplaySource: DisplayMonitorSource {
    func displays() async -> [DisplayInfo] { [] }
}
