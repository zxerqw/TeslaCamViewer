import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class TeslaEventTests: XCTestCase {

    func test_minuteSegment_exposesFilesByAngle() {
        let ts = Date(timeIntervalSince1970: 1_721_050_321)
        let url = URL(fileURLWithPath: "/tmp/front.mp4")
        let seg = MinuteSegment(
            timestamp: ts,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            filesByAngle: [.front: url]
        )
        XCTAssertEqual(seg.filesByAngle[.front], url)
        XCTAssertNil(seg.filesByAngle[.back])
    }

    func test_eventMetadata_decodesFromTeslaEventJSON() throws {
        let json = #"""
        {"timestamp":"2024-07-15T14:32:01","city":"Mountain View","reason":"sentry_aware_object_detection"}
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithOptionalFractionalSeconds
        let meta = try decoder.decode(EventMetadata.self, from: json)
        XCTAssertEqual(meta.city, "Mountain View")
        XCTAssertEqual(meta.reason, "sentry_aware_object_detection")
        XCTAssertNotNil(meta.timestamp)
    }

    func test_totalDuration_sumsAllSegmentDurations() {
        let event = TeslaEvent.fixture(
            segments: [
                .fixture(offsetSeconds: 0,   durationSeconds: 60),
                .fixture(offsetSeconds: 60,  durationSeconds: 60),
                .fixture(offsetSeconds: 120, durationSeconds: 45)
            ]
        )
        XCTAssertEqual(event.totalDuration.seconds, 165, accuracy: 0.001)
    }

    func test_availableAngles_isUnionAcrossSegments() {
        let event = TeslaEvent.fixture(
            segments: [
                .fixture(angles: [.front, .back]),
                .fixture(angles: [.front, .leftRepeater])
            ]
        )
        XCTAssertEqual(event.availableAngles, [.front, .back, .leftRepeater])
    }
}
