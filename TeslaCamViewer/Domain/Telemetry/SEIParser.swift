import Foundation

/// One decoded Tesla dashcam SEI message (protobuf `SeiMetadata`, see
/// github.com/teslamotors/dashcam dashcam.proto). Recorded by firmware
/// 2025.44.25+ on HW3/HW4, roughly one per video frame, usually absent while
/// the car is parked (e.g. most Sentry clips).
public struct SEIRawMessage: Equatable, Sendable {
    public var version: UInt32 = 0
    public var gearState: Int = 0            // 0 P, 1 D, 2 R, 3 N
    public var frameSeqNo: UInt64?
    public var vehicleSpeedMps: Float = 0
    public var acceleratorPedal: Float = 0
    public var steeringWheelAngle: Float = 0
    public var blinkerOnLeft = false
    public var blinkerOnRight = false
    public var brakeApplied = false
    public var autopilotState: Int = 0       // 0 none, 1 self-driving, 2 autosteer, 3 TACC
    public var latitudeDeg: Double = 0
    public var longitudeDeg: Double = 0
    public var headingDeg: Double = 0
    public var accelX: Double = 0            // m/s², forward/back
    public var accelY: Double = 0            // m/s², left/right
    public var accelZ: Double = 0            // m/s², up/down (includes gravity)
    /// Index of the video frame this SEI precedes (0-based, in decode order).
    public var frameIndex: Int = 0

    public init() {}
}

/// Result of scanning one MP4: SEI messages plus how many video frames were seen,
/// so a message's time = frameIndex / frameCount × clip duration.
public struct SEIScanResult: Sendable {
    public var messages: [SEIRawMessage]
    public var frameCount: Int
}

/// Streams a Tesla MP4 (AVCC, 4-byte NAL lengths) and extracts SEI telemetry.
/// Same algorithm as Tesla's dashcam-mp4.js / Guyungy Tesla-cam parseSEI.ts.
public enum SEIParser {

    /// Stop early when this many NALs were seen without a single Tesla SEI —
    /// footage without telemetry (old firmware / parked) then costs ~nothing.
    static let giveUpAfterNALsWithoutSEI = 900

    public static func scan(fileURL: URL) -> SEIScanResult {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else {
            return SEIScanResult(messages: [], frameCount: 0)
        }
        defer { try? fh.close() }
        let fileSize = (try? fh.seekToEnd()) ?? 0
        guard let (mdatOffset, mdatSize) = findMdat(fh, fileSize: fileSize) else {
            return SEIScanResult(messages: [], frameCount: 0)
        }
        return scanMdat(fh, offset: mdatOffset, size: mdatSize)
    }

