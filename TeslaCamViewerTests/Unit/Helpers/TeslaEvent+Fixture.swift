import Foundation
import CoreMedia
@testable import TeslaCamViewer

extension TeslaEvent {
    static func fixture(
        id: String = "fix-1",
        type: EventType = .saved,
        startTime: Date = Date(timeIntervalSince1970: 1_721_050_321),
        segments: [MinuteSegment],
        thumbnailURL: URL? = nil,
        eventMetadata: EventMetadata? = nil
    ) -> TeslaEvent {
        TeslaEvent(
            id: id,
            type: type,
            startTime: startTime,
            segments: segments,
            availableAngles: Set(segments.flatMap { $0.filesByAngle.keys }),
            thumbnailURL: thumbnailURL,
            eventMetadata: eventMetadata
        )
    }
}

extension MinuteSegment {
    static func fixture(
        offsetSeconds: Double = 0,
        durationSeconds: Double = 60,
        angles: [CameraAngle] = [.front, .back, .leftRepeater, .rightRepeater]
    ) -> MinuteSegment {
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        let files = Dictionary(uniqueKeysWithValues: angles.map {
            ($0, URL(fileURLWithPath: "/tmp/\(Int(offsetSeconds))-\($0.fileSuffix).mp4"))
        })
        return MinuteSegment(
            timestamp: base.addingTimeInterval(offsetSeconds),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            filesByAngle: files
        )
    }
}
