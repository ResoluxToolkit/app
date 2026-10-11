import Darwin
import Foundation

public struct NetworkInterfaceCounters: Sendable, Equatable, Codable {
    public let name: String
    public let macAddress: String?
    public private(set) var addresses: [String]
    public let isUp: Bool
    public let isLoopback: Bool
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let packetsIn: UInt64
    public let packetsOut: UInt64
    public let errorsIn: UInt64
    public let errorsOut: UInt64
    public let dropsIn: UInt64

    public init(
        name: String,
        macAddress: String?,
        addresses: [String],
        isUp: Bool,
        isLoopback: Bool,
        bytesIn: UInt64,
        bytesOut: UInt64,
        packetsIn: UInt64,
        packetsOut: UInt64,
        errorsIn: UInt64,
        errorsOut: UInt64,
        dropsIn: UInt64
    ) {
        self.name = name
        self.macAddress = macAddress
        self.addresses = addresses
        self.isUp = isUp
        self.isLoopback = isLoopback
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.packetsIn = packetsIn
        self.packetsOut = packetsOut
        self.errorsIn = errorsIn
        self.errorsOut = errorsOut
        self.dropsIn = dropsIn
    }
}

private struct NetworkInterfaceAccumulator {
    var name: String
    var macAddress: String?
    var addresses: [String] = []
    var isUp: Bool
    var isLoopback: Bool
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var packetsIn: UInt64 = 0
    var packetsOut: UInt64 = 0
    var errorsIn: UInt64 = 0
    var errorsOut: UInt64 = 0
    var dropsIn: UInt64 = 0

    func makeCounters() -> NetworkInterfaceCounters {
        NetworkInterfaceCounters(
            name: name,
            macAddress: macAddress,
            addresses: addresses,
            isUp: isUp,
            isLoopback: isLoopback,
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            packetsIn: packetsIn,
            packetsOut: packetsOut,
            errorsIn: errorsIn,
            errorsOut: errorsOut,
            dropsIn: dropsIn)
    }
}

public struct NetworkSample: Sendable, Equatable, Codable {
    public let capturedAt: Date
    public let interfaces: [NetworkInterfaceCounters]

    public init(capturedAt: Date, interfaces: [NetworkInterfaceCounters]) {
        self.capturedAt = capturedAt
        self.interfaces = interfaces
    }
}

public struct NetworkThroughput: Sendable, Equatable, Codable {
    public let name: String
    public let bytesInPerSecond: Double
    public let bytesOutPerSecond: Double
    public let packetsInPerSecond: Double
    public let packetsOutPerSecond: Double

    public init(
        name: String,
        bytesInPerSecond: Double,
        bytesOutPerSecond: Double,
        packetsInPerSecond: Double,
        packetsOutPerSecond: Double
    ) {
        self.name = name
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
        self.packetsInPerSecond = packetsInPerSecond
        self.packetsOutPerSecond = packetsOutPerSecond
    }
}

public struct NetworkTotals: Sendable, Equatable, Codable {
    public let bytesInPerSecond: Double
    public let bytesOutPerSecond: Double
    public let packetsInPerSecond: Double
    public let packetsOutPerSecond: Double
    public let bytesInSinceBoot: UInt64
    public let bytesOutSinceBoot: UInt64

    public init(
        bytesInPerSecond: Double,
        bytesOutPerSecond: Double,
        packetsInPerSecond: Double,
        packetsOutPerSecond: Double,
        bytesInSinceBoot: UInt64,
        bytesOutSinceBoot: UInt64
    ) {
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
        self.packetsInPerSecond = packetsInPerSecond
        self.packetsOutPerSecond = packetsOutPerSecond
        self.bytesInSinceBoot = bytesInSinceBoot
        self.bytesOutSinceBoot = bytesOutSinceBoot
    }
}

public protocol NetworkMonitorSource: Sendable {
    func sample() async throws -> NetworkSample
}

public enum NetworkMonitorMath {
    public static func delta(current: UInt64, previous: UInt64) -> UInt64 {
        guard current != previous else { return 0 }
        if current > previous { return current - previous }
        return current &+ (UInt64(UInt32.max) &+ 1) &- previous
    }

    public static func throughput(current: NetworkSample, previous: NetworkSample) -> [NetworkThroughput] {
        let elapsed = current.capturedAt.timeIntervalSince(previous.capturedAt)
        guard elapsed > 0 else { return [] }

        let previousByName = Dictionary(uniqueKeysWithValues: previous.interfaces.map { ($0.name, $0) })
        return current.interfaces.compactMap { currentInterface in
            guard let previousInterface = previousByName[currentInterface.name] else { return nil }
            return NetworkThroughput(
                name: currentInterface.name,
                bytesInPerSecond: Double(delta(current: currentInterface.bytesIn, previous: previousInterface.bytesIn)) / elapsed,
                bytesOutPerSecond: Double(delta(current: currentInterface.bytesOut, previous: previousInterface.bytesOut)) / elapsed,
                packetsInPerSecond: Double(delta(current: currentInterface.packetsIn, previous: previousInterface.packetsIn)) / elapsed,
                packetsOutPerSecond: Double(delta(current: currentInterface.packetsOut, previous: previousInterface.packetsOut)) / elapsed)
        }
    }

