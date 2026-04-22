import Foundation

public struct EventMetadata: Codable, Equatable {
    public let timestamp: Date?
    public let city: String?
    public let reason: String?

    public init(timestamp: Date?, city: String?, reason: String?) {
        self.timestamp = timestamp
        self.city = city
        self.reason = reason
    }
}
