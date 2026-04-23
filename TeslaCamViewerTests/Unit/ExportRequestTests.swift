import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class ExportRequestTests: XCTestCase {

    func test_gridLayout_requiresExactlyFourAngles() {
        let ok = ExportRequest.Layout.gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater])
        XCTAssertTrue(ok.isValid)

        let tooFew = ExportRequest.Layout.gridCombined(angles: [.front, .back])
        XCTAssertFalse(tooFew.isValid)
    }

    func test_singlesLayout_requiresAtLeastOneAngle() {
        XCTAssertFalse(ExportRequest.Layout.singlesPerAngle(angles: []).isValid)
        XCTAssertTrue(ExportRequest.Layout.singlesPerAngle(angles: [.front]).isValid)
    }

    func test_watermarkPosition_codable_roundtrip() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for pos in ExportRequest.WatermarkPosition.allCases {
            let data = try enc.encode(pos)
            let back = try dec.decode(ExportRequest.WatermarkPosition.self, from: data)
            XCTAssertEqual(pos, back)
        }
    }
}