    public static func totals(from sample: NetworkSample, throughputs: [NetworkThroughput]) -> NetworkTotals {
        let activeNames = Set(
            sample.interfaces
                .filter { $0.isUp && !$0.isLoopback }
                .map(\.name))
        let activeThroughputs = throughputs.filter { activeNames.contains($0.name) }
        let activeInterfaces = sample.interfaces.filter { activeNames.contains($0.name) }

        func sum(_ keyPath: KeyPath<NetworkThroughput, Double>) -> Double {
            activeThroughputs.reduce(0) { $0 + $1[keyPath: keyPath] }
        }

        return NetworkTotals(
            bytesInPerSecond: sum(\.bytesInPerSecond),
            bytesOutPerSecond: sum(\.bytesOutPerSecond),
            packetsInPerSecond: sum(\.packetsInPerSecond),
            packetsOutPerSecond: sum(\.packetsOutPerSecond),
            bytesInSinceBoot: activeInterfaces.reduce(0) { $0 + $1.bytesIn },
            bytesOutSinceBoot: activeInterfaces.reduce(0) { $0 + $1.bytesOut })
    }
}

public enum NetworkMonitorError: Error, LocalizedError {
    case interfacesUnavailable

    public var errorDescription: String? {
        "Interfaces de rede indisponíveis no host."
    }
}

