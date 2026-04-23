import XCTest
@testable import TeslaCamViewer

final class BookmarkStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BookmarkStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_initiallyNoBookmark() {
        let store = BookmarkStore(defaults: defaults)
        XCTAssertFalse(store.hasBookmark)
    }

    func test_saveAndLoad_roundtripRealDirectoryOnDisk() throws {
        // Use a real tmp directory so the bookmark actually resolves.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(defaults: defaults)
        try store.save(url: tmp)
        XCTAssertTrue(store.hasBookmark)

        let resolved = try store.resolve()
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    func test_resolveMissingBookmark_throwsBookmarkStale() {
        let store = BookmarkStore(defaults: defaults)
        do {
            _ = try store.resolve()
            XCTFail("expected AppError.bookmarkStale")
        } catch AppError.bookmarkStale {
            // ok
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func test_clear_removesBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(defaults: defaults)
        try store.save(url: tmp)
        store.clear()
        XCTAssertFalse(store.hasBookmark)
    }
}
