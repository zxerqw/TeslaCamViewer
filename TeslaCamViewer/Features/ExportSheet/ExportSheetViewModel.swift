import Foundation
import Observation
import CoreMedia

@Observable
@MainActor
final class ExportSheetViewModel: Identifiable {
    let id = UUID()
    enum Mode: String, CaseIterable, Identifiable {
        case grid, singles
        var id: String { rawValue }
        var label: String { self == .grid ? "四宫格合成" : "多视角独立" }
    }

    var mode: Mode = .grid
    var selectedAngles: Set<CameraAngle>
    var watermarkPosition: ExportRequest.WatermarkPosition
    var isRunning = false
    var resultURLs: [URL] = []
    var error: AppError?
    /// Whether the video was successfully saved to the photo library.
    var savedToLibrary = false

    /// Export progress from 0.0 to 1.0, driven by ExportJob.
    var progress: Double { exportJob.progress }

    @ObservationIgnored let event: TeslaEvent
    @ObservationIgnored let gridAngles: [CameraAngle]
    @ObservationIgnored let trim: TrimRange
    @ObservationIgnored private let exportJob: ExportJob

    init(
        event: TeslaEvent,
        gridAngles: [CameraAngle],
        trim: TrimRange,
        defaultWatermark: ExportRequest.WatermarkPosition,
        exportJob: ExportJob
    ) {
        self.event = event
        self.gridAngles = gridAngles
        self.trim = trim
        self.watermarkPosition = defaultWatermark
        self.selectedAngles = Set(gridAngles)
        self.exportJob = exportJob
    }

    func run() async {
        isRunning = true
        error = nil
        savedToLibrary = false
        defer { isRunning = false }
        let layout: ExportRequest.Layout = switch mode {
        case .grid:    .gridCombined(angles: gridAngles)
        case .singles: .singlesPerAngle(angles: Array(selectedAngles))
        }
        let request = ExportRequest(event: event, layout: layout, range: trim, watermarkPosition: watermarkPosition)
        do {
            let result = try await exportJob.run(request)
            resultURLs = result.outputURLs

            // Attempt to save to photo library and report any errors
            var saveErrors: [Error] = []
            for u in resultURLs {
                do {
                    try await PhotoLibrarySaver.save(u)
                } catch {
                    saveErrors.append(error)
                }
            }
            if saveErrors.isEmpty {
                savedToLibrary = true
            } else {
                // Export succeeded but save to library failed — report but keep resultURLs for sharing
                self.error = .photoLibraryDenied
            }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .exportFailed(underlying: error)
        }
    }
}
