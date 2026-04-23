import XCTest
import AVFoundation
import CoreMedia
@testable import TeslaCamViewer

final class MultiAVPlayerTests: XCTestCase {

    private func fixtureEvent() async throws -> TeslaEvent {
        let bundle = Bundle(for: Self.self)
        let root = bundle.url(forResource: "Fixtures/fixture-6cam-saved/TeslaCam", withExtension: nil)!
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: root)
        return result.savedEvents[0]
    }

    func test_totalDuration_isSumOfSegmentDurations() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        try await player.load(event: event, angles: [.front, .back])
        // Fixture: 3 segments × ~5s = ~15s
        let expected = event.totalDuration.seconds
        XCTAssertEqual(player.totalDuration.seconds, expected, accuracy: 0.5)
    }

    func test_seek_bringsAllPlayersWithin100msSyncWindow() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        try await player.load(event: event, angles: [.front, .back, .leftRepeater, .rightRepeater])
        try await player.seek(to: CMTime(seconds: 6, preferredTimescale: 600))

        let times = player.debugPerAnglePlayhead()
        XCTAssertFalse(times.isEmpty)
        let maxGap = times.max()!.seconds - times.min()!.seconds
        XCTAssertLessThan(maxGap, 0.1)
    }

    func test_missingAngle_doesNotThrowAndIsSkipped() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        // fixture-6cam-saved HAS left_pillar, so synthesize an event that doesn't.
        let trimmed = TeslaEvent(
            id: event.id, type: event.type, startTime: event.startTime,
            segments: event.segments,
            availableAngles: [.front, .back],   // pretend
            thumbnailURL: event.thumbnailURL, eventMetadata: event.eventMetadata
        )
        try await player.load(event: trimmed, angles: [.front, .back, .leftPillar])
        XCTAssertEqual(Set(player.loadedAngles), [.front, .back])
    }
}
