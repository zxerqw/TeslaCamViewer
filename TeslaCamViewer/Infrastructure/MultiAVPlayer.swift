import Foundation
import CoreMedia
import AVFoundation

public final class MultiAVPlayer: PlayerProtocol, @unchecked Sendable {
    public private(set) var totalDuration: CMTime = .zero
    public private(set) var loadedAngles: [CameraAngle] = []
    public var currentTime: CMTime {
        playersByAngle.values.first?.currentTime() ?? .zero
    }
    public var isPlaying: Bool {
        playersByAngle.values.first?.timeControlStatus == .playing
    }

    public private(set) var segmentStartTimes: [CMTime] = []

    private var playersByAngle: [CameraAngle: AVPlayer] = [:]

    public init() {}

    public func load(event: TeslaEvent, angles requested: [CameraAngle]) async throws {
        teardown()

        let angles = requested.filter { event.availableAngles.contains($0) }
        var players: [CameraAngle: AVPlayer] = [:]
        var startsByAngle: [CameraAngle: [CMTime]] = [:]

        for angle in angles {
            let comp = AVMutableComposition()
            let track = comp.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )!
            var cursor: CMTime = .zero
            var starts: [CMTime] = []
            for seg in event.segments {
                starts.append(cursor)
                guard let url = seg.filesByAngle[angle] else {
                    // Leave a gap of `seg.duration` so playhead stays aligned with other angles.
                    cursor = cursor + seg.duration
                    continue
                }
                let asset = AVURLAsset(url: url)
                do {
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    guard let vt = videoTracks.first else { cursor = cursor + seg.duration; continue }
                    let dur = try await asset.load(.duration)
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: cursor)
                    cursor = cursor + dur
                } catch {
                    cursor = cursor + seg.duration   // skip broken file, keep alignment
                }
            }
            startsByAngle[angle] = starts
            let item = AVPlayerItem(asset: comp)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.sourceClock = CMClockGetHostTimeClock()
            players[angle] = player
        }

        playersByAngle = players
        loadedAngles = angles
        // Same angle that drives the playhead observer in PlaybackController.
        segmentStartTimes = angles.first.flatMap { startsByAngle[$0] } ?? []
        totalDuration = event.totalDuration
    }

    public func play()  { playersByAngle.values.forEach { $0.play()  } }
    public func pause() { playersByAngle.values.forEach { $0.pause() } }

    public func seek(to time: CMTime) async throws {
        await withTaskGroup(of: Void.self) { group in
            for p in playersByAngle.values {
                group.addTask {
                    await withCheckedContinuation { cont in
                        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    public func player(for angle: CameraAngle) -> AVPlayer? { playersByAngle[angle] }

    public func debugPerAnglePlayhead() -> [CMTime] {
        playersByAngle.values.map { $0.currentTime() }
    }

    private func teardown() {
        playersByAngle.values.forEach { $0.pause() }
        playersByAngle.removeAll()
        loadedAngles.removeAll()
        segmentStartTimes.removeAll()
        totalDuration = .zero
    }
}
