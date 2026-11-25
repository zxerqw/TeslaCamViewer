import Foundation
import Observation
import CoreMedia
import AVFoundation

@Observable
@MainActor
final class GridPlayerViewModel {
    let event: TeslaEvent
    let playback: PlaybackController
    enum GridLayout: Int, CaseIterable, Identifiable {
        case four = 4, six = 6
        var id: Int { rawValue }
        var label: String { self == .four ? "四画面" : "六画面" }
    }

    var gridLayout: GridLayout = .four
    private var fourAngles: [CameraAngle] = CameraAngle.defaultGrid
    private var sixAngles: [CameraAngle] = CameraAngle.sixGrid

    /// Angles of the currently selected layout (4 or 6 cells). Each layout
    /// keeps its own cell assignments when switching back and forth.
    var gridAngles: [CameraAngle] {
        get { gridLayout == .four ? fourAngles : sixAngles }
        set {
            if gridLayout == .four { fourAngles = newValue } else { sixAngles = newValue }
        }
    }
    var watermarkPosition: ExportRequest.WatermarkPosition

    init(event: TeslaEvent, playback: PlaybackController, defaultWatermark: ExportRequest.WatermarkPosition = .bottomLeft) {
        self.event = event
        self.playback = playback
        self.watermarkPosition = defaultWatermark
    }

    func load() async {
        // Load ALL available angles so the user can freely switch
        // grid cells to any angle (including B-pillar) without a reload.
        let allAvailable = Array(event.availableAngles)
        try? await playback.load(event: event, angles: allAvailable)
    }

    func setAngle(_ angle: CameraAngle, at index: Int) {
        guard (0..<gridAngles.count).contains(index) else { return }
        gridAngles[index] = angle
    }
}
