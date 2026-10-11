import CoreMIDI
import Foundation

public struct MIDISourceState: Sendable, Equatable, Codable {
    public let uniqueID: Int32
    public let name: String
    public let manufacturer: String?
    public let packetCount: UInt64
    public let lastMessageAt: Date?

    public init(
        uniqueID: Int32,
        name: String,
        manufacturer: String?,
        packetCount: UInt64,
        lastMessageAt: Date?
    ) {
        self.uniqueID = uniqueID
        self.name = name
        self.manufacturer = manufacturer
        self.packetCount = packetCount
        self.lastMessageAt = lastMessageAt
    }
}

public struct MIDIStatus: Sendable, Equatable, Codable {
    public let isAvailable: Bool
    public let error: String?
    public let sources: [MIDISourceState]
}

public protocol MIDIMonitorSource: Sendable {
    func status() async -> MIDIStatus
}

final class MIDIPacketCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int32: UInt64] = [:]
    private var lastAt: [Int32: Date] = [:]

    func record(uniqueID: Int32, packets: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        counts[uniqueID, default: 0] += packets
        lastAt[uniqueID] = Date()
    }

    func snapshot(_ uniqueID: Int32) -> (count: UInt64, lastAt: Date?) {
        lock.lock()
        defer { lock.unlock() }
        return (counts[uniqueID] ?? 0, lastAt[uniqueID])
    }
}

public actor CoreMIDIMonitorSource: MIDIMonitorSource {
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private let counter = MIDIPacketCounter()
    private var connectedUniqueIDs: Set<Int32> = []
    private nonisolated(unsafe) var connectionRefPointers: [UnsafeMutablePointer<Int32>] = []
    private var error: String?

    public init() {
        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("Resolux MIDI Monitor" as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            self.error = "CoreMIDI client: OSStatus \(clientStatus)"
            return
        }
        self.client = client
        var port = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithBlock(
            self.client,
            "Resolux MIDI Monitor" as CFString,
            &port
        ) { [counter] packetList, connectionRefCon in
            guard let connectionRefCon else { return }
            let uniqueID = connectionRefCon.load(as: Int32.self)
            let list = packetList.pointee
            let lengthOffset = MemoryLayout.offset(of: \MIDIPacket.length) ?? 8
            let dataOffset = MemoryLayout.offset(of: \MIDIPacket.data) ?? 10
            var packetOffset = MemoryLayout<UInt32>.size
            for _ in 0..<list.numPackets {
                counter.record(uniqueID: uniqueID, packets: 1)
                let length = UnsafeRawPointer(packetList)
                    .advanced(by: packetOffset + lengthOffset)
                    .load(as: UInt16.self)
                packetOffset = (packetOffset + dataOffset + Int(length) + 3) & ~3
            }
        }
        guard portStatus == noErr else {
            self.error = "CoreMIDI porta de entrada: OSStatus \(portStatus)"
            return
        }
        self.inputPort = port
    }

    deinit {
        for pointer in connectionRefPointers {
            pointer.deallocate()
        }
    }

    public func status() -> MIDIStatus {
        syncConnections()
        var sources: [MIDISourceState] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            var uniqueID: MIDIUniqueID = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr,
                  uniqueID != 0
            else { continue }
            let snapshot = counter.snapshot(uniqueID)
            sources.append(
                MIDISourceState(
                    uniqueID: uniqueID,
                    name: stringProperty(endpoint, kMIDIPropertyName) ?? "MIDI \(uniqueID)",
                    manufacturer: stringProperty(endpoint, kMIDIPropertyManufacturer),
                    packetCount: snapshot.count,
                    lastMessageAt: snapshot.lastAt
                )
            )
        }
        return MIDIStatus(
            isAvailable: error == nil,
            error: error,
            sources: sources.sorted { $0.uniqueID < $1.uniqueID }
        )
    }

    private func syncConnections() {
        guard inputPort != 0 else { return }
        var current: Set<Int32> = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            var uniqueID: MIDIUniqueID = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr,
                  uniqueID != 0
            else { continue }
            current.insert(uniqueID)
            guard !connectedUniqueIDs.contains(uniqueID) else { continue }
            let refCon = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            refCon.pointee = uniqueID
            if MIDIPortConnectSource(inputPort, endpoint, refCon) == noErr {
                connectionRefPointers.append(refCon)
                connectedUniqueIDs.insert(uniqueID)
            } else {
                refCon.deallocate()
            }
        }
        connectedUniqueIDs.formIntersection(current)
    }

    private func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
