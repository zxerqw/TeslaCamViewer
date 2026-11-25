import Foundation

public struct EventMetadata: Codable, Equatable {
    public let timestamp: Date?
    public let city: String?
    public let reason: String?
    /// Which camera fired the Sentry event (event.json `camera`, e.g. "0").
    public let camera: String?

    public init(timestamp: Date?, city: String?, reason: String?, camera: String? = nil) {
        self.timestamp = timestamp
        self.city = city
        self.reason = reason
        self.camera = camera
    }

    private enum CodingKeys: String, CodingKey { case timestamp, city, reason, camera }

    // Tolerant decoding: a field with an unexpected type is treated as missing
    // instead of discarding the whole event.json.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try? c.decodeIfPresent(Date.self, forKey: .timestamp)
        city = try? c.decodeIfPresent(String.self, forKey: .city)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        if let s = try? c.decodeIfPresent(String.self, forKey: .camera) {
            camera = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .camera) {
            camera = String(i)
        } else {
            camera = nil
        }
    }

    /// Camera that triggered a Sentry event. Mapping per community-documented
    /// TeslaCam values (same as Guyungy/Tesla-cam); unknown values → nil.
    public var triggerAngle: CameraAngle? {
        guard let cam = camera?.trimmingCharacters(in: .whitespaces) else { return nil }
        switch cam {
        case "0": return .front
        case "3": return .leftRepeater
        case "4": return .rightRepeater
        case "5": return .back
        default:  return nil
        }
    }
}