    /// Convenience for tests: parse an in-memory MP4.
    public static func scan(data: Data) -> SEIScanResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sei-\(UUID().uuidString).mp4")
        try? data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return scan(fileURL: tmp)
    }

    // MARK: - MP4 box walk

    static func findMdat(_ fh: FileHandle, fileSize: UInt64) -> (UInt64, UInt64)? {
        var pos: UInt64 = 0
        while pos + 8 <= fileSize {
            try? fh.seek(toOffset: pos)
            guard let hdr = try? fh.read(upToCount: 16), hdr.count >= 8 else { return nil }
            let b = [UInt8](hdr)
            var size = UInt64(be32(b, 0))
            let type = String(bytes: b[4..<8], encoding: .ascii) ?? ""
            var headerSize: UInt64 = 8
            if size == 1 {
                guard b.count >= 16 else { return nil }
                size = (UInt64(be32(b, 8)) << 32) | UInt64(be32(b, 12))
                headerSize = 16
            } else if size == 0 {
                size = fileSize - pos
            }
            if size < headerSize { return nil }
            if type == "mdat" {
                let avail = min(size, fileSize - pos)
                return (pos + headerSize, avail - headerSize)
            }
            pos += size
        }
        return nil
    }

    // MARK: - NAL walk (chunked)

    static func scanMdat(_ fh: FileHandle, offset: UInt64, size: UInt64) -> SEIScanResult {
        let chunk = 4 * 1024 * 1024
        var buf = [UInt8]()
        var head = 0                      // read position inside buf
        var filePos = offset
        let end = offset + size
        var messages: [SEIRawMessage] = []
        var frames = 0
        var nalsSeen = 0

        func fill(_ need: Int) -> Bool {
            while buf.count - head < need {
                guard filePos < end else { return false }
                if head > 0 && head > buf.count / 2 {
                    buf.removeSubrange(0..<head); head = 0
                }
                let take = Int(min(UInt64(max(chunk, need)), end - filePos))
                try? fh.seek(toOffset: filePos)
                guard let d = try? fh.read(upToCount: take), !d.isEmpty else { return false }
                buf.append(contentsOf: d)
                filePos += UInt64(d.count)
            }
            return true
        }

        while fill(4) {
            let nalSize = Int(be32(buf, head))
            guard nalSize >= 1, UInt64(nalSize) <= size else { break }   // desync
            guard fill(4 + nalSize) else { break }
            let s = head + 4
            let nalType = buf[s] & 0x1F
            nalsSeen += 1
            if nalType == 6, nalSize >= 2, buf[s + 1] == 5 {
                if var m = decodeSei(buf, from: s, count: nalSize) {
                    m.frameIndex = frames
                    messages.append(m)
                }
            } else if nalType == 1 || nalType == 5 {
                frames += 1
            }
            head = s + nalSize
            if messages.isEmpty && nalsSeen >= giveUpAfterNALsWithoutSEI { break }
        }
        return SEIScanResult(messages: messages, frameCount: frames)
    }

    // MARK: - SEI → protobuf

    /// Skip NAL header + payload type + payload size (3 bytes), then the 0x42
    /// padding (at least one), require 0x69, drop the trailing RBSP stop byte,
    /// remove emulation-prevention bytes and decode the protobuf.
    static func decodeSei(_ b: [UInt8], from s: Int, count n: Int) -> SEIRawMessage? {
        guard n >= 4 else { return nil }
        let e = s + n
        var i = s + 3
        while i < e && b[i] == 0x42 { i += 1 }
        guard i > s + 3, i + 1 < e, b[i] == 0x69 else { return nil }
        let payload = stripEmulation(b, from: i + 1, to: e - 1)
        return decodeProtobuf(payload)
    }

    static func stripEmulation(_ b: [UInt8], from: Int, to: Int) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(max(0, to - from))
        var zeros = 0
        var k = from
        while k < to {
            let x = b[k]; k += 1
            if zeros >= 2 && x == 0x03 { zeros = 0; continue }
            out.append(x)
            zeros = x == 0 ? zeros + 1 : 0
        }
        return out
    }

    static func decodeProtobuf(_ d: [UInt8]) -> SEIRawMessage? {
        var m = SEIRawMessage()
        if d.isEmpty { return m }   // proto3: every field at its default
        var p = 0
        var any = false
        func varint() -> UInt64? {
            var r: UInt64 = 0, shift: UInt64 = 0
            while p < d.count && shift < 64 {
                let x = d[p]; p += 1
                r |= UInt64(x & 0x7F) << shift
                if x & 0x80 == 0 { return r }
                shift += 7
            }
            return nil
        }
        func f32() -> Float? {
            guard p + 4 <= d.count else { return nil }
            let v = UInt32(d[p]) | UInt32(d[p+1]) << 8 | UInt32(d[p+2]) << 16 | UInt32(d[p+3]) << 24
            p += 4; return Float(bitPattern: v)
        }
        func f64() -> Double? {
            guard p + 8 <= d.count else { return nil }
            var v: UInt64 = 0
            for k in 0..<8 { v |= UInt64(d[p + k]) << (8 * UInt64(k)) }
            p += 8; return Double(bitPattern: v)
        }
        while p < d.count {
            guard let tag = varint() else { break }
            let field = Int(tag >> 3), wire = Int(tag & 7)
            switch (field, wire) {
            case (1, 0): guard let v = varint() else { return any ? m : nil }; m.version = UInt32(truncatingIfNeeded: v)
            case (2, 0): guard let v = varint() else { return any ? m : nil }; m.gearState = Int(truncatingIfNeeded: v)
            case (3, 0): guard let v = varint() else { return any ? m : nil }; m.frameSeqNo = v
            case (4, 5): guard let v = f32() else { return any ? m : nil }; m.vehicleSpeedMps = v
            case (5, 5): guard let v = f32() else { return any ? m : nil }; m.acceleratorPedal = v
            case (6, 5): guard let v = f32() else { return any ? m : nil }; m.steeringWheelAngle = v
            case (7, 0): guard let v = varint() else { return any ? m : nil }; m.blinkerOnLeft = v != 0
            case (8, 0): guard let v = varint() else { return any ? m : nil }; m.blinkerOnRight = v != 0
            case (9, 0): guard let v = varint() else { return any ? m : nil }; m.brakeApplied = v != 0
            case (10, 0): guard let v = varint() else { return any ? m : nil }; m.autopilotState = Int(truncatingIfNeeded: v)
            case (11, 1): guard let v = f64() else { return any ? m : nil }; m.latitudeDeg = v
            case (12, 1): guard let v = f64() else { return any ? m : nil }; m.longitudeDeg = v
            case (13, 1): guard let v = f64() else { return any ? m : nil }; m.headingDeg = v
            case (14, 1): guard let v = f64() else { return any ? m : nil }; m.accelX = v
            case (15, 1): guard let v = f64() else { return any ? m : nil }; m.accelY = v
            case (16, 1): guard let v = f64() else { return any ? m : nil }; m.accelZ = v
            default:
                // unknown field: skip by wire type
                switch wire {
                case 0: guard varint() != nil else { return any ? m : nil }
                case 1: p += 8
                case 2: guard let len = varint() else { return any ? m : nil }; p += Int(len)
                case 5: p += 4
                default: return any ? m : nil
                }
                if p > d.count { return any ? m : nil }
                continue
            }
            any = true
        }
        return any ? m : nil
    }

    @inline(__always)
    static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) << 24 | UInt32(b[o+1]) << 16 | UInt32(b[o+2]) << 8 | UInt32(b[o+3])
    }
    @inline(__always)
    static func be32(_ b: ArraySlice<UInt8>, _ o: Int) -> UInt32 {
        let s = b.startIndex + o
        return UInt32(b[s]) << 24 | UInt32(b[s+1]) << 16 | UInt32(b[s+2]) << 8 | UInt32(b[s+3])
    }
}
