import Foundation
import Testing
@testable import Resolume

@Test("Taxa de rede é delta entre duas amostras")
func networkThroughputDelta() {
    let previous = NetworkSample(capturedAt: Date(timeIntervalSince1970: 1_000), interfaces: [
        counters(name: "en0", bytesIn: 1_000, bytesOut: 500, packetsIn: 10, packetsOut: 5),
    ])
    let current = NetworkSample(capturedAt: Date(timeIntervalSince1970: 1_002), interfaces: [
        counters(name: "en0", bytesIn: 3_000, bytesOut: 1_500, packetsIn: 30, packetsOut: 15),
    ])
    let throughputs = NetworkMonitorMath.throughput(current: current, previous: previous)
    #expect(throughputs.count == 1)
    #expect(throughputs[0].bytesInPerSecond == 1_000)
    #expect(throughputs[0].bytesOutPerSecond == 500)
    #expect(throughputs[0].packetsInPerSecond == 10)
    #expect(throughputs[0].packetsOutPerSecond == 5)
}

@Test("Contador que reinicia é tratado com wrap de 32 bits")
func networkCounterWrap() {
    #expect(NetworkMonitorMath.delta(current: 10, previous: 20) == UInt64(UInt32.max) + 1 - 10)
    #expect(NetworkMonitorMath.delta(current: 30, previous: 20) == 10)
    #expect(NetworkMonitorMath.delta(current: 20, previous: 20) == 0)
}

@Test("Totais ignoram loopback e só somam interfaces ativas")
func networkTotals() {
    let sample = NetworkSample(capturedAt: Date(timeIntervalSince1970: 0), interfaces: [
        counters(name: "lo0", isLoopback: true, isUp: true, bytesIn: 900_000, bytesOut: 900_000),
        counters(name: "en0", bytesIn: 200_000, bytesOut: 50_000),
        counters(name: "gif0", isUp: false, bytesIn: 700_000, bytesOut: 700_000),
    ])
    let throughputs = [
        NetworkThroughput(name: "lo0", bytesInPerSecond: 9_000, bytesOutPerSecond: 9_000, packetsInPerSecond: 0, packetsOutPerSecond: 0),
        NetworkThroughput(name: "en0", bytesInPerSecond: 1_000, bytesOutPerSecond: 200, packetsInPerSecond: 0, packetsOutPerSecond: 0),
        NetworkThroughput(name: "gif0", bytesInPerSecond: 500, bytesOutPerSecond: 500, packetsInPerSecond: 0, packetsOutPerSecond: 0),
    ]
    let totals = NetworkMonitorMath.totals(from: sample, throughputs: throughputs)
    #expect(totals.bytesInPerSecond == 1_000)
    #expect(totals.bytesOutPerSecond == 200)
    #expect(totals.bytesInSinceBoot == 200_000)
    #expect(totals.bytesOutSinceBoot == 50_000)
}

@Test("getifaddrs coleta interfaces reais do host")
func liveGetIfAddrsSample() async throws {
    let source = GetIfAddrsNetworkMonitorSource()
    let first = try await source.sample()
    let loopback = try #require(first.interfaces.first { $0.name == "lo0" })
    #expect(loopback.isLoopback)
    #expect(loopback.isUp)

    let second = try await source.sample()
    let rates = NetworkMonitorMath.throughput(current: second, previous: first)
    #expect(rates.count == second.interfaces.count)
    #expect(rates.allSatisfy { $0.bytesInPerSecond >= 0 })
}

@Test("MAC é extraído do endereço link-layer")
func macAddressParsing() {
    var link = sockaddr_dl()
    link.sdl_len = 20
    link.sdl_family = UInt8(AF_LINK)
    link.sdl_nlen = 0
    link.sdl_alen = 6
    let bytes: [UInt8] = [0xde, 0xad, 0xbe, 0xef, 0x00, 0x01]
    withUnsafeMutableBytes(of: &link) { raw in
        for (offset, byte) in bytes.enumerated() {
            raw[8 + offset] = byte
        }
    }

    var copy = link
    withUnsafeMutablePointer(to: &copy) { pointer in
        let mac = GetIfAddrsNetworkMonitorSource.macAddress(
            from: link,
            at: UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self))
        #expect(mac == "de:ad:be:ef:00:01")
    }
}

@Test("NDI degrada sem biblioteca disponível")
func ndiProbeDegradesWithoutLibrary() async {
    let probe = NDIProbe(candidates: ["/tmp/resolux-nao-existe/libndi.dylib"])
    let status = await probe.status()
    #expect(!status.isAvailable)
    #expect(status.libraryPath == nil)
    #expect(status.version == nil)
    #expect(status.sources.isEmpty)
}

private func counters(
    name: String,
    macAddress: String? = nil,
    isLoopback: Bool = false,
    isUp: Bool = true,
    bytesIn: UInt64 = 0,
    bytesOut: UInt64 = 0,
    packetsIn: UInt64 = 0,
    packetsOut: UInt64 = 0
) -> NetworkInterfaceCounters {
    NetworkInterfaceCounters(
        name: name,
        macAddress: macAddress,
        addresses: [],
        isUp: isUp,
        isLoopback: isLoopback,
        bytesIn: bytesIn,
        bytesOut: bytesOut,
        packetsIn: packetsIn,
        packetsOut: packetsOut,
        errorsIn: 0,
        errorsOut: 0,
        dropsIn: 0)
}
