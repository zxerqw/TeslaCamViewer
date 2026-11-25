import Foundation
import CoreMedia

/// Finds where the moment that triggered a Sentry event sits on the playback
/// timeline, from event.json's `timestamp` and the minute-segment start times.
/// Same approach as Guyungy/Tesla-cam's calcEventSeconds: find the last
/// segment that starts before the event, add the offset inside it, then back
/// up a few seconds so the lead-up is visible.
public enum SentryEventLocator {
    public static let defaultLeadSeconds: Double = 5

    public static func eventTime(
        for event: TeslaEvent,
        segmentStartTimes: [CMTime],
        totalDuration: CMTime,
        leadSeconds: Double = defaultLeadSeconds
    ) -> CMTime? {
        guard event.type == .sentry,
              let trigger = event.eventMetadata?.timestamp,
              !event.segments.isEmpty else { return nil }

        // Timeline start of each segment: real durations when the player
        // reported them, otherwise the aggregated (placeholder) durations.
        let starts: [Double]
        if segmentStartTimes.count == event.segments.count {
            starts = segmentStartTimes.map { $0.seconds }
        } else {
            var acc = 0.0
            starts = event.segments.map { seg in
                defer { acc += seg.duration.seconds }
                return acc
            }
        }

        var position: Double?
        for i in stride(from: event.segments.count - 1, through: 0, by: -1) {
            let segStart = event.segments[i].timestamp
            if trigger >= segStart {
                position = starts[i] + trigger.timeIntervalSince(segStart)
                break
            }
        }
        guard var seconds = position else { return nil }

        let total = totalDuration.seconds
        guard total.isFinite, total > 0, seconds <= total + 1 else { return nil }
        seconds = min(max(0, seconds - leadSeconds), total)
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