public actor GetIfAddrsNetworkMonitorSource: NetworkMonitorSource {
    public init() {}

    public func sample() async throws -> NetworkSample {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            throw NetworkMonitorError.interfacesUnavailable
        }
        defer { freeifaddrs(first) }

        var byName: [String: NetworkInterfaceAccumulator] = [:]
        var order: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let sockaddrPointer = entry.ifa_addr else { continue }

            let name = String(cString: entry.ifa_name)
            if byName[name] == nil {
                order.append(name)
                byName[name] = NetworkInterfaceAccumulator(
                    name: name,
                    macAddress: nil,
                    isUp: (entry.ifa_flags & UInt32(IFF_UP)) != 0,
                    isLoopback: (entry.ifa_flags & UInt32(IFF_LOOPBACK)) != 0)
            }

            var interface = byName[name]!
            switch Int32(sockaddrPointer.pointee.sa_family) {
            case AF_LINK:
                let link = sockaddrPointer.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                interface.macAddress = Self.macAddress(from: link, at: sockaddrPointer)
                if let data = entry.ifa_data {
                    let counters = UnsafeRawPointer(data).bindMemory(to: if_data.self, capacity: 1).pointee
                    interface.bytesIn = UInt64(counters.ifi_ibytes)
                    interface.bytesOut = UInt64(counters.ifi_obytes)
                    interface.packetsIn = UInt64(counters.ifi_ipackets)
                    interface.packetsOut = UInt64(counters.ifi_opackets)
                    interface.errorsIn = UInt64(counters.ifi_ierrors)
                    interface.errorsOut = UInt64(counters.ifi_oerrors)
                    interface.dropsIn = UInt64(counters.ifi_iqdrops)
                }
            case AF_INET, AF_INET6:
                if let address = Self.address(from: sockaddrPointer) {
                    interface.addresses.append(address)
                }
            default:
                break
            }
            byName[name] = interface
        }

        let interfaces = order.compactMap { byName[$0]?.makeCounters() }.sorted { $0.name < $1.name }
        return NetworkSample(capturedAt: Date(), interfaces: interfaces)
    }

    static func macAddress(from link: sockaddr_dl, at pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        let start = 8 + Int(link.sdl_nlen)
        let end = start + Int(link.sdl_alen)
        guard link.sdl_alen > 0, Int(link.sdl_len) >= end else { return nil }
        let raw = UnsafeRawBufferPointer(start: pointer, count: Int(link.sdl_len))
        return (start..<end)
            .map { String(format: "%02x", raw[$0]) }
            .joined(separator: ":")
    }

    static func address(from pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            let socket = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in.self).pointee
            return Self.string(from: socket.sin_addr, family: AF_INET)
        case AF_INET6:
            let socket = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in6.self).pointee
            return Self.string(from: socket.sin6_addr, family: AF_INET6)
        default:
            return nil
        }
    }

    private static func string(from address: in_addr, family: Int32) -> String? {
        var value = address
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, &value, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return string(fromCString: buffer)
    }

    private static func string(from address: in6_addr, family: Int32) -> String? {
        var value = address
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, &value, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return string(fromCString: buffer)
    }

    private static func string(fromCString buffer: [CChar]) -> String {
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public struct NDIDiscoveredSource: Sendable, Equatable, Codable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct NDIStatus: Sendable, Equatable, Codable {
    public let isAvailable: Bool
    public let libraryPath: String?
    public let version: String?
    public let sources: [NDIDiscoveredSource]

    public init(isAvailable: Bool, libraryPath: String?, version: String?, sources: [NDIDiscoveredSource]) {
        self.isAvailable = isAvailable
        self.libraryPath = libraryPath
        self.version = version
        self.sources = sources
    }
}

public actor NDIProbe {
    public static let defaultLibraryCandidates: [String] = [
        "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
        "/Applications/Resolume Arena/libndi.dylib",
        NSHomeDirectory() + "/Developer/NDI-SDK/lib/macOS/libndi.dylib",
    ]

    private let candidates: [String]
    private var handle: UnsafeMutableRawPointer?
    private var loadedPath: String?
    private var isInitialized = false

    public init(candidates: [String] = defaultLibraryCandidates) {
        self.candidates = candidates
    }

    public func status(discoveryTimeout: TimeInterval = 0.3) -> NDIStatus {
        guard let (handle, path) = library() else {
            return NDIStatus(isAvailable: false, libraryPath: nil, version: nil, sources: [])
        }
        let version = Self.version(from: handle)
        let sources = Self.discover(from: handle, discoveryTimeout: discoveryTimeout)
        return NDIStatus(isAvailable: true, libraryPath: path, version: version, sources: sources)
    }

    private func library() -> (handle: UnsafeMutableRawPointer, path: String)? {
        if let handle, let loadedPath {
            return (handle, loadedPath)
        }
        for candidate in candidates {
            if let handle = dlopen(candidate, RTLD_LAZY | RTLD_LOCAL) {
                self.handle = handle
                self.loadedPath = candidate
                if !isInitialized, let initialize: NDIlibInitialize = Self.symbol(handle, "NDIlib_initialize") {
                    isInitialized = initialize()
                }
                return (handle, candidate)
            }
        }
        return nil
    }

    private static func version(from handle: UnsafeMutableRawPointer) -> String? {
        guard let version: NDIlibVersion = symbol(handle, "NDIlib_version") else { return nil }
        return version().flatMap { String(cString: $0) }
    }

    private static func discover(from handle: UnsafeMutableRawPointer, discoveryTimeout: TimeInterval) -> [NDIDiscoveredSource] {
        let milliseconds = UInt32(max(0, min(5_000, discoveryTimeout * 1_000)))
        guard let create: NDIlibFindCreate = symbol(handle, "NDIlib_find_create_v2"),
              let currentSources: NDIlibFindGetCurrentSources = symbol(handle, "NDIlib_find_get_current_sources"),
              let destroy: NDIlibFindDestroy = symbol(handle, "NDIlib_find_destroy"),
              let find = create(nil) else { return [] }
        if let wait: NDIlibFindWaitForSources = symbol(handle, "NDIlib_find_wait_for_sources") {
            _ = wait(find, milliseconds)
        } else {
            Thread.sleep(forTimeInterval: discoveryTimeout)
        }

        defer { destroy(find) }
        var count: UInt32 = 0
        guard let sourcesPointer = currentSources(find, &count), count > 0 else { return [] }

        let sources = UnsafeRawPointer(sourcesPointer).bindMemory(to: NDILibSource.self, capacity: Int(count))
        return (0..<Int(count)).compactMap { index in
            guard let name = sources[index].name else { return nil }
            return NDIDiscoveredSource(
                name: cString(name),
                address: sources[index].url.map { cString($0) } ?? "")
        }
    }

    private static func cString(_ pointer: UnsafePointer<CChar>) -> String {
        let bytes = UnsafeBufferPointer(start: pointer, count: Int(strlen(pointer))).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}

private typealias NDIlibVersion = @convention(c) () -> UnsafePointer<CChar>?
private typealias NDIlibInitialize = @convention(c) () -> Bool
private typealias NDIlibFindCreate = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
private typealias NDIlibFindWaitForSources = @convention(c) (OpaquePointer, UInt32) -> Bool
private typealias NDIlibFindGetCurrentSources = @convention(c) (OpaquePointer, UnsafeMutablePointer<UInt32>) -> UnsafeMutableRawPointer?
private typealias NDIlibFindDestroy = @convention(c) (OpaquePointer) -> Void
private struct NDILibSource {
    let name: UnsafePointer<CChar>?
    let url: UnsafePointer<CChar>?
}
