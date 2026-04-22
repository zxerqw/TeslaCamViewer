import XCTest
@testable import TeslaCamViewer

final class CameraAngleTests: XCTestCase {

    func test_fileSuffix_mapsEachAngleToTeslaNaming() {
        XCTAssertEqual(CameraAngle.front.fileSuffix, "front")
        XCTAssertEqual(CameraAngle.back.fileSuffix, "back")
        XCTAssertEqual(CameraAngle.leftRepeater.fileSuffix, "left_repeater")
        XCTAssertEqual(CameraAngle.rightRepeater.fileSuffix, "right_repeater")
        XCTAssertEqual(CameraAngle.leftPillar.fileSuffix, "left_pillar")
        XCTAssertEqual(CameraAngle.rightPillar.fileSuffix, "right_pillar")
    }

    func test_defaultGrid_isFrontBackAndTwoRepeaters() {
        XCTAssertEqual(
            CameraAngle.defaultGrid,
            [.front, .back, .leftRepeater, .rightRepeater]
        )
    }

    func test_fromFileSuffix_matchesAllCases() {
        for angle in CameraAngle.allCases {
            XCTAssertEqual(CameraAngle(fileSuffix: angle.fileSuffix), angle)
        }
    }

    func test_fromFileSuffix_returnsNilOnUnknown() {
        XCTAssertNil(CameraAngle(fileSuffix: "trunk"))
    }
}
