import Foundation
import CoreMedia

public struct ExportRequest {
    public enum Layout: Equatable {
        case singlesPerAngle(angles: [CameraAngle])
        case gridCombined(angles: [CameraAngle])

        public var isValid: Bool {
            switch self {
            case .singlesPerAngle(let angles): return !angles.isEmpty
            case .gridCombined(let angles):    return angles.count == 4 || angles.count == 6
            }
        }

        public var angles: [CameraAngle] {
            switch self {
            case .singlesPerAngle(let a), .gridCombined(let a): return a
            }
        }
    }

    public enum WatermarkPosition: String, Codable, CaseIterable, Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public let event: TeslaEvent
    public let layout: Layout
    public let range: TrimRange
    public let watermarkPosition: WatermarkPosition

    public init(event: TeslaEvent, layout: Layout, range: TrimRange, watermarkPosition: WatermarkPosition) {
        self.event = event
        self.layout = layout
        self.range = range
        self.watermarkPosition = watermarkPosition
    }
}
