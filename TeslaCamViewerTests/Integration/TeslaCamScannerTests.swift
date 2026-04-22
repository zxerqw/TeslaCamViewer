import XCTest
@testable import TeslaCamViewer

final class TeslaCamScannerTests: XCTestCase {

    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: Self.self)
        return bundle.url(forResource: "Fixtures/\(name)/TeslaCam", withExtension: nil)
            ?? URL(fileURLWithPath: "/nonexistent")
    }

    func test_scan_sixCamSaved_returnsOneSavedEventWithAllAngles() async throws {
        let url = fixtureURL("fixture-6cam-saved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "fixture not copied into test bundle")
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: url)
        XCTAssertEqual(result.savedEvents.count, 1)
        XCTAssertTrue(result.sentryEvents.isEmpty)
        XCTAssertTrue(result.recentSegments.isEmpty)

        let event = result.savedEvents[0]
        XCTAssertEqual(event.type, .saved)
        XCTAssertEqual(event.availableAngles.count, 6)
        XCTAssertEqual(event.segments.count, 3)
        XCTAssertNotNil(event.thumbnailURL)
        XCTAssertEqual(event.eventMetadata?.city, "Mountain View")
    }

    func test_scan_fourCamSentry_returnsTwoEventsOldCar() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-4cam-sentry"))
        XCTAssertEqual(result.sentryEvents.count, 2)
        for ev in result.sentryEvents {
            XCTAssertEqual(ev.availableAngles, [.front, .back, .leftRepeater, .rightRepeater])
        }
    }

    func test_scan_corrupted_skipsBadFoldersAndFiles() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-corrupted"))
        XCTAssertEqual(result.savedEvents.count, 1, "random_trash_folder must be skipped")
        let ev = result.savedEvents[0]
        XCTAssertEqual(ev.availableAngles, [.front, .leftRepeater])
        XCTAssertNil(ev.eventMetadata, "corrupted JSON → metadata nil, does not throw")
    }

    func test_scan_recentContinuous_returnsUnchunkedSegments() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-recent-continuous"))
        XCTAssertEqual(result.recentSegments.count, 5, "one per consecutive minute")
        XCTAssertTrue(result.savedEvents.isEmpty)
    }

    func test_scan_recentGapped_returnsAllSixSegmentsUnchunked() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-recent-gapped"))
        XCTAssertEqual(result.recentSegments.count, 6)
        // Scanner does NOT chunk; that's RecentChunker's job.
    }

    func test_scan_nonTeslaCamFolder_throwsNotTeslaCamFolder() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let scanner = TeslaCamScanner()
        do {
            _ = try await scanner.scan(root: empty)
            XCTFail("expected AppError.notTeslaCamFolder")
        } catch AppError.notTeslaCamFolder {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
