import Darwin
import Foundation

public struct SystemHardware: Sendable, Equatable, Codable {
    public let cpuModel: String
    public let coreCount: Int
    public let physicalMemoryBytes: UInt64

    public init(cpuModel: String, coreCount: Int, physicalMemoryBytes: UInt64) {
        self.cpuModel = cpuModel
        self.coreCount = coreCount
        self.physicalMemoryBytes = physicalMemoryBytes
    }
}

public struct CPULoad: Sendable, Equatable, Codable {
    public let usagePercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(usagePercent: Double, userPercent: Double, systemPercent: Double, idlePercent: Double) {
        self.usagePercent = usagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }
}

public struct MemoryUsage: Sendable, Equatable, Codable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let activeBytes: UInt64
    public let wiredBytes: UInt64
    public let compressorBytes: UInt64
    public let freeBytes: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, activeBytes: UInt64, wiredBytes: UInt64, compressorBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.activeBytes = activeBytes
        self.wiredBytes = wiredBytes
        self.compressorBytes = compressorBytes
        self.freeBytes = freeBytes
    }
}

public struct GPUMetrics: Sendable, Equatable, Codable {
    public let name: String?
    public let devicePercent: Int?
    public let rendererPercent: Int?
    public let tilerPercent: Int?
    public let allocatedBytes: Int?
    public let usedBytes: Int?

    public init(
        name: String?,
        devicePercent: Int?,
        rendererPercent: Int?,
        tilerPercent: Int?,
        allocatedBytes: Int?,
        usedBytes: Int?
    ) {
        self.name = name
        self.devicePercent = devicePercent
        self.rendererPercent = rendererPercent
        self.tilerPercent = tilerPercent
        self.allocatedBytes = allocatedBytes
        self.usedBytes = usedBytes
    }
}

public struct SystemPortEndpoint: Identifiable, Sendable, Equatable, Codable {
    public let localAddress: String
    public let localPort: Int
    public let transport: String
    public let addressFamily: String
    public let processName: String
    public let processID: Int
    public let service: String

    public var id: String { "\(transport)-\(addressFamily)-\(localAddress):\(localPort)-\(processID)" }
    public var protocolLabel: String { "\(transport) · \(service)" }

    public init(
        localAddress: String,
        localPort: Int,
        transport: String,
        addressFamily: String,
        processName: String,
        processID: Int,
        service: String
    ) {
        self.localAddress = localAddress
        self.localPort = localPort
        self.transport = transport
        self.addressFamily = addressFamily
        self.processName = processName
        self.processID = processID
        self.service = service
    }
}

public struct CPUTicks: Sendable, Equatable {
    public let user: Int
    public let system: Int
    public let idle: Int
    public let nice: Int

    public init(user: Int, system: Int, idle: Int, nice: Int) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var active: Int { user + system + nice }
    public var total: Int { active + idle }
}

public protocol SystemMonitorSource: Sendable {
    func hardware() async throws -> SystemHardware
    func cpuLoad() async throws -> CPULoad?
    func memoryUsage() async throws -> MemoryUsage
    func gpuMetrics() async throws -> GPUMetrics?
    func ports() async throws -> [SystemPortEndpoint]
}

public enum SystemMonitorMath {
    public static func cpuLoad(current: CPUTicks, previous: CPUTicks) -> CPULoad? {
        let user = max(0, current.user - previous.user)
        let system = max(0, current.system - previous.system)
        let idle = max(0, current.idle - previous.idle)
        let nice = max(0, current.nice - previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }

        let userPercent = Double(user + nice) * 100 / Double(total)
        let systemPercent = Double(system) * 100 / Double(total)
        let idlePercent = Double(idle) * 100 / Double(total)
        let usage = max(0, min(100, userPercent + systemPercent))
        return CPULoad(
            usagePercent: usage,
            userPercent: userPercent,
            systemPercent: systemPercent,
            idlePercent: idlePercent)
    }

    public static func ports(fromLSOF output: String, transport: String) -> [SystemPortEndpoint] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard fields.count >= 9 else { return nil }

            let processName = String(fields[0])
                .replacingOccurrences(of: "\\x20", with: " ")
            guard let processID = Int(fields[1]) else { return nil }
            let addressFamily = String(fields[3])
            let endpoint = String(fields[8])
            guard let parsed = parseEndpoint(endpoint), parsed.port > 0 else { return nil }

