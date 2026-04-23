import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class ExportJobTests: XCTestCase {

    private final class StubComposer: ComposerProtocol, @unchecked Sendable {
        var singleCalls: [(CameraAngle, URL)] = []
        var gridCalls: [URL] = []
        var shouldFail: Error?

        func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws {
            if let e = shouldFail { throw e }
            singleCalls.append((angle, url))
            FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        }

        func exportGrid(request: ExportRequest, to url: URL) async throws {
            if let e = shouldFail { throw e }
            gridCalls.append(url)
            FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        }
    }

    private func makeRequest(layout: ExportRequest.Layout) -> ExportRequest {
        let event = TeslaEvent.fixture(segments: [.fixture(), .fixture(offsetSeconds: 60)])
        return ExportRequest(
            event: event,
            layout: layout,
            range: TrimRange.fullRange(totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
    }

    func test_singlesLayout_callsComposerOncePerAngle() async throws {
        let composer = StubComposer()
        let job = await ExportJob(composer: composer)
        let req = makeRequest(layout: .singlesPerAngle(angles: [.front, .back]))
        let result = try await job.run(req)
        XCTAssertEqual(composer.singleCalls.count, 2)
        XCTAssertEqual(composer.gridCalls.count, 0)
        XCTAssertEqual(result.outputURLs.count, 2)
    }

    func test_gridLayout_callsComposerOnce() async throws {
        let composer = StubComposer()
        let job = await ExportJob(composer: composer)
        let req = makeRequest(layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]))
        let result = try await job.run(req)
        XCTAssertEqual(composer.gridCalls.count, 1)
        XCTAssertEqual(composer.singleCalls.count, 0)
        XCTAssertEqual(result.outputURLs.count, 1)
    }

    func test_composerError_becomesAppErrorExportFailed() async {
        let composer = StubComposer()
        composer.shouldFail = NSError(domain: "t", code: 1)
        let job = await ExportJob(composer: composer)
        let req = makeRequest(layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]))
        do {
            _ = try await job.run(req)
            XCTFail("expected throw")
        } catch AppError.exportFailed {
            // ok
        } catch {
            XCTFail("expected AppError.exportFailed, got \(error)")
        }
    }

    func test_invalidLayout_throwsBeforeCallingComposer() async {
        let composer = StubComposer()
        let job = await ExportJob(composer: composer)
        let req = makeRequest(layout: .singlesPerAngle(angles: []))
        do {
            _ = try await job.run(req)
            XCTFail("expected throw")
        } catch AppError.exportFailed {
            XCTAssertEqual(composer.singleCalls.count, 0)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
