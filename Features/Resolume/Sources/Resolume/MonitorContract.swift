import Foundation

public struct MonitorContract: Sendable, Equatable, Codable {
    public static let version = 1

    public var contractVersion: Int
    public var capturedAt: Date
    public var hardware: SystemHardware?
    public var cpu: CPULoad?
    public var memory: MemoryUsage?
    public var gpu: GPUMetrics?
    public var ports: [SystemPortEndpoint]
    public var processes: [SystemProcessInfo]
    public var network: NetworkSample?
    public var throughputs: [NetworkThroughput]
    public var networkTotals: NetworkTotals?
    public var ndi: NDIStatus?
    public var midi: MIDIStatus?
    public var artNet: ArtNetPollResult?
    public var captureDevices: [CaptureDeviceInfo]
    public var audioDevices: [AudioDeviceInfo]
    public var displays: [DisplayInfo]

    public init(
        capturedAt: Date,
        contractVersion: Int = MonitorContract.version,
        hardware: SystemHardware? = nil,
        cpu: CPULoad? = nil,
        memory: MemoryUsage? = nil,
        gpu: GPUMetrics? = nil,
        ports: [SystemPortEndpoint] = [],
        processes: [SystemProcessInfo] = [],
        network: NetworkSample? = nil,
        throughputs: [NetworkThroughput] = [],
        networkTotals: NetworkTotals? = nil,
        ndi: NDIStatus? = nil,
        midi: MIDIStatus? = nil,
        artNet: ArtNetPollResult? = nil,
        captureDevices: [CaptureDeviceInfo] = [],
        audioDevices: [AudioDeviceInfo] = [],
        displays: [DisplayInfo] = []
    ) {
        self.contractVersion = contractVersion
        self.capturedAt = capturedAt
        self.hardware = hardware
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.ports = ports
        self.processes = processes
        self.network = network
        self.throughputs = throughputs
        self.networkTotals = networkTotals
        self.ndi = ndi
        self.midi = midi
        self.artNet = artNet
        self.captureDevices = captureDevices
        self.audioDevices = audioDevices
        self.displays = displays
    }

    public static func json(from contract: MonitorContract) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contract)
    }

    public static func decode(from data: Data) throws -> MonitorContract {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MonitorContract.self, from: data)
    }
}
