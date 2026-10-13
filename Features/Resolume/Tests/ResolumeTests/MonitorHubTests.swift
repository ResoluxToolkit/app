import Foundation
import Testing
@testable import Resolume

@Test("MonitorContract faz round-trip JSON com ISO8601")
func monitorContractJSONRoundTrip() throws {
    let base = Date(timeIntervalSince1970: 1_234_567)
    let contract = MonitorContract(
        capturedAt: base,
        hardware: SystemHardware(cpuModel: "Apple M1", coreCount: 8, physicalMemoryBytes: 16_000_000_000),
        cpu: CPULoad(usagePercent: 42, userPercent: 20, systemPercent: 12, idlePercent: 58),
        memory: MemoryUsage(
            totalBytes: 16_000_000_000,
            usedBytes: 8_000_000_000,
            activeBytes: 4_000_000_000,
            wiredBytes: 1_000_000_000,
            compressorBytes: 500_000_000,
            freeBytes: 8_000_000_000),
        gpu: GPUMetrics(
            name: "Apple M1",
            devicePercent: 33,
            rendererPercent: 20,
            tilerPercent: 15,
            allocatedBytes: 500_000_000,
            usedBytes: 250_000_000),
        ports: [SystemPortEndpoint(
            localAddress: "127.0.0.1",
            localPort: 8080,
            transport: "TCP",
            addressFamily: "IPv4",
            processName: "Arena",
            processID: 1687,
            service: "HTTP")],
        network: NetworkSample(capturedAt: base, interfaces: [
            monitorCounters(name: "en0", isLoopback: false, bytesIn: 1_000, bytesOut: 100),
        ]),
        throughputs: [NetworkThroughput(
            name: "en0",
            bytesInPerSecond: 900,
            bytesOutPerSecond: 80,
            packetsInPerSecond: 10,
            packetsOutPerSecond: 5)],
        networkTotals: NetworkTotals(
            bytesInPerSecond: 900,
            bytesOutPerSecond: 80,
            packetsInPerSecond: 10,
            packetsOutPerSecond: 5,
            bytesInSinceBoot: 1_000,
            bytesOutSinceBoot: 100),
        ndi: NDIStatus(
            isAvailable: true,
            libraryPath: "/tmp/libndi.dylib",
            version: "6.1.1",
            sources: [NDIDiscoveredSource(name: "Composition", address: "127.0.0.1:5962")]),
        midi: MIDIStatus(isAvailable: true, error: nil, sources: [
            MIDISourceState(
                uniqueID: 7,
                name: "Keyboard",
                manufacturer: "Teste",
                packetCount: 3,
                lastMessageAt: Date(timeIntervalSince1970: 990)),
        ]),
        artNet: ArtNetPollResult(
            nodes: [ArtNetNode(ipAddress: "127.0.0.1", shortName: "Node", longName: "Node Longo", status1: 0)],
            replyCount: 1,
            error: nil),
        captureDevices: [CaptureDeviceInfo(
            uniqueID: "cam-1",
            name: "Câmera",
            deviceType: "builtInWideAngleCamera",
            hasVideo: true,
            hasAudio: false,
            position: "frontal",
            isConnected: true)],
        audioDevices: [AudioDeviceInfo(
            uid: "aud-1",
            name: "Built-In",
            manufacturer: "Apple",
            transportType: "Built-In",
            isAlive: true,
            isDefaultInput: true,
            isDefaultOutput: false,
            inputStreams: 1,
            outputStreams: 0)],
        displays: [DisplayInfo(
            id: 1,
            originX: 0,
            originY: 0,
            pointWidth: 1920,
            pointHeight: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 60,
            isMain: true)]
    )

    let data = try MonitorContract.json(from: contract)
    let decoded = try MonitorContract.decode(from: data)
    #expect(decoded == contract)
    #expect(decoded.contractVersion == MonitorContract.version)
}

