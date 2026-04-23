import Foundation

public enum RecentChunker {
    /// Splits a time-sorted list of MinuteSegments into event-level chunks.
    /// Two adjacent segments belong to the same chunk if the gap between
    /// `previous.end` and `next.start` is **≤** `gapThresholdSeconds`.
    public static func chunk(
        segments: [MinuteSegment],
        gapThresholdSeconds: Int
    ) -> [[MinuteSegment]] {
        guard !segments.isEmpty else { return [] }
        let threshold = TimeInterval(gapThresholdSeconds)
        var chunks: [[MinuteSegment]] = [[segments[0]]]
        for next in segments.dropFirst() {
            let prev = chunks[chunks.count - 1].last!
            let prevEnd = prev.timestamp.addingTimeInterval(prev.duration.seconds)
            let gap = next.timestamp.timeIntervalSince(prevEnd)
            if gap <= threshold {
                chunks[chunks.count - 1].append(next)
            } else {
                chunks.append([next])
            }
        }
        return chunks
    }
}
