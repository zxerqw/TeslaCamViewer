import Foundation

public enum FilenameParser {
    public struct ParsedFile: Equatable {
        public let timestamp: Date
        public let angle: CameraAngle
    }

    /// Parses `"YYYY-MM-DD_HH-MM-SS-{angle}.mp4"`. Returns nil for anything else.
    public static func parse(_ filename: String) -> ParsedFile? {
        // Require `.mp4` suffix.
        guard filename.hasSuffix(".mp4") else { return nil }
        let base = String(filename.dropLast(4))   // strip ".mp4"

        // Minimum length for "YYYY-MM-DD_HH-MM-SS-X" = 21
        guard base.count > 20 else { return nil }

        // Timestamp is first 19 chars, expected "YYYY-MM-DD_HH-MM-SS"
        let tsPart = String(base.prefix(19))
        guard base.dropFirst(19).first == "-" else { return nil }
        let anglePart = String(base.dropFirst(20))   // after timestamp '-'
        guard let angle = CameraAngle(fileSuffix: anglePart) else { return nil }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let ts = f.date(from: tsPart) else { return nil }
        return ParsedFile(timestamp: ts, angle: angle)
    }
}
