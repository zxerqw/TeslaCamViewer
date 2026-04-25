import Foundation

extension JSONDecoder.DateDecodingStrategy {
    /// Accepts ISO 8601 with or without fractional seconds, with or without timezone.
    /// Tesla's event.json writes "2024-07-15T14:32:01" (no tz, no fractions).
    static let iso8601WithOptionalFractionalSeconds: Self = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: str) { return d }

        let compact = ISO8601DateFormatter()
        compact.formatOptions = [.withInternetDateTime]
        if let d = compact.date(from: str) { return d }

        // Fallback: "yyyy-MM-dd'T'HH:mm:ss" without timezone — Tesla stores local time.
        let naive = DateFormatter()
        naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = .current
        if let d = naive.date(from: str) { return d }

        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Unrecognized date string: \(str)"
        )
    }
}
