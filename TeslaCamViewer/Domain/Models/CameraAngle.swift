import Foundation

public enum CameraAngle: String, CaseIterable, Codable, Hashable {
    case front
    case back
    case leftRepeater
    case rightRepeater
    case leftPillar
    case rightPillar

    /// Suffix Tesla uses in the MP4 filename, e.g. "2024-07-15_14-32-01-**front**.mp4".
    public var fileSuffix: String {
        switch self {
        case .front:          return "front"
        case .back:           return "back"
        case .leftRepeater:   return "left_repeater"
        case .rightRepeater:  return "right_repeater"
        case .leftPillar:     return "left_pillar"
        case .rightPillar:    return "right_pillar"
        }
    }

    public init?(fileSuffix: String) {
        guard let match = CameraAngle.allCases.first(where: { $0.fileSuffix == fileSuffix })
        else { return nil }
        self = match
    }

    /// The 4 angles pre-selected for the default grid when a user opens an event.
    public static let defaultGrid: [CameraAngle] = [
        .front, .back, .leftRepeater, .rightRepeater
    ]

    /// The 6-camera grid (3 columns × 2 rows): pillars flank the front camera
    /// on top, repeaters flank the rear camera below.
    public static let sixGrid: [CameraAngle] = [
        .leftPillar, .front, .rightPillar,
        .leftRepeater, .back, .rightRepeater
    ]

    /// Number of grid columns for a grid of `count` cells (2 rows always).
    public static func gridColumns(forCount count: Int) -> Int {
        count > 4 ? 3 : 2
    }
}
