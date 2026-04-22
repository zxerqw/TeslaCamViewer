import XCTest
import CoreMedia
@testable import TeslaCamViewer

@MainActor
final class LibraryStoreTests: XCTestCase {

    /// Minimal in-memory scanner stub returning a canned ScanResult.
    private final class FakeScanner: ScannerProtocol, @unchecked Sendable {
        var result: ScanResult
        init(result: ScanResult) { self.result = result }
        func scan(root: URL) async throws -> ScanResult { result }
    }

    private func makeFakeResult(
        recentOffsetsMinutes: [Int] = []
    ) -> ScanResult {
        let savedEvent = TeslaEvent.fixture(id: "saved-1", type: .saved, segments: [.fixture()])
        let sentryEvent = TeslaEvent.fixture(id: "sentry-1", type: .sentry, segments: [.fixture()])
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        let segs = recentOffsetsMinutes.map { mins in
            MinuteSegment(
                timestamp: base.addingTimeInterval(TimeInterval(mins * 60)),
                duration: CMTime(seconds: 60, preferredTimescale: 600),
                filesByAngle: [.front: URL(fileURLWithPath: "/tmp/\(mins).mp4")]
            )
        }
        return ScanResult(savedEvents: [savedEvent], sentryEvents: [sentryEvent], recentSegments: segs)
    }

    func test_loadEvents_populatesSavedAndSentry() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let scanner = FakeScanner(result: makeFakeResult())
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(store.savedEvents.count, 1)
        XCTAssertEqual(store.sentryEvents.count, 1)
        XCTAssertEqual(store.recentEvents.count, 0)
    }

    func test_recentEvents_useCurrentThreshold() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.settings.recentGapThresholdSeconds = 300     // 5 min

        let scanner = FakeScanner(result: makeFakeResult(recentOffsetsMinutes: [0, 1, 12, 13]))
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(store.recentEvents.count, 2)
    }

    func test_changingThreshold_reChunksWithoutRescan() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.settings.recentGapThresholdSeconds = 300
        let scanner = FakeScanner(result: makeFakeResult(recentOffsetsMinutes: [0, 1, 12, 13]))
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(store.recentEvents.count, 2)

        // Change the fake scanner's canned result so that if LibraryStore
        // accidentally rescans, the test would notice — but it should not rescan.
        scanner.result = ScanResult(savedEvents: [], sentryEvents: [], recentSegments: [])
        settings.settings.recentGapThresholdSeconds = 1_800     // 30 min

        // Give the observation loop a beat to pick up the change.
        // 50ms is the poll interval inside startObservingSettings; allow 200ms to be safe.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.recentEvents.count, 1, "threshold widened → one merged event")
        // Saved/sentry unchanged, proving no rescan happened:
        XCTAssertEqual(store.savedEvents.count, 1)
    }
}
