import XCTest
import AVFoundation
import CoreMedia
@testable import TeslaCamViewer

final class AVComposerTests: XCTestCase {

    private func fixtureEvent() async throws -> TeslaEvent {
        let bundle = Bundle(for: Self.self)
        let root = bundle.url(forResource: "Fixtures/fixture-6cam-saved/TeslaCam", withExtension: nil)!
        let scanner = TeslaCamScanner()
        return try await scanner.scan(root: root).savedEvents[0]
    }

    private func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AVComposerTests-\(UUID().uuidString).mp4")
    }

    func test_singleAngle_export_producesPlayableMP4() async throws {
        let event = try await fixtureEvent()
        let request = ExportRequest(
            event: event,
            layout: .singlesPerAngle(angles: [.front]),
            range: TrimRange(start: .zero, end: CMTime(seconds: 4, preferredTimescale: 600), totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
        let outURL = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: outURL) }

        let composer = AVComposer()
        try await composer.exportSingleAngle(.front, request: request, to: outURL, progress: { _ in })

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        let asset = AVURLAsset(url: outURL)
        let dur = try await asset.load(.duration)
        XCTAssertEqual(dur.seconds, 4, accuracy: 0.5)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
    }

    func test_gridExport_producesPlayable2x2Video() async throws {
        let event = try await fixtureEvent()
        let request = ExportRequest(
            event: event,
            layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]),
            range: TrimRange(start: .zero, end: CMTime(seconds: 4, preferredTimescale: 600), totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
        let outURL = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: outURL) }

        let composer = AVComposer()
        try await composer.exportGrid(request: request, to: outURL, progress: { _ in })

        let asset = AVURLAsset(url: outURL)
        let track = try await asset.loadTracks(withMediaType: .video).first
        XCTAssertNotNil(track)
        let size = try await track!.load(.naturalSize)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }
}
