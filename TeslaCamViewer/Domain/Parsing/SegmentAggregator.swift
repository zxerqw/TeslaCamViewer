import Foundation
import CoreMedia

public enum SegmentAggregator {
    /// Groups a list of file URLs by timestamp into MinuteSegments.
    /// `defaultSegmentDuration` is used as a placeholder duration; the Scanner
    /// may replace it with the actual asset duration once it probes AVAssets.
    public static func aggregate(
        urls: [URL],
        defaultSegmentDuration: CMTime
    ) -> [MinuteSegment] {
        var byTimestamp: [Date: [CameraAngle: URL]] = [:]
        for url in urls {
            guard let parsed = FilenameParser.parse(url.lastPathComponent) else { continue }
            byTimestamp[parsed.timestamp, default: [:]][parsed.angle] = url
        }
        return byTimestamp
            .sorted { $0.key < $1.key }
            .map { (timestamp, files) in
                MinuteSegment(timestamp: timestamp, duration: defaultSegmentDuration, filesByAngle: files)
            }
    }
}
