import Foundation
import CoreMedia

/// Reads SEI telemetry for every segment of an event (front camera first,
/// any other angle as fallback) off the main thread.
public enum TelemetryLoader {
    static let preferredAngles: [CameraAngle] = [.front, .back, .leftRepeater, .rightRepeater, .leftPillar, .rightPillar]

    public static func load(event: TeslaEvent, segmentStartTimes: [CMTime], totalDuration: CMTime) async -> TelemetryTrack {
        let segments = event.segments
        let starts: [Double]
        if segmentStartTimes.count == segments.count {
            starts = segmentStartTimes.map { $0.seconds }
        } else {
            var acc = 0.0
            starts = segments.map { s in defer { acc += s.duration.seconds }; return acc }
        }
        let total = totalDuration.seconds.isFinite && totalDuration.seconds > 0
            ? totalDuration.seconds : (starts.last ?? 0) + (segments.last?.duration.seconds ?? 60)
        let durations: [Double] = starts.indices.map { i in
            i + 1 < starts.count ? starts[i + 1] - starts[i] : total - starts[i]
        }
        return await Task.detached(priority: .utility) {
            var scans: [SEIScanResult?] = []
            for seg in segments {
                var result: SEIScanResult?
                for angle in preferredAngles {
                    guard let url = seg.filesByAngle[angle] else { continue }
                    let r = SEIParser.scan(fileURL: url)
                    result = r
                    if !r.messages.isEmpty { break }
                    // a camera with frames but no SEI means this clip has none
                    if r.frameCount > 0 { break }
                }
                scans.append(result)
                if Task.isCancelled { break }
            }
            return TelemetryTrack.build(scans: scans, segmentStarts: starts, segmentDurations: durations)
        }.value
    }
}
