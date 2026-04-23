import Foundation

public struct ScanResult: Equatable {
    public var savedEvents: [TeslaEvent]
    public var sentryEvents: [TeslaEvent]
    /// RecentClips is returned UNCHUNKED. `LibraryStore` runs `RecentChunker`
    /// over these segments using the current `AppSettings.recentGapThresholdSeconds`.
    public var recentSegments: [MinuteSegment]

    public init(savedEvents: [TeslaEvent], sentryEvents: [TeslaEvent], recentSegments: [MinuteSegment]) {
        self.savedEvents = savedEvents
        self.sentryEvents = sentryEvents
        self.recentSegments = recentSegments
    }
}

public protocol ScannerProtocol {
    func scan(root: URL) async throws -> ScanResult
}
