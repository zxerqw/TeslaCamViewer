import Foundation

public enum FolderNameParser {
    /// Parses a Tesla event folder name `"YYYY-MM-DD_HH-MM-SS"` into a UTC-anchored `Date`.
    /// Returns nil for anything else (hidden folders, names with extra characters, etc.).
    public static func parse(_ name: String) -> Date? {
        // Tesla folder names are purely ASCII digits + '-' + '_' and always 19 chars.
        guard name.count == 19 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: name)
    }
}
