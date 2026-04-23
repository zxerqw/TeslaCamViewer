import Foundation
import CoreMedia

public struct MinuteSegment: Equatable {
    public let timestamp: Date
    public let duration: CMTime
    public let filesByAngle: [CameraAngle: URL]

    public init(timestamp: Date, duration: CMTime, filesByAngle: [CameraAngle: URL]) {
        self.timestamp = timestamp
        self.duration = duration
        self.filesByAngle = filesByAngle
    }
}
