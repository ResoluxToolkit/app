import AVFoundation
import Foundation

public struct CaptureDeviceInfo: Sendable, Equatable, Codable {
    public let uniqueID: String
    public let name: String
    public let deviceType: String
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let position: String?
    public let isConnected: Bool
}

public protocol CaptureDeviceSource: Sendable {
    func devices() async -> [CaptureDeviceInfo]
}

public actor AVCaptureDeviceProbe: CaptureDeviceSource {
    public init() {}

    public func devices() async -> [CaptureDeviceInfo] {
        AVCaptureDevice.devices()
            .map { device in
                CaptureDeviceInfo(
                    uniqueID: device.uniqueID,
                    name: device.localizedName,
                    deviceType: device.deviceType.rawValue,
                    hasVideo: device.hasMediaType(.video),
                    hasAudio: device.hasMediaType(.audio) || device.hasMediaType(.muxed),
                    position: Self.positionDescription(device.position),
                    isConnected: device.isConnected
                )
            }
            .sorted { $0.name < $1.name }
    }

    private static func positionDescription(_ position: AVCaptureDevice.Position) -> String? {
        switch position {
        case .front: return "frontal"
        case .back: return "traseira"
        default: return nil
        }
    }
}
