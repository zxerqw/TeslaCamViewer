import Foundation

public protocol ComposerProtocol: Sendable {
    /// Export a single angle at the event's native resolution with a timestamp watermark.
    func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws

    /// Export four angles into a 1920×1080 2×2 grid with per-cell angle labels + timestamp watermark.
    func exportGrid(request: ExportRequest, to url: URL) async throws
}
