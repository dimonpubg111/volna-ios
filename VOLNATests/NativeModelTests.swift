import XCTest
@testable import VOLNA

final class NativeModelTests: XCTestCase {
    private let now = KyivClock.parse("2026-10-30T14:00:00Z")!
    private func recording(start: String = "2026-10-30T10:00:00Z", end: String = "2026-10-30T12:00:00Z", status: String = "ready", playable: Bool = true, offset: Double = 10, limit: Double = 7210, id: String = "novyi-20261030", channel: String = "novyi") -> Recording {
        Recording(id: id, channelId: channel, title: "Передача", start: start, end: end, status: status, playable: playable, coveredSeconds: 7200, durationSeconds: 7200, playbackStartOffsetSeconds: offset, playbackEndSeconds: limit, coverageRatio: 1, fullProgramme: true)
    }
    func testCatalogueContractAndPriority() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog", withExtension: "json"))
        let catalogue = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(catalogue.ukrainianChannels.count, 90)
        XCTAssertEqual(Array(catalogue.ukrainianChannels.prefix(3).map(\.id)), ["novyi", "tet", "stb"])
        XCTAssertTrue(catalogue.ukrainianChannels.allSatisfy { $0.nativeSource?.nativeURL?.scheme == "https" })
        XCTAssertTrue(catalogue.movies.filter { $0.sources.allSatisfy { $0.type == "youtube" } }.allSatisfy { $0.nativeSource == nil })
    }
    func testNoProviderOrLocalURLs() {
        for value in ["https://user:pass@example.com/a.m3u8", "file:///private/video", "javascript:alert(1)", "http://example.com/a.m3u8", "https://127.0.0.1/a", "https://localhost/a", "https://example.local/a"] {
            XCTAssertNil(VolnaConfiguration.mediaURL(value), value)
        }
        XCTAssertEqual(VolnaConfiguration.mediaURL("/api/stream?url=a")?.host, VolnaConfiguration.origin.host)
        XCTAssertNil(VolnaConfiguration.archiveURL(id: "../../secret"))
    }
    func testProgrammeBoundaryAndProgress() {
        let p = Programme(id: "x", title: "Фільм", start: "2026-10-30T13:00:00.000Z", end: "2026-10-30T14:00:00Z", description: nil, image: nil)
        XCTAssertFalse(p.isCurrent(at: now))
        XCTAssertTrue(p.isCurrent(at: now.addingTimeInterval(-1)))
        XCTAssertEqual(p.progress(at: now.addingTimeInterval(-1800)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.progress(at: now.addingTimeInterval(300)), 1)
    }
    func testKyivMidnightAndDST() {
        XCTAssertEqual(KyivClock.key(KyivClock.parse("2026-10-30T22:10:00Z")!), "2026-10-31")
        let afterDST = KyivClock.parse("2026-10-25T14:00:00Z")!
        XCTAssertEqual(KyivClock.key(KyivClock.day(-1, from: afterDST)), "2026-10-24")
        XCTAssertEqual(KyivClock.time(KyivClock.parse("2026-10-30T14:00:00Z")), "16:00")
    }
    func testArchiveOnlyActuallySavedPastMedia() {
        XCTAssertTrue(recording().isPlayable(at: now))
        XCTAssertFalse(recording(start: "2026-10-30T15:00:00Z", end: "2026-10-30T16:00:00Z").isPlayable(at: now))
        XCTAssertFalse(recording(start: "2026-10-27T10:00:00Z", end: "2026-10-27T12:00:00Z").isPlayable(at: now))
        XCTAssertFalse(recording(playable: false).isPlayable(at: now))
        XCTAssertFalse(recording(offset: -10).isPlayable(at: now))
        XCTAssertFalse(recording(offset: 30, limit: 20).isPlayable(at: now))
        XCTAssertFalse(recording(limit: .infinity).isPlayable(at: now))
        XCTAssertFalse(recording(id: "../../etc").isPlayable(at: now))
        XCTAssertFalse(recording(channel: "other").isPlayable(at: now))
    }
    func testArchiveMatchesByTimeNotOnlyName() {
        let sameNameWrongTime = Programme(id: "p", title: "Передача", start: "2026-10-30T08:00:00Z", end: "2026-10-30T09:00:00Z", description: nil, image: nil)
        XCTAssertFalse(recording().overlaps(sameNameWrongTime))
        let exact = Programme(id: "q", title: "Передача", start: "2026-10-30T10:00:00Z", end: "2026-10-30T12:00:00Z", description: nil, image: nil)
        XCTAssertTrue(recording().overlaps(exact))
    }
    func testSearchHandlesAliasesYearAndWords() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog", withExtension: "json"))
        let catalogue = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
        let film = try XCTUnwrap(catalogue.movies.first { $0.id == "rasha-hudbai" })
        XCTAssertTrue(film.matches("2025"))
        XCTAssertTrue(film.matches("РАША ГУДБАЙ"))
        XCTAssertFalse(film.matches("несуществующий сериал"))
    }
}
