import XCTest
@testable import TeslaCamViewer

final class FolderNameParserTests: XCTestCase {

    func test_parses_validFolderName() {
        let result = FolderNameParser.parse("2024-07-15_14-32-01")
        XCTAssertNotNil(result)
        let cal = Calendar(identifier: .gregorian)
        // Tesla stores local time — verify components match in the current timezone.
        let comps = cal.dateComponents(in: .current, from: result!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 32)
        XCTAssertEqual(comps.second, 1)
    }

    func test_rejects_extraCharacters() {
        XCTAssertNil(FolderNameParser.parse("2024-07-15_14-32-01 copy"))
    }

    func test_rejects_wrongSeparators() {
        XCTAssertNil(FolderNameParser.parse("2024-07-15 14:32:01"))
    }

    func test_rejects_unixHiddenFolder() {
        XCTAssertNil(FolderNameParser.parse(".DS_Store"))
    }
}
