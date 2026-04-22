import Foundation
import CoreMedia
import AVFoundation

// All stored properties are immutable after init (let), making this safe for
// concurrent use without any internal synchronization.
public final class TeslaCamScanner: ScannerProtocol, @unchecked Sendable {
    private let fileManager: FileManager
    private let defaultSegmentDuration: CMTime

    public init(
        fileManager: FileManager = .default,
        defaultSegmentDuration: CMTime = CMTime(seconds: 60, preferredTimescale: 600)
    ) {
        self.fileManager = fileManager
        self.defaultSegmentDuration = defaultSegmentDuration
    }

    public func scan(root: URL) async throws -> ScanResult {
        // If caller passed the USB root (containing TeslaCam/), unwrap once.
        let effectiveRoot: URL = {
            let nested = root.appendingPathComponent("TeslaCam")
            if fileManager.fileExists(atPath: nested.appendingPathComponent("SavedClips").path)
                || fileManager.fileExists(atPath: nested.appendingPathComponent("SentryClips").path)
                || fileManager.fileExists(atPath: nested.appendingPathComponent("RecentClips").path) {
                return nested
            }
            return root
        }()

        let eSaved = effectiveRoot.appendingPathComponent("SavedClips")
        let eSentry = effectiveRoot.appendingPathComponent("SentryClips")
        let eRecent = effectiveRoot.appendingPathComponent("RecentClips")

        let anyExists =
            fileManager.fileExists(atPath: eSaved.path)  ||
            fileManager.fileExists(atPath: eSentry.path) ||
            fileManager.fileExists(atPath: eRecent.path)
        guard anyExists else { throw AppError.notTeslaCamFolder }

        let savedEvents  = fileManager.fileExists(atPath: eSaved.path)  ? scanClipDirectory(eSaved,  type: .saved)  : []
        let sentryEvents = fileManager.fileExists(atPath: eSentry.path) ? scanClipDirectory(eSentry, type: .sentry) : []
        let recentSegs   = fileManager.fileExists(atPath: eRecent.path) ? scanRecentDirectory(eRecent)              : []

        return ScanResult(
            savedEvents: savedEvents.sorted(by: { $0.startTime > $1.startTime }),
            sentryEvents: sentryEvents.sorted(by: { $0.startTime > $1.startTime }),
            recentSegments: recentSegs
        )
    }

    // MARK: - per-event folders (Saved / Sentry)

    private func scanClipDirectory(_ dir: URL, type: EventType) -> [TeslaEvent] {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            return []
        }

        var out: [TeslaEvent] = []
        for child in children {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let startTime = FolderNameParser.parse(child.lastPathComponent) else { continue }

            let files = (try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
            let mp4s = files.filter { $0.pathExtension.lowercased() == "mp4" }
            let segments = SegmentAggregator.aggregate(urls: mp4s, defaultSegmentDuration: defaultSegmentDuration)
            guard !segments.isEmpty else { continue }

            let available = Set(segments.flatMap { $0.filesByAngle.keys })
            let metadataURL = child.appendingPathComponent("event.json")
            let metadata: EventMetadata? = {
                guard fileManager.fileExists(atPath: metadataURL.path),
                      let data = try? Data(contentsOf: metadataURL) else { return nil }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = TeslaCamScanner.eventJsonDateStrategy
                return try? decoder.decode(EventMetadata.self, from: data)
            }()
            let thumbURL = child.appendingPathComponent("thumb.png")
            let thumbnail: URL? = fileManager.fileExists(atPath: thumbURL.path) ? thumbURL : nil

            out.append(TeslaEvent(
                id: child.lastPathComponent,
                type: type,
                startTime: startTime,
                segments: segments,
                availableAngles: available,
                thumbnailURL: thumbnail,
                eventMetadata: metadata
            ))
        }
        return out
    }

    // MARK: - flat RecentClips

    private func scanRecentDirectory(_ dir: URL) -> [MinuteSegment] {
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mp4s = files.filter { $0.pathExtension.lowercased() == "mp4" }
        return SegmentAggregator.aggregate(urls: mp4s, defaultSegmentDuration: defaultSegmentDuration)
    }

    static let eventJsonDateStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: str) { return d }
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = f2.date(from: str) { return d }
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Unrecognized date string: \(str)"
        )
    }
}
