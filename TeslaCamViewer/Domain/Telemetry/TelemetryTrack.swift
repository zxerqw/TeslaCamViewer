import Foundation

/// Telemetry at one instant, already converted to display units.
public struct TelemetrySample: Equatable, Sendable {
    public enum Gear: String, Sendable { case P, D, R, N }
    public enum Autopilot: Sendable { case none, fsd, autosteer, tacc }

    /// Position on the playback timeline (seconds from the start of the event).
    public var time: Double
    public var speedKph: Double
    public var gear: Gear
    public var steeringDeg: Double
    public var throttlePct: Double
    public var brake: Bool
    public var blinkerLeft: Bool
    public var blinkerRight: Bool
    public var autopilot: Autopilot
    public var latitude: Double
    public var longitude: Double
    public var heading: Double
    /// Longitudinal G (+ accelerating, − braking) and lateral G.
    public var gLongitudinal: Double
    public var gLateral: Double

    public var gTotal: Double { (gLongitudinal * gLongitudinal + gLateral * gLateral).squareRoot() }
}

/// All telemetry samples of an event, sorted by timeline time.
public struct TelemetryTrack: Sendable {
    public static let standardGravity = 9.80665
    public let samples: [TelemetrySample]

    public init(samples: [TelemetrySample]) {
        self.samples = samples.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Latest sample at or before `t` (within `maxGap` seconds), else the first
    /// sample if `t` is just before it.
    public func sample(at t: Double, maxGap: Double = 1.5) -> TelemetrySample? {
        guard !samples.isEmpty else { return nil }
        var lo = 0, hi = samples.count - 1
        if t < samples[0].time { return samples[0].time - t <= maxGap ? samples[0] : nil }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if samples[mid].time <= t { lo = mid } else { hi = mid - 1 }
        }
        let s = samples[lo]
        return t - s.time <= maxGap ? s : nil
    }

    /// Build a track from per-segment SEI scans.
    /// - Parameters:
    ///   - scans: one scan per segment (nil when that segment had no file).
    ///   - segmentStarts: timeline start of each segment (seconds).
    ///   - segmentDurations: real duration of each segment (seconds).
    public static func build(scans: [SEIScanResult?], segmentStarts: [Double], segmentDurations: [Double]) -> TelemetryTrack {
        // Accelerator pedal: schema says 0–1, real footage stores 0–100.
        let allPedals = scans.compactMap { $0 }.flatMap { $0.messages.map { Double($0.acceleratorPedal) } }
        let pedalIsFraction = !allPedals.isEmpty && (allPedals.max() ?? 0) <= 1.0001
        let g = standardGravity
        var out: [TelemetrySample] = []
        for (i, scanOpt) in scans.enumerated() {
            guard let scan = scanOpt, !scan.messages.isEmpty,
                  i < segmentStarts.count, i < segmentDurations.count else { continue }
            let start = segmentStarts[i], dur = max(0.001, segmentDurations[i])
            let frames = max(scan.frameCount, (scan.messages.last?.frameIndex ?? 0) + 1)
            for m in scan.messages {
                let t = start + min(dur, Double(m.frameIndex) / Double(frames) * dur)
                let gear: TelemetrySample.Gear = [0: .P, 1: .D, 2: .R, 3: .N][m.gearState] ?? .P
                var kph = Double(m.vehicleSpeedMps) * 3.6
                if !kph.isFinite || kph < 0 { kph = 0 }
                kph = min(kph, 300)
                if gear == .P && kph < 1.5 { kph = 0 }
                let pedal = Double(m.acceleratorPedal)
                let ap: TelemetrySample.Autopilot = [1: .fsd, 2: .autosteer, 3: .tacc][m.autopilotState] ?? .none
                out.append(TelemetrySample(
                    time: t,
                    speedKph: kph,
                    gear: gear,
                    steeringDeg: max(-900, min(900, Double(m.steeringWheelAngle))),
                    throttlePct: max(0, min(100, pedalIsFraction ? pedal * 100 : pedal)),
                    brake: m.brakeApplied,
                    blinkerLeft: m.blinkerOnLeft,
                    blinkerRight: m.blinkerOnRight,
                    autopilot: ap,
                    latitude: m.latitudeDeg,
                    longitude: m.longitudeDeg,
                    heading: m.headingDeg,
                    gLongitudinal: m.accelX.isFinite ? m.accelX / g : 0,
                    gLateral: m.accelY.isFinite ? m.accelY / g : 0
                ))
            }
        }
        return TelemetryTrack(samples: out)
    }

    /// Short one-line text for the exported video, e.g. "56 km/h  D  纵向 -0.32G  横向 0.10G".
    public static func overlayLine(_ s: TelemetrySample) -> String {
        var parts = ["\(Int(s.speedKph.rounded())) km/h", s.gear.rawValue,
                     String(format: "纵向 %+.2fG", s.gLongitudinal),
                     String(format: "横向 %+.2fG", s.gLateral)]
        if s.brake { parts.append("刹车") }
        switch s.autopilot {
        case .fsd: parts.append("FSD")
        case .autosteer: parts.append("AP")
        case .tacc: parts.append("TACC")
        case .none: break
        }
        return parts.joined(separator: "  ")
    }
}
