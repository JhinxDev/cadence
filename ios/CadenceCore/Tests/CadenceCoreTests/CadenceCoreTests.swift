import XCTest
@testable import CadenceCore

final class CadenceCoreTests: XCTestCase {
    func testSubsonicMD5TokenMatchesSpec() {
        let token = OpenSubsonicClient.makeAuthToken(password: "sesame", salt: "c19b2d")
        XCTAssertEqual(token.count, 32)
        XCTAssertEqual(token, "26719a1196d2a940705a59634eb18eab")
    }

    func testQueueEngineInfiniteRadioLowWatermarkAndSave() {
        var queue = QueueEngine()
        let initial = DemoCatalog.libraryTracks + DemoCatalog.discoveryTracks
        queue.load(tracks: initial, startAt: 0, radioSessionId: "rad-1", radioMode: .balanced)

        XCTAssertEqual(queue.currentTrack?.id, "demo-lib-1")
        XCTAssertFalse(queue.shouldFetchMoreRadio(lowWatermark: 3))

        _ = queue.jump(to: 5)
        XCTAssertTrue(queue.shouldFetchMoreRadio(lowWatermark: 3))

        queue.markTrackSaved(extId: "ext:deezer:2001", navidromeId: "nav-999")
        let saved = queue.tracks.first { $0.id == "ext:deezer:2001" }
        XCTAssertEqual(saved?.inLibrary, true)
        XCTAssertEqual(saved?.isPreview, false)
        XCTAssertEqual(saved?.navidromeId, "nav-999")
    }

    func testQueueEngineMoveAndRemoveUpcoming() {
        var queue = QueueEngine()
        queue.load(tracks: DemoCatalog.libraryTracks, startAt: 0)
        XCTAssertEqual(queue.upNextTracks.count, 3)

        queue.removeUpcoming(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(queue.upNextTracks.map(\.id), ["demo-lib-3", "demo-lib-4"])

        queue.moveUpcoming(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(queue.upNextTracks.map(\.id), ["demo-lib-4", "demo-lib-3"])
    }

    func testOfflineCachePersistenceAndRemoval() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceCacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = OfflineCacheManager(directory: dir)
        let sourceFile = dir.appendingPathComponent("sample.m4a")
        try Data("CADENCE_AUDIO_BYTES".utf8).write(to: sourceFile)

        let track = DemoCatalog.libraryTracks[0]
        let savedURL = try await manager.download(track: track, from: sourceFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))

        let downloaded = await manager.isDownloaded(track.id)
        XCTAssertTrue(downloaded)

        let bytes = await manager.totalBytes()
        XCTAssertGreaterThan(bytes, 0)

        await manager.remove(trackId: track.id)
        let afterRemove = await manager.isDownloaded(track.id)
        XCTAssertFalse(afterRemove)
    }

    func testCadenceURLNormalizationAndTokenResolution() {
        XCTAssertEqual(
            CadenceAPIClient.normalizedBaseURL("music.example.com/"),
            "https://music.example.com"
        )
        let client = CadenceAPIClient()
        let acct = UserAccount(serverURL: "https://cadence.example.com", username: "listener", password: "pw", bearerToken: "tok123")
        let resolved = client.resolveURL(account: acct, rawPathOrURL: "/api/v1/artwork/cov-1")
        XCTAssertEqual(resolved?.absoluteString, "https://cadence.example.com/api/v1/artwork/cov-1?token=tok123")
    }
}
