import Foundation

public protocol NDIMonitorSource: Sendable {
    func status() async -> NDIStatus
}

extension NDIProbe: NDIMonitorSource {
    public func status() async -> NDIStatus {
        await status(discoveryTimeout: 0.3)
    }
}

public protocol ArtNetMonitorSource: Sendable {
    func poll() async -> ArtNetPollResult
}

extension ArtNetPollProbe: ArtNetMonitorSource {
    public func poll() async -> ArtNetPollResult {
        await poll(broadcast: true)
    }
}

public protocol DisplayMonitorSource: Sendable {
    func displays() async -> [DisplayInfo]
}

public actor CoreGraphicsDisplaySource: DisplayMonitorSource {
    public init() {}

    public func displays() async -> [DisplayInfo] {
        DisplaySource.displays()
    }
}

public actor MonitorHub {
    private let systemSource: any SystemMonitorSource
    private let networkSource: any NetworkMonitorSource
    private let ndiSource: any NDIMonitorSource
    private let midiSource: any MIDIMonitorSource
    private let artNetSource: any ArtNetMonitorSource
    private let captureSource: any CaptureDeviceSource
    private let audioSource: any AudioDeviceSource
    private let displaySource: any DisplayMonitorSource
    private let pollInterval: TimeInterval

    private var clientRefs = 0
    private var pollTask: Task<Void, Never>?
    private var latest: MonitorContract?
    private var previousNetwork: NetworkSample?
    private var cycle = 0

    public init(
        systemSource: any SystemMonitorSource = MachSystemMonitorSource(),
        networkSource: any NetworkMonitorSource = GetIfAddrsNetworkMonitorSource(),
        ndiSource: any NDIMonitorSource = NDIProbe(),
        midiSource: any MIDIMonitorSource = CoreMIDIMonitorSource(),
        artNetSource: any ArtNetMonitorSource = ArtNetPollProbe(),
        captureSource: any CaptureDeviceSource = AVCaptureDeviceProbe(),
        audioSource: any AudioDeviceSource = CoreAudioDeviceSource(),
        displaySource: any DisplayMonitorSource = CoreGraphicsDisplaySource(),
        pollInterval: TimeInterval = 1.0
    ) {
        self.systemSource = systemSource
        self.networkSource = networkSource
        self.ndiSource = ndiSource
        self.midiSource = midiSource
        self.artNetSource = artNetSource
        self.captureSource = captureSource
        self.audioSource = audioSource
        self.displaySource = displaySource
        self.pollInterval = pollInterval
    }

    public var isRunning: Bool { pollTask != nil }

    public func clientCount() -> Int { clientRefs }

    public func attach() async -> MonitorContract {
        clientRefs += 1
        if pollTask == nil {
            await pollOnce()
            pollTask = Task { [weak self] in await self?.pollLoop() }
        }
        return latest ?? MonitorContract(capturedAt: Date())
    }

    public func detach() async {
        clientRefs = max(0, clientRefs - 1)
        if clientRefs == 0 {
            pollTask?.cancel()
            pollTask = nil
            latest = nil
            previousNetwork = nil
            cycle = 0
        }
    }

    public func snapshot() -> MonitorContract? { latest }

    private func pollLoop() async {
        while !Task.isCancelled && clientRefs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            guard !Task.isCancelled && clientRefs > 0 else { break }
            await pollOnce()
        }
    }

    private func pollOnce() async {
        cycle += 1
        var contract = latest ?? MonitorContract(capturedAt: Date())

        if contract.hardware == nil {
            contract.hardware = try? await systemSource.hardware()
        }
        contract.cpu = try? await systemSource.cpuLoad() ?? contract.cpu
        contract.memory = try? await systemSource.memoryUsage()
        contract.gpu = try? await systemSource.gpuMetrics() ?? contract.gpu
        contract.ports = (try? await systemSource.ports()) ?? contract.ports

        if let sample = try? await networkSource.sample() {
            if let previous = previousNetwork {
                let rates = NetworkMonitorMath.throughput(current: sample, previous: previous)
                contract.throughputs = rates
                contract.networkTotals = NetworkMonitorMath.totals(from: sample, throughputs: rates)
            }
            contract.network = sample
            previousNetwork = sample
        }

        contract.midi = await midiSource.status()

        if cycle % 5 == 1 {
            contract.ndi = await ndiSource.status()
            contract.captureDevices = await captureSource.devices()
            contract.audioDevices = await audioSource.devices()
            contract.displays = await displaySource.displays()
        }
        if cycle % 10 == 1 {
            contract.artNet = await artNetSource.poll()
        }

        contract.capturedAt = Date()
        if clientRefs > 0 {
            latest = contract
        }
    }
}
