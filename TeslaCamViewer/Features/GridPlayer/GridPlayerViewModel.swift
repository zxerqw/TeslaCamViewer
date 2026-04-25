import Foundation
import Observation
import CoreMedia
import AVFoundation

@Observable
@MainActor
final class GridPlayerViewModel {
    let event: TeslaEvent
    let playback: PlaybackController
    var gridAngles: [CameraAngle]

    init(event: TeslaEvent, playback: PlaybackController) {
        self.event = event
        self.playback = playback
        self.gridAngles = CameraAngle.defaultGrid
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
