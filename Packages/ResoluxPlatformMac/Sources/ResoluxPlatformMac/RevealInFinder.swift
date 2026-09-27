import AppKit
import Foundation

public enum RevealError: Error, Equatable {
    case missing(String)
}

public struct FinderRevealer: Sendable {
    public init() {}

    public func reveal(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RevealError.missing(url.path)
        }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
