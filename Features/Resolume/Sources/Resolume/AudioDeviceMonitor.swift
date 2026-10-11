import CoreAudio
import Foundation

public struct AudioDeviceInfo: Sendable, Equatable, Codable {
    public let uid: String
    public let name: String
    public let manufacturer: String?
    public let transportType: String?
    public let isAlive: Bool
    public let isDefaultInput: Bool
    public let isDefaultOutput: Bool
    public let inputStreams: Int
    public let outputStreams: Int
}

public protocol AudioDeviceSource: Sendable {
    func devices() async -> [AudioDeviceInfo]
}

public actor CoreAudioDeviceSource: AudioDeviceSource {
    public init() {}

    public func devices() async -> [AudioDeviceInfo] {
        let defaultInputUID = Self.defaultDeviceUID(kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutputUID = Self.defaultDeviceUID(kAudioHardwarePropertyDefaultOutputDevice)
        return Self.hardwareDeviceIDs()
            .compactMap { deviceID in
                guard let uid = Self.audioObjectString(deviceID, kAudioDevicePropertyDeviceUID) else { return nil }
                let alive = Self.audioObjectUInt32(deviceID, kAudioDevicePropertyDeviceIsAlive) ?? 0
                return AudioDeviceInfo(
                    uid: uid,
                    name: Self.audioObjectString(deviceID, kAudioObjectPropertyName) ?? uid,
                    manufacturer: Self.audioObjectString(deviceID, kAudioObjectPropertyManufacturer),
                    transportType: Self.transportDescription(
                        Self.audioObjectUInt32(deviceID, kAudioDevicePropertyTransportType)
                    ),
                    isAlive: alive != 0,
                    isDefaultInput: uid == defaultInputUID,
                    isDefaultOutput: uid == defaultOutputUID,
                    inputStreams: Self.streamCount(deviceID, scope: kAudioObjectPropertyScopeInput),
                    outputStreams: Self.streamCount(deviceID, scope: kAudioObjectPropertyScopeOutput)
                )
            }
            .sorted { $0.name < $1.name }
    }

    static func hardwareDeviceIDs() -> [AudioDeviceID] {
        var systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func audioObjectString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var object = object
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func audioObjectUInt32(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var object = object
        var value: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func defaultDeviceUID(_ selector: AudioObjectPropertySelector) -> String? {
        var systemObject = AudioObjectID(kAudioObjectSystemObject)
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return audioObjectString(deviceID, kAudioDevicePropertyDeviceUID)
    }

    static func streamCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var device = device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    static func transportDescription(_ transport: UInt32?) -> String? {
        guard let transport else { return nil }
        switch transport {
        case 0x6275696C: return "Built-In"
        case 0x75736220: return "USB"
        case 0x70636920: return "PCI"
        case 0x66697265: return "FireWire"
        case 0x626c7565: return "Bluetooth"
        case 0x626c7530: return "Bluetooth LE"
        case 0x68646d69: return "HDMI"
        case 0x64706f72: return "DisplayPort"
        case 0x61697270: return "AirPlay"
        case 0x76697274: return "Virtual"
        case 0x61676772: return "Aggregate"
        default: return String(format: "0x%08X", transport)
        }
    }
}
