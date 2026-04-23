import Foundation
import CoreMedia
import AVFoundation

public protocol PlayerProtocol: AnyObject {
    var totalDuration: CMTime { get }
    var loadedAngles: [CameraAngle] { get }
    var currentTime: CMTime { get }
    var isPlaying: Bool { get }

    func load(event: TeslaEvent, angles: [CameraAngle]) async throws
    func play()
    func pause()
    func seek(to time: CMTime) async throws

    /// SwiftUI needs to show per-angle AVPlayerLayers. The view layer will ask for these players.
    func player(for angle: CameraAngle) -> AVPlayer?
}
