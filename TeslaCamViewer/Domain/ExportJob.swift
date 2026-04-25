import Foundation
import Observation

public struct ExportResult: Sendable {
    public let outputURLs: [URL]
}

@Observable
@MainActor
public final class ExportJob {
    public private(set) var isRunning = false
    public private(set) var progress: Double = 0

    @ObservationIgnored private let composer: ComposerProtocol
    @ObservationIgnored private let tempDir: URL

    public init(composer: ComposerProtocol, tempDir: URL = FileManager.default.temporaryDirectory) {
        self.composer = composer
        self.tempDir = tempDir
    }

    @discardableResult
    public func run(_ request: ExportRequest) async throws -> ExportResult {
        guard request.layout.isValid else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "ExportJob", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid export layout"]
            ))
        }
        isRunning = true
        defer { isRunning = false; progress = 0 }

        var outs: [URL] = []

        do {
            switch request.layout {
            case .singlesPerAngle(let angles):
                for (i, angle) in angles.enumerated() {
                    let url = tempDir.appendingPathComponent("tcv-\(UUID().uuidString)-\(angle.fileSuffix).mp4")
                    let base = Double(i) / Double(angles.count)
                    let span = 1.0 / Double(angles.count)
                    try await composer.exportSingleAngle(angle, request: request, to: url) { [weak self] p in
                        Task { @MainActor [weak self] in
                            self?.progress = base + Double(p) * span
                        }
                    }
                    outs.append(url)
                    progress = Double(i + 1) / Double(angles.count)
                }

            case .gridCombined:
                let url = tempDir.appendingPathComponent("tcv-\(UUID().uuidString)-grid.mp4")
                try await composer.exportGrid(request: request, to: url) { [weak self] p in
                    Task { @MainActor [weak self] in
                        self?.progress = Double(p)
                    }
                }
                outs.append(url)
                progress = 1.0
            }
        } catch let e as AppError {
            throw e
        } catch {
            throw AppError.exportFailed(underlying: error)
        }

        return ExportResult(outputURLs: outs)
    }
}
