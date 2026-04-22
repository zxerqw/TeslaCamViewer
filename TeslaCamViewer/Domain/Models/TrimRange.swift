import Foundation
import CoreMedia

public struct TrimRange: Equatable {
    public let start: CMTime
    public let end: CMTime

    /// Clamps both ends into `[.zero, totalDuration]`, orders them,
    /// and ensures a minimum range of 1s if both collapsed to the same value.
    public init(start: CMTime, end: CMTime, totalDuration: CMTime) {
        let minVal = CMTime.zero
        let maxVal = totalDuration
        var s = max(minVal, min(maxVal, start))
        var e = max(minVal, min(maxVal, end))
        if s > e { swap(&s, &e) }
        if s == e {
            let oneSec = CMTime(seconds: 1, preferredTimescale: 600)
            if e + oneSec <= maxVal {
                e = e + oneSec
            } else if s - oneSec >= minVal {
                s = s - oneSec
            }
        }
        self.start = s
        self.end = e
    }

    public static func fullRange(totalDuration: CMTime) -> TrimRange {
        TrimRange(start: .zero, end: totalDuration, totalDuration: totalDuration)
    }

    public var duration: CMTime { end - start }
}
