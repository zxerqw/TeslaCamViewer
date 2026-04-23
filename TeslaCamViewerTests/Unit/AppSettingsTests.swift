import XCTest
@testable import TeslaCamViewer

final class AppSettingsTests: XCTestCase {

    func test_defaults_matchSpec() {
        let s = AppSettings()
        XCTAssertEqual(s.recentGapThresholdSeconds, 300)        // 5 minutes
        XCTAssertEqual(s.defaultWatermarkPosition, .bottomLeft)
    }

    func test_codable_roundtrip() throws {
        let s = AppSettings(recentGapThresholdSeconds: 900, defaultWatermarkPosition: .topRight)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.recentGapThresholdSeconds, 900)
        XCTAssertEqual(back.defaultWatermarkPosition, .topRight)
    }

    func test_clampsRecentGapOnInit() {
        let tooLow  = AppSettings(recentGapThresholdSeconds: 10,   defaultWatermarkPosition: .bottomLeft)
        let tooHigh = AppSettings(recentGapThresholdSeconds: 9_999, defaultWatermarkPosition: .bottomLeft)
        XCTAssertEqual(tooLow.recentGapThresholdSeconds,  AppSettings.minRecentGapSeconds)
        XCTAssertEqual(tooHigh.recentGapThresholdSeconds, AppSettings.maxRecentGapSeconds)
    }
}
