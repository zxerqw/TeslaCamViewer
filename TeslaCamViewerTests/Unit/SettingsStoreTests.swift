import XCTest
@testable import TeslaCamViewer

final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_firstLaunch_returnsDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings())
    }

    func test_updating_persistsAcrossInstances() {
        let store1 = SettingsStore(defaults: defaults)
        store1.settings.recentGapThresholdSeconds = 900
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.settings.recentGapThresholdSeconds, 900)
    }

    func test_updating_clampsOutOfRangeToValid() {
        let store = SettingsStore(defaults: defaults)
        store.settings.recentGapThresholdSeconds = 99_999
        XCTAssertEqual(store.settings.recentGapThresholdSeconds, AppSettings.maxRecentGapSeconds)
    }

    func test_changes_bumpVersion() {
        let store = SettingsStore(defaults: defaults)
        let v0 = store.version
        store.settings.recentGapThresholdSeconds = 600
        XCTAssertGreaterThan(store.version, v0)
    }
}
