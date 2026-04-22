import Foundation
import CoreMedia

public struct TeslaEvent: Identifiable, Equatable {
    public let id: String
    public let type: EventType
    public let startTime: Date
    public let segments: [MinuteSegment]
    public let availableAngles: Set<CameraAngle>
    public let thumbnailURL: URL?
    public let eventMetadata: EventMetadata?

    public init(
        id: String,
        type: EventType,
        startTime: Date,
        segments: [MinuteSegment],
        availableAngles: Set<CameraAngle>,
        thumbnailURL: URL?,
        eventMetadata: EventMetadata?
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.segments = segments
        self.availableAngles = availableAngles
        self.thumbnailURL = thumbnailURL
        self.eventMetadata = eventMetadata
    }

    public var totalDuration: CMTime {
        segments.reduce(CMTime.zero) { acc, seg in acc + seg.duration }
    }
}
