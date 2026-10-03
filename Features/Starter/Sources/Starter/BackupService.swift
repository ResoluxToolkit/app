#if os(macOS)
import Foundation

public struct BackupResult: Sendable, Equatable {
    public let archivePath: String
    public let finishedAt: Date
}

public final class BackupService: @unchecked Sendable {
    public static let shared = BackupService()

    private let stateURL: URL
    private let queue = DispatchQueue(label: "com.resolux.backup", qos: .utility)

    public init(stateDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = stateDirectory ?? home.appendingPathComponent("Backups/Resolux", isDirectory: true)
        self.stateURL = dir.appendingPathComponent("last-backup.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public var lastBackupDate: Date? {
        get { Self.readDate(from: stateURL) }
        set { queue.sync { Self.write(newValue, to: stateURL) } }
    }

    public func runBackup(progress: ((String) -> Void)? = nil) async throws -> BackupResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let outputDir = stateURL.deletingLastPathComponent()
        let stamp = Self.fileStamp(Date())
        let archivePath = outputDir.appendingPathComponent("agent-configs-\(stamp).tar.gz").path

        let sources = ["\(home.path)/.spike", "\(home.path)/.openclaw"]
        let excludes = ["--exclude=.build", "--exclude=DerivedData", "--exclude=node_modules"]
        var args = ["-czf", archivePath] + excludes + sources

        progress?("empacotando ~/.spike e ~/.openclaw…")
        try await Self.runProcess("/usr/bin/tar", arguments: args)

        let finished = Date()
        lastBackupDate = finished
        progress?("backup concluído")
        return BackupResult(archivePath: archivePath, finishedAt: finished)
    }

    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func runProcess(_ path: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "BackupService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "tar falhou com status \(process.terminationStatus)"]
            )
        }
    }

    static func readDate(from url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredState.self, from: data).lastBackup
    }

    static func write(_ date: Date?, to url: URL) {
        guard let date else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let state = StoredState(lastBackup: date)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private struct StoredState: Codable {
    let lastBackup: Date
}
#endif
