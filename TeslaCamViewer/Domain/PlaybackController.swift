import Foundation
import CoreMedia
import AVFoundation
import Observation

@Observable
@MainActor
public final class PlaybackController {
    public private(set) var totalDuration: CMTime = .zero
    public private(set) var currentTime: CMTime = .zero
    public private(set) var isPlaying: Bool = false
    public private(set) var loadedAngles: [CameraAngle] = []
    public private(set) var trim: TrimRange = TrimRange(
        start: .zero,
        end: .init(seconds: 1, preferredTimescale: 600),
        totalDuration: .init(seconds: 1, preferredTimescale: 600)
    )

    @ObservationIgnored private let player: PlayerProtocol
    @ObservationIgnored private var timeObserver: Any?

    public init(player: PlayerProtocol) {
        self.player = player
    }

    public func load(event: TeslaEvent, angles: [CameraAngle]) async throws {
        try await player.load(event: event, angles: angles)
        totalDuration = player.totalDuration
        loadedAngles = player.loadedAngles
        trim = TrimRange.fullRange(totalDuration: totalDuration)
        attachTimeObserver()
    }

    public func play()  { player.play();  isPlaying = true }
    public func pause() { player.pause(); isPlaying = false }

    public func seek(to t: CMTime) async throws {
        try await player.seek(to: t)
        currentTime = t
    }

    public func setTrim(start: CMTime, end: CMTime) {
        trim = TrimRange(start: start, end: end, totalDuration: totalDuration)
    }

    public func player(for angle: CameraAngle) -> AVPlayer? { player.player(for: angle) }

    private func attachTimeObserver() {
        guard let p = player.player(for: loadedAngles.first ?? .front) else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                self?.currentTime = t
                self?.isPlaying = p.timeControlStatus == .playing
            }
        }
    }
}