            return SystemPortEndpoint(
                localAddress: parsed.address,
                localPort: parsed.port,
                transport: transport,
                addressFamily: addressFamily,
                processName: processName,
                processID: processID,
                service: serviceLabel(port: parsed.port, processName: processName))
        }
    }

    public static func serviceLabel(port: Int, processName: String) -> String {
        switch port {
        case 22: "SSH"
        case 53: "DNS"
        case 80, 8000, 8080: "HTTP"
        case 123: "NTP"
        case 443, 8443: "HTTPS"
        case 5900: "VNC"
        case 5353: "mDNS"
        case 5960: "NDI Video"
        case 5961: "NDI Control"
        case 7000, 7001: "AirPlay"
        case 11434: "Ollama"
        case 1976: "Apple FM"
        case 4731: "MCP"
        default:
            processName.contains("Arena") ? "Arena" : "Desconhecido"
        }
    }

    public static func gpuMetrics(fromIORegistry output: String) -> GPUMetrics? {
        func value(forKey key: String) -> String? {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = "\"\(escapedKey)\"\\s*=\\s*(?:\"([^\"]+)\"|(\\d+))"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  let range = Range(match.range(at: 1), in: output) ?? Range(match.range(at: 2), in: output) else {
                return nil
            }
            return String(output[range])
        }

        let name = value(forKey: "model")
        let device = value(forKey: "Device Utilization %").flatMap(Int.init)
        let renderer = value(forKey: "Renderer Utilization %").flatMap(Int.init)
        let tiler = value(forKey: "Tiler Utilization %").flatMap(Int.init)
        let allocated = value(forKey: "Alloc system memory").flatMap(Int.init)
        let used = value(forKey: "In use system memory").flatMap(Int.init)
        guard name != nil || device != nil || renderer != nil || tiler != nil else { return nil }

        return GPUMetrics(
            name: name,
            devicePercent: device,
            rendererPercent: renderer,
            tilerPercent: tiler,
            allocatedBytes: allocated,
            usedBytes: used)
    }

    static func parseEndpoint(_ raw: String) -> (address: String, port: Int)? {
        var endpoint = raw
        if let arrow = endpoint.range(of: "->") {
            endpoint = String(endpoint[..<arrow.lowerBound])
        }
        if let listenSuffix = endpoint.range(of: " (LISTEN)") {
            endpoint = String(endpoint[..<listenSuffix.lowerBound])
        }

        if endpoint.contains("]:") {
            guard let closeBracket = endpoint.firstIndex(of: "]") else { return nil }
            let address = String(endpoint[endpoint.index(after: endpoint.startIndex)..<closeBracket])
            let portStart = endpoint.index(after: closeBracket)
            guard endpoint[portStart] == ":" else { return nil }
            let portStartAfterColon = endpoint.index(after: portStart)
            guard let port = Int(endpoint[portStartAfterColon...]) else { return nil }
            return (address, port)
        }

        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let address = String(endpoint[..<colon])
        guard let port = Int(endpoint[endpoint.index(after: colon)...]) else { return nil }
        return (address.isEmpty ? "*" : address, port)
    }
}

public actor MachSystemMonitorSource: SystemMonitorSource {
    private var previousTicks: CPUTicks?

    public init() {}

    public func hardware() async throws -> SystemHardware {
        SystemHardware(
            cpuModel: Self.sysctlString("machdep.cpu.brand_string") ?? "CPU Apple",
            coreCount: Int(ProcessInfo.processInfo.processorCount),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    public func cpuLoad() async throws -> CPULoad? {
        let ticks = try Self.processorTicks()
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }
        return SystemMonitorMath.cpuLoad(current: ticks, previous: previous)
    }

    public func memoryUsage() async throws -> MemoryUsage {
        try Self.memory()
    }

    public func gpuMetrics() async throws -> GPUMetrics? {
        let output = try Self.runCommand("/usr/sbin/ioreg", ["-r", "-d", "1", "-w0", "-c", "IOAccelerator"])
        return SystemMonitorMath.gpuMetrics(fromIORegistry: output)
    }

    public func ports() async throws -> [SystemPortEndpoint] {
        let tcp = try Self.runCommand("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN"])
        let udp = try Self.runCommand("/usr/sbin/lsof", ["-nP", "+c0", "-iUDP"])
        return (SystemMonitorMath.ports(fromLSOF: tcp, transport: "TCP")
            + SystemMonitorMath.ports(fromLSOF: udp, transport: "UDP"))
            .sorted { $0.localPort < $1.localPort }
    }

    private static func processorTicks() throws -> CPUTicks {
        var coreCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var tickCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &processorInfo, &tickCount)
        guard result == KERN_SUCCESS, let info = processorInfo, coreCount > 0 else {
            throw MonitorError.cpuUnavailable
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(tickCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var user = 0
        var system = 0
        var idle = 0
        var nice = 0
        for core in 0..<Int(coreCount) {
            let offset = core * Int(CPU_STATE_MAX)
            user += Int(info[offset + Int(CPU_STATE_USER)])
            system += Int(info[offset + Int(CPU_STATE_SYSTEM)])
            idle += Int(info[offset + Int(CPU_STATE_IDLE)])
            nice += Int(info[offset + Int(CPU_STATE_NICE)])
        }
        return CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private static func memory() throws -> MemoryUsage {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            UInt32(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<natural_t>.stride))
        var pageSize: vm_size_t = 0
        let host = mach_host_self()
        let pointer = withUnsafeMutablePointer(to: &statistics) { statisticsPointer in
            UnsafeMutableRawPointer(statisticsPointer).assumingMemoryBound(to: integer_t.self)
        }
        let result = host_statistics64(host, HOST_VM_INFO64, pointer, &count)
        let pageResult = host_page_size(host, &pageSize)
        guard result == KERN_SUCCESS, pageResult == KERN_SUCCESS, pageSize > 0 else {
            throw MonitorError.memoryUnavailable
        }

        let page = UInt64(pageSize)
        let active = UInt64(statistics.active_count) * page
        let wired = UInt64(statistics.wire_count) * page
        let compressor = UInt64(statistics.compressor_page_count) * page
        let free = UInt64(statistics.free_count) * page
        let total = ProcessInfo.processInfo.physicalMemory
        return MemoryUsage(
            totalBytes: total,
            usedBytes: active + wired + compressor,
            activeBytes: active,
            wiredBytes: wired,
            compressorBytes: compressor,
            freeBytes: free)
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MonitorError.commandFailed(executable)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}

public enum MonitorError: Error, LocalizedError {
    case cpuUnavailable
    case memoryUnavailable
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cpuUnavailable: "CPU indisponível no host."
        case .memoryUnavailable: "Memória indisponível no host."
        case .commandFailed(let command): "Comando de leitura falhou: \(command)"
        }
    }
}
