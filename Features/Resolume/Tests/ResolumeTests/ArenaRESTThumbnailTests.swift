import Foundation
import Testing
@testable import Resolume

@Test("thumbnail usa o endpoint com id e last_update")
func buscaThumbnailComLastUpdate() async throws {
    let recorder = PathRecorder()
    let rest = ArenaREST(endpoint: .init(
        get: { path in
            await recorder.record(path)
            return Data([0x89])
        },
        post: { _, _ in Data() }))

    let data = try await rest.thumbnailData(clipID: 42, stamp: "1791369653576238")

    #expect(data == Data([0x89]))
    #expect(await recorder.paths == ["/composition/clips/by-id/42/thumbnail/1791369653576238"])
}

@Test("thumbnail sem last_update e negada")
func recusaThumbnailSemStamp() async {
    let rest = ArenaREST(endpoint: .init(
        get: { _ in Data() },
        post: { _, _ in Data() }))

    await #expect(throws: ArenaREST.Failure.self) {
        try await rest.thumbnailData(clipID: 42, stamp: "0")
    }
}

private actor PathRecorder {
    private(set) var paths: [String] = []

    func record(_ path: String) {
        paths.append(path)
    }
}
