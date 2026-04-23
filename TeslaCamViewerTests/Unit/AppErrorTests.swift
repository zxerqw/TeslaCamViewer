import XCTest
@testable import TeslaCamViewer

final class AppErrorTests: XCTestCase {

    func test_notTeslaCamFolder_hasDescription() {
        let e: AppError = .notTeslaCamFolder
        XCTAssertNotNil(e.errorDescription)
        XCTAssertTrue(e.errorDescription!.contains("TeslaCam"))
    }

    func test_diskSpaceInsufficient_describesBytes() {
        let e: AppError = .diskSpaceInsufficient(neededBytes: 5_000_000_000, availableBytes: 1_000_000_000)
        let desc = e.errorDescription ?? ""
        XCTAssertTrue(desc.contains("5"))      // needed
        XCTAssertTrue(desc.contains("1"))      // available
    }

    func test_eventCorrupted_embedsUnderlyingMessage() {
        struct DummyError: Error, LocalizedError { var errorDescription: String? { "bad json" } }
        let e: AppError = .eventCorrupted(id: "2024-07-15_14-32-01", underlying: DummyError())
        let desc = e.errorDescription ?? ""
        XCTAssertTrue(desc.contains("2024-07-15"))
    }
}
