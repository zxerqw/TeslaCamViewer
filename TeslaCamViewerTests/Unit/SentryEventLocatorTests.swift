import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class SentryEventLocatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_721_050_321)

    private func sentry(triggerOffset: Double?, segments: [MinuteSegment]) -> TeslaEvent {
        .fixture(
            type: .sentry,
            segments: segments,
            eventMetadata: EventMetadata(
                timestamp: triggerOffset.map { base.addingTimeInterval($0) },
                city: nil, reason: "sentry_aware_object_detection"
            )
        )
    }

    func test_triggerInSecondSegment_usesRealStartsAndLead() {
        let segs = [MinuteSegment.fixture(offsetSeconds: 0), .fixture(offsetSeconds: 60)]
        let e = sentry(triggerOffset: 90, segments: segs)
        // first clip really lasted 58 s
        let t = SentryEventLocator.eventTime(
            for: e,
            segmentStartTimes: [.zero, CMTime(seconds: 58, preferredTimescale: 600)],
            totalDuration: CMTime(seconds: 118, preferredTimescale: 600)
        )
        XCTAssertEqual(t?.seconds ?? -1, 58 + 30 - 5, accuracy: 0.01)
    }

    func test_fallsBackToSegmentDurations() {
        let segs = [MinuteSegment.fixture(offsetSeconds: 0), .fixture(offsetSeconds: 60)]
        let e = sentry(triggerOffset: 70, segments: segs)
        let t = SentryEventLocator.eventTime(for: e, segmentStartTimes: [],
                                             totalDuration: CMTime(seconds: 120, preferredTimescale: 600))
        XCTAssertEqual(t?.seconds ?? -1, 65, accuracy: 0.01)
    }

    func test_nilForNonSentryOrMissingTimestamp() {
        let segs = [MinuteSegment.fixture(offsetSeconds: 0)]
        let total = CMTime(seconds: 60, preferredTimescale: 600)
        XCTAssertNil(SentryEventLocator.eventTime(for: sentry(triggerOffset: nil, segments: segs),
                                                  segmentStartTimes: [], totalDuration: total))
        XCTAssertNil(SentryEventLocator.eventTime(for: .fixture(type: .saved, segments: segs),
                                                  segmentStartTimes: [], totalDuration: total))
    }

    func test_triggerBeforeFirstSegment_isNil() {
        let e = sentry(triggerOffset: -30, segments: [.fixture(offsetSeconds: 0)])
        XCTAssertNil(SentryEventLocator.eventTime(for: e, segmentStartTimes: [],
                                                  totalDuration: CMTime(seconds: 60, preferredTimescale: 600)))
    }
}
