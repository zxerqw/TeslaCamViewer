import Foundation

public struct AppSettings: Codable, Equatable {
    public static let minRecentGapSeconds = 60        // 1 minute (matches spec slider min)
    public static let maxRecentGapSeconds = 1_800     // 30 minutes

    public var recentGapThresholdSeconds: Int
    public var defaultWatermarkPosition: ExportRequest.WatermarkPosition

    public init(
        recentGapThresholdSeconds: Int = 300,
        defaultWatermarkPosition: ExportRequest.WatermarkPosition = .bottomLeft
    ) {
        self.recentGapThresholdSeconds = max(
            Self.minRecentGapSeconds,
            min(Self.maxRecentGapSeconds, recentGapThresholdSeconds)
        )
        self.defaultWatermarkPosition = defaultWatermarkPosition
    }
}
