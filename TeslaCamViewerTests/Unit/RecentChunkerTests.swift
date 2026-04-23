import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class RecentChunkerTests: XCTestCase {

    func test_continuousSegments_yieldOneChunk() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 3, 4])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }

    func test_gapExceedsThreshold_splits() {
        // 3 segments, then a 10-minute gap, then 2 more
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 12, 13])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300)   // 5 min
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 3)
        XCTAssertEqual(chunks[1].count, 2)
    }

    func test_wideThreshold_mergesBack() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 12, 13])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 1_800)  // 30 min
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }

    func test_gapEqualsThreshold_belongsToFirstChunk() {
        // gap of exactly 240s between segments at minute 2 and minute 7 (end of seg2 at 3:00, start of seg3 at 7:00 = 240s)
        // With threshold 240, ≤ threshold → same chunk.
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 7])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 240)
        XCTAssertEqual(chunks.count, 1)
    }

    func test_gapJustOverThreshold_splits() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 7])
        // gap 240s; threshold 239 → splits
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 239)
        XCTAssertEqual(chunks.count, 2)
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(RecentChunker.chunk(segments: [], gapThresholdSeconds: 300).isEmpty)
    }

    func test_singleSegment_isOwnChunk() {
        let segments = makeSegments(startOffsetsMinutes: [0])
        XCTAssertEqual(RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300).count, 1)
    }

    // MARK: helpers

    private func makeSegments(startOffsetsMinutes offsets: [Int]) -> [MinuteSegment] {
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        return offsets.map { mins in
            MinuteSegment(
                timestamp: base.addingTimeInterval(TimeInterval(mins * 60)),
                duration: CMTime(seconds: 60, preferredTimescale: 600),
                filesByAngle: [.front: URL(fileURLWithPath: "/tmp/fake-\(mins).mp4")]
            )
        }
    }
}
