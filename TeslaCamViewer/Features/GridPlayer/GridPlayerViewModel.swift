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
        try? await playback.load(event: event, angles: gridAngles)
    }

    func setAngle(_ angle: CameraAngle, at index: Int) {
        guard (0..<gridAngles.count).contains(index) else { return }
        gridAngles[index] = angle
        Task { await load() }
    }
}
