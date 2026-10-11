import CoreGraphics
import Foundation

public struct DisplayInfo: Sendable, Equatable, Codable {
    public let id: UInt32
    public let originX: Int
    public let originY: Int
    public let pointWidth: Int
    public let pointHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isMain: Bool
}

public enum DisplaySource {
    public static func displays() -> [DisplayInfo] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(32, &displayIDs, &displayCount) == .success, displayCount > 0 else {
            return []
        }
        let mainDisplayID = CGMainDisplayID()
        let displays = (0..<Int(displayCount)).map { index -> DisplayInfo in
            let displayID = displayIDs[index]
            let bounds = CGDisplayBounds(displayID)
            let mode = CGDisplayCopyDisplayMode(displayID)
            return DisplayInfo(
                id: displayID,
                originX: Int(bounds.origin.x),
                originY: Int(bounds.origin.y),
                pointWidth: Int(bounds.width),
                pointHeight: Int(bounds.height),
                pixelWidth: mode.map { Int($0.pixelWidth) } ?? Int(bounds.width),
                pixelHeight: mode.map { Int($0.pixelHeight) } ?? Int(bounds.height),
                refreshRate: mode.map { $0.refreshRate } ?? 0,
                isMain: displayID == mainDisplayID
            )
        }
        return displays.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.id < rhs.id
        }
    }
}
