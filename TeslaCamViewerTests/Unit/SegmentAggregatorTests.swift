import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class SegmentAggregatorTests: XCTestCase {

    func test_groupsSameTimestampAcrossAngles() {
        let urls = [
            url("2024-07-15_14-32-01-front.mp4"),
            url("2024-07-15_14-32-01-back.mp4"),
            url("2024-07-15_14-32-01-left_repeater.mp4"),
            url("2024-07-15_14-32-01-right_repeater.mp4"),
            url("2024-07-15_14-33-01-front.mp4"),
            url("2024-07-15_14-33-01-back.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].filesByAngle.count, 4)
        XCTAssertEqual(segments[1].filesByAngle.count, 2)
        XCTAssertLessThan(segments[0].timestamp, segments[1].timestamp)
    }

    func test_skipsUnparseableFiles() {
        let urls = [
            url("2024-07-15_14-32-01-front.mp4"),
            url("thumb.png"),
            url("event.json"),
            url(".DS_Store"),
            url("random.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].filesByAngle.count, 1)
        XCTAssertEqual(segments[0].filesByAngle.keys.first, .front)
    }

    func test_resultIsSortedByTimestamp() {
        let urls = [
            url("2024-07-15_14-34-01-front.mp4"),
            url("2024-07-15_14-32-01-front.mp4"),
            url("2024-07-15_14-33-01-front.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.map { $0.timestamp }, segments.map { $0.timestamp }.sorted())
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(SegmentAggregator.aggregate(urls: [], defaultSegmentDuration: .zero).isEmpty)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/fake/\(name)")
    }
}
