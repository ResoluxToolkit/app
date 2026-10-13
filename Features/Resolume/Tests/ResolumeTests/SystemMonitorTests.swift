import Foundation
import Testing
@testable import ResolumeUI
@testable import Resolume

@Test("CPU calcula delta entre dois ticks")
func cpuDelta() throws {
    let previous = CPUTicks(user: 10, system: 5, idle: 85, nice: 0)
    let current = CPUTicks(user: 20, system: 10, idle: 170, nice: 0)
    let load = try #require(SystemMonitorMath.cpuLoad(current: current, previous: previous))
    #expect(load.usagePercent == 15)
    #expect(load.userPercent == 10)
    #expect(load.systemPercent == 5)
    #expect(load.idlePercent == 85)
}

@Test("LSOF é traduzido para portas e protocolos")
func portsParsing() {
    let output = """
    COMMAND           PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    Arena             1687 luizinho   58u  IPv4 0x1 0t0 TCP *:8080 (LISTEN)
    mDNSResponder      128 luizinho   10u  IPv4 0x1 0t0 UDP *:5353
    Remolo\\x20Helper   1749 luizinho   14u  IPv6 0x1 0t0 TCP [::1]:7000 (LISTEN)
    Arena             1687 luizinho   40u  IPv4 0x1 0t0 UDP 127.0.0.1:50587->127.0.0.1:7001
    """
    let ports = SystemMonitorMath.ports(fromLSOF: output, transport: "TCP")
    #expect(ports.map(\.localPort) == [8080, 5353, 7000, 50587])
    #expect(ports.first { $0.localPort == 8080 }?.service == "HTTP")
    #expect(ports.first { $0.localPort == 5353 }?.service == "mDNS")
    #expect(ports.first { $0.processName == "Remolo Helper" } != nil)
}

@Test("IORegistry expõe nome e utilização da GPU")
func gpuParsing() throws {
    let output = """
    "model" = "Apple M1"
    "PerformanceStatistics" = {"Renderer Utilization %"=25,"Tiler Utilization %"=27,"Device Utilization %"=27,"Alloc system memory"=847560704,"In use system memory"=414744576}
    """
    let gpu = try #require(SystemMonitorMath.gpuMetrics(fromIORegistry: output))
    #expect(gpu.name == "Apple M1")
    #expect(gpu.devicePercent == 27)
    #expect(gpu.rendererPercent == 25)
    #expect(gpu.tilerPercent == 27)
    #expect(gpu.allocatedBytes == 847560704)
    #expect(gpu.usedBytes == 414744576)
}

@Test("PS expõe só processos do usuário, fora do Arena e com uso medido")
func processesParsing() {
    let output = """
      UID   PID  PPID  %CPU %MEM    RSS COMM             ARGS
      501  100     1   3.2  1.2  8192 /Applications/O /Applications/Obsidian.app/Contents/MacOS/Obsidian
      501  200     1   0.0  0.8 40960 /Applications/Re /Applications/Resolume Arena/Arena.app/Contents/MacOS/Arena
        0  300     1   9.0  2.0 65536 /usr/libexec/C /usr/libexec/CryptoTokenKit
      501  400     1   0.0  0.0     0 /usr/bin/true /usr/bin/true
      501  500     1  20.0  2.4 98304 /bin/ps /bin/ps -axo uid,pid,ppid,pcpu,pmem,rss,comm,args
    """

    let processos = SystemMonitorMath.processes(fromPS: output, currentUID: 501, currentPID: 500)
    #expect(processos.map(\.pid) == [100])
    #expect(processos.first?.userID == 501)
    #expect(processos.first?.cpuPercent == 3.2)
    #expect(processos.first?.memoryBytes == 8_388_608)
}

@MainActor
@Test("Modelo de sistema calcula throughput de rede entre polls e sonda NDI")
func systemMonitorModelNetwork() async throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let first = NetworkSample(capturedAt: base, interfaces: [
        monitorCounters(name: "en0", isLoopback: false, bytesIn: 1_000, bytesOut: 100),
        monitorCounters(name: "lo0", isLoopback: true, bytesIn: 50_000, bytesOut: 50_000),
    ])
    let second = NetworkSample(capturedAt: base.addingTimeInterval(1), interfaces: [
        monitorCounters(name: "en0", isLoopback: false, bytesIn: 2_000, bytesOut: 300),
        monitorCounters(name: "lo0", isLoopback: true, bytesIn: 100_000, bytesOut: 100_000),
    ])
    let model = SystemMonitorModel(
        source: StubSystemSource(),
        networkSource: StubNetworkSource(samples: [first, second]),
        ndiProbe: NDIProbe(candidates: []))

    await model.refresh()
    #expect(model.networkTotals == nil)

    await model.refresh()
    let totals = try #require(model.networkTotals)
    #expect(totals.bytesInPerSecond == 1_000)
    #expect(totals.bytesOutPerSecond == 200)
    #expect(totals.bytesInSinceBoot == 2_000)
    #expect(totals.bytesOutSinceBoot == 300)
    #expect(model.network?.interfaces.first(where: { $0.name == "lo0" }) != nil)
    #expect(model.ndi?.isAvailable == false)
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

    func cpuLoad() async throws -> CPULoad? { nil }
    func gpuMetrics() async throws -> GPUMetrics? { nil }
    func ports() async throws -> [SystemPortEndpoint] { [] }

    func processes() async throws -> [SystemProcessInfo] { [] }

    func memoryUsage() async throws -> MemoryUsage {
        MemoryUsage(totalBytes: 1, usedBytes: 0, activeBytes: 0, wiredBytes: 0, compressorBytes: 0, freeBytes: 1)
    }
}

private actor StubNetworkSource: NetworkMonitorSource {
    private var samples: [NetworkSample]

    init(samples: [NetworkSample]) {
        self.samples = samples
    }

    func sample() async throws -> NetworkSample {
        guard !samples.isEmpty else { throw NetworkMonitorError.interfacesUnavailable }
        return samples.removeFirst()
    }
}
