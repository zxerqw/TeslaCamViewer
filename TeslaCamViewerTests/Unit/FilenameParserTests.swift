import XCTest
@testable import TeslaCamViewer

final class FilenameParserTests: XCTestCase {

    func test_parses_allKnownAngles() {
        let cases: [(String, CameraAngle)] = [
            ("2024-07-15_14-32-01-front.mp4",          .front),
            ("2024-07-15_14-32-01-back.mp4",           .back),
            ("2024-07-15_14-32-01-left_repeater.mp4",  .leftRepeater),
            ("2024-07-15_14-32-01-right_repeater.mp4", .rightRepeater),
            ("2024-07-15_14-32-01-left_pillar.mp4",    .leftPillar),
            ("2024-07-15_14-32-01-right_pillar.mp4",   .rightPillar),
        ]
        for (name, expectedAngle) in cases {
            let parsed = FilenameParser.parse(name)
            XCTAssertNotNil(parsed, "failed for \(name)")
            XCTAssertEqual(parsed?.angle, expectedAngle)
        }
    }

    func test_timestamp_matchesLocalTime() {
        let parsed = FilenameParser.parse("2024-07-15_14-32-01-front.mp4")!
        let cal = Calendar(identifier: .gregorian)
        // Tesla stores local time — verify components match in the current timezone.
        let comps = cal.dateComponents(in: .current, from: parsed.timestamp)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 32)
        XCTAssertEqual(comps.second, 1)
    }

    func test_rejects_nonMp4() {
        XCTAssertNil(FilenameParser.parse("2024-07-15_14-32-01-front.mov"))
    }

    func test_rejects_unknownAngle() {
        XCTAssertNil(FilenameParser.parse("2024-07-15_14-32-01-trunk.mp4"))
    }

    func test_rejects_malformed() {
        XCTAssertNil(FilenameParser.parse("front.mp4"))
        XCTAssertNil(FilenameParser.parse("random.mp4"))
        XCTAssertNil(FilenameParser.parse("thumb.png"))
    }
}
