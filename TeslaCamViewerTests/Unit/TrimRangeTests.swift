import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class TrimRangeTests: XCTestCase {

    func test_init_clampsAndOrdersWithinBounds() {
        let total = CMTime(seconds: 180, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: -5, preferredTimescale: 600),
            end: .init(seconds: 200, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual(r.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(r.end.seconds, 180, accuracy: 0.001)
    }

    func test_init_whenStartExceedsEnd_swapsThem() {
        let total = CMTime(seconds: 120, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: 80, preferredTimescale: 600),
            end: .init(seconds: 10, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual(r.start.seconds, 10, accuracy: 0.001)
        XCTAssertEqual(r.end.seconds, 80, accuracy: 0.001)
    }

    func test_init_whenCollapsed_leavesOneSecondOfRange() {
        let total = CMTime(seconds: 60, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: 30, preferredTimescale: 600),
            end: .init(seconds: 30, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual((r.end - r.start).seconds, 1, accuracy: 0.001)
    }

    func test_fullRange_spansZeroToTotalDuration() {
        let total = CMTime(seconds: 120, preferredTimescale: 600)
        let r = TrimRange.fullRange(totalDuration: total)
        XCTAssertEqual(r.start, .zero)
        XCTAssertEqual(r.end, total)
    }
}