@Test("MonitorHub roda lazy: attach/detach controla a coleta")
func lazyLifecycle() async {
    let hub = MonitorHub(
        systemSource: StubSystemSource(),
        networkSource: ScriptedNetworkSource(samples: [NetworkSample(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            interfaces: [monitorCounters(name: "en0", isLoopback: false, bytesIn: 1_000, bytesOut: 100)])]),
        ndiSource: FixedNDISource(),
        midiSource: FixedMIDISource(),
        artNetSource: FixedArtNetSource(),
        captureSource: FixedCaptureSource(),
        audioSource: FixedAudioSource(),
        displaySource: FixedDisplaySource(),
        pollInterval: 0.05)

    await #expect(hub.isRunning == false)
    let first = await hub.attach()
    await #expect(hub.clientCount() == 1)
    await #expect(hub.isRunning == true)
    #expect(first.networkTotals == nil)
    #expect(first.hardware?.cpuModel == "stub")
    #expect(first.cpu?.usagePercent == 10)
    #expect(first.ndi?.isAvailable == true)
    #expect(first.midi?.sources.first?.name == "Keyboard")
    #expect(first.artNet?.replyCount == 1)
    #expect(first.captureDevices.first?.name == "Câmera")
    #expect(first.audioDevices.first?.name == "Built-In")
    #expect(first.displays.first?.isMain == true)

    _ = await hub.attach()
    await #expect(hub.clientCount() == 2)

    await hub.detach()
    await #expect(hub.clientCount() == 1)
    await #expect(hub.isRunning == true)

    await hub.detach()
    await #expect(hub.clientCount() == 0)
    await #expect(hub.isRunning == false)
    await #expect(hub.snapshot() == nil)
}

@Test("Taxa de rede aparece no segundo poll do MonitorHub")
func throughputSecondPoll() async throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let hub = MonitorHub(
        systemSource: StubSystemSource(),
        networkSource: ScriptedNetworkSource(samples: [
            NetworkSample(capturedAt: base, interfaces: [
                monitorCounters(name: "en0", isLoopback: false, bytesIn: 1_000, bytesOut: 100),
            ]),
            NetworkSample(capturedAt: base.addingTimeInterval(1), interfaces: [
                monitorCounters(name: "en0", isLoopback: false, bytesIn: 2_000, bytesOut: 300),
            ]),
        ]),
        ndiSource: FixedNDISource(),
        midiSource: FixedMIDISource(),
        artNetSource: FixedArtNetSource(),
        captureSource: FixedCaptureSource(),
        audioSource: FixedAudioSource(),
        displaySource: FixedDisplaySource(),
        pollInterval: 0.05)

    _ = await hub.attach()
    var totals: NetworkTotals?
    let deadline = Date().addingTimeInterval(2)
    while totals == nil && Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        totals = await hub.snapshot()?.networkTotals
    }
    let found = try #require(totals)
    #expect(found.bytesInPerSecond == 1_000)
    #expect(found.bytesOutPerSecond == 200)
    await hub.detach()
}

@Test("Processos só são relidos após o intervalo dedicado")
func processPollThrottle() async throws {
    let source = ContagemPortasSource()
    let hub = MonitorHub(
        systemSource: source,
        networkSource: ScriptedNetworkSource(samples: []),
        ndiSource: FixedNDISource(),
        midiSource: FixedMIDISource(),
        artNetSource: FixedArtNetSource(),
        captureSource: FixedCaptureSource(),
        audioSource: FixedAudioSource(),
        displaySource: FixedDisplaySource(),
        pollInterval: 0.02,
        processPollInterval: 0.08)

    _ = await hub.attach()
    try await Task.sleep(nanoseconds: 100_000_000)
    let chamadas = await source.chamadas
    #expect(chamadas >= 2 && chamadas <= 3)
    await hub.detach()
}

private func monitorCounters(
    name: String,
    isLoopback: Bool,
    bytesIn: UInt64,
    bytesOut: UInt64
) -> NetworkInterfaceCounters {
    NetworkInterfaceCounters(
        name: name,
        macAddress: nil,
        addresses: ["10.0.0.2"],
        isUp: true,
        isLoopback: isLoopback,
        bytesIn: bytesIn,
        bytesOut: bytesOut,
        packetsIn: 0,
        packetsOut: 0,
        errorsIn: 0,
        errorsOut: 0,
        dropsIn: 0)
}

private struct StubSystemSource: SystemMonitorSource {
    func hardware() async throws -> SystemHardware {
        SystemHardware(cpuModel: "stub", coreCount: 1, physicalMemoryBytes: 1)
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

private actor ContagemPortasSource: SystemMonitorSource {
    private(set) var chamadas = 0

    func hardware() async throws -> SystemHardware {
        SystemHardware(cpuModel: "stub", coreCount: 1, physicalMemoryBytes: 1)
    }

    func cpuLoad() async throws -> CPULoad? { nil }
    func memoryUsage() async throws -> MemoryUsage {
        MemoryUsage(totalBytes: 1, usedBytes: 0, activeBytes: 0, wiredBytes: 0, compressorBytes: 0, freeBytes: 1)
    }
    func gpuMetrics() async throws -> GPUMetrics? { nil }

    func ports() async throws -> [SystemPortEndpoint] {
        chamadas += 1
        return []
    }

    func processes() async throws -> [SystemProcessInfo] { [] }
}

private actor ScriptedNetworkSource: NetworkMonitorSource {
    private let samples: [NetworkSample]
    private var index = 0

    init(samples: [NetworkSample]) {
        self.samples = samples
    }

    func sample() async throws -> NetworkSample {
        guard !samples.isEmpty else { throw NetworkMonitorError.interfacesUnavailable }
        let sample = samples[index % samples.count]
        index += 1
        return sample
    }
}

private struct FixedNDISource: NDIMonitorSource {
    func status() async -> NDIStatus {
        NDIStatus(
            isAvailable: true,
            libraryPath: "/tmp/libndi.dylib",
            version: "6.1.1",
            sources: [NDIDiscoveredSource(name: "Composition", address: "127.0.0.1:5962")])
    }
}

private struct FixedMIDISource: MIDIMonitorSource {
    func status() async -> MIDIStatus {
        MIDIStatus(isAvailable: true, error: nil, sources: [
            MIDISourceState(
                uniqueID: 7,
                name: "Keyboard",
                manufacturer: "Teste",
                packetCount: 3,
                lastMessageAt: Date(timeIntervalSince1970: 990)),
        ])
    }
}

private struct FixedArtNetSource: ArtNetMonitorSource {
    func poll() async -> ArtNetPollResult {
        ArtNetPollResult(
            nodes: [ArtNetNode(ipAddress: "127.0.0.1", shortName: "Node", longName: "Node Longo", status1: 0)],
            replyCount: 1,
            error: nil)
    }
}

private struct FixedCaptureSource: CaptureDeviceSource {
    func devices() async -> [CaptureDeviceInfo] {
        [CaptureDeviceInfo(
            uniqueID: "cam-1",
            name: "Câmera",
            deviceType: "builtInWideAngleCamera",
            hasVideo: true,
            hasAudio: false,
            position: "frontal",
            isConnected: true)]
    }
}

private struct FixedAudioSource: AudioDeviceSource {
    func devices() async -> [AudioDeviceInfo] {
        [AudioDeviceInfo(
            uid: "aud-1",
            name: "Built-In",
            manufacturer: "Apple",
            transportType: "Built-In",
            isAlive: true,
            isDefaultInput: true,
            isDefaultOutput: false,
            inputStreams: 1,
            outputStreams: 0)]
    }
}

private struct FixedDisplaySource: DisplayMonitorSource {
    func displays() async -> [DisplayInfo] {
        [DisplayInfo(
            id: 1,
            originX: 0,
            originY: 0,
            pointWidth: 1920,
            pointHeight: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 60,
            isMain: true)]
    }
}
