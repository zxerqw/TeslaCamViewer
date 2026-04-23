import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import UIKit

public final class AVComposer: ComposerProtocol, @unchecked Sendable {
    public init() {}

    // MARK: Single angle

    public func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws {
        let (composition, videoComp, renderSize) = try await singleAngleComposition(
            request: request, angle: angle
        )
        try await runExport(
            composition: composition,
            videoComposition: videoComp,
            renderSize: renderSize,
            watermarkBakeInfo: .init(
                position: request.watermarkPosition,
                layoutKind: .single,
                eventStart: request.event.startTime,
                rangeStart: request.range.start
            ),
            to: url
        )
    }

    // MARK: Grid

    public func exportGrid(request: ExportRequest, to url: URL) async throws {
        guard case .gridCombined(let angles) = request.layout, angles.count == 4 else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "AVComposer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "gridCombined requires exactly 4 angles"]
            ))
        }
        let (composition, videoComp) = try await gridComposition(
            request: request, angles: angles, renderSize: CGSize(width: 1920, height: 1080)
        )
        try await runExport(
            composition: composition,
            videoComposition: videoComp,
            renderSize: CGSize(width: 1920, height: 1080),
            watermarkBakeInfo: .init(
                position: request.watermarkPosition,
                layoutKind: .grid(angles: angles),
                eventStart: request.event.startTime,
                rangeStart: request.range.start
            ),
            to: url
        )
    }

    // MARK: - single angle helpers

    private func singleAngleComposition(
        request: ExportRequest,
        angle: CameraAngle
    ) async throws -> (AVMutableComposition, AVMutableVideoComposition, CGSize) {
        let comp = AVMutableComposition()
        let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let trimDuration = request.range.end - request.range.start

        var eventCursor: CMTime = .zero
        var compositionCursor: CMTime = .zero
        var renderSize = CGSize(width: 1280, height: 960)

        for seg in request.event.segments {
            let segStart = eventCursor
            let segEnd = eventCursor + seg.duration
            defer { eventCursor = segEnd }

            let overlapStart = max(segStart, request.range.start)
            let overlapEnd = min(segEnd, request.range.end)
            guard overlapStart < overlapEnd else { continue }

            guard let u = seg.filesByAngle[angle] else {
                compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                continue
            }
            let asset = AVURLAsset(url: u)
            do {
                let vts = try await asset.loadTracks(withMediaType: .video)
                guard let vt = vts.first else {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                    continue
                }
                let fileOffset = overlapStart - segStart
                let insertDuration = overlapEnd - overlapStart
                try track.insertTimeRange(
                    CMTimeRange(start: fileOffset, duration: insertDuration),
                    of: vt,
                    at: compositionCursor
                )
                let sz = try await vt.load(.naturalSize)
                if sz.width > 0, sz.height > 0 { renderSize = sz }
                compositionCursor = compositionCursor + insertDuration
            } catch {
                compositionCursor = compositionCursor + (overlapEnd - overlapStart)
            }
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: trimDuration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instr.layerInstructions = [layer]
        videoComp.instructions = [instr]

        return (comp, videoComp, renderSize)
    }

    // MARK: - grid helpers

    private func gridComposition(
        request: ExportRequest,
        angles: [CameraAngle],
        renderSize: CGSize
    ) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let comp = AVMutableComposition()
        let cellW = renderSize.width / 2
        let cellH = renderSize.height / 2
        let trimDuration = request.range.end - request.range.start

        var layerInstrs: [AVMutableVideoCompositionLayerInstruction] = []

        for (idx, angle) in angles.enumerated() {
            let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            var eventCursor: CMTime = .zero
            var compositionCursor: CMTime = .zero
            var nativeSize = CGSize(width: 1280, height: 960)

            for seg in request.event.segments {
                let segStart = eventCursor
                let segEnd = eventCursor + seg.duration
                defer { eventCursor = segEnd }

                let overlapStart = max(segStart, request.range.start)
                let overlapEnd = min(segEnd, request.range.end)
                guard overlapStart < overlapEnd else { continue }

                guard let u = seg.filesByAngle[angle] else {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                    continue
                }
                let asset = AVURLAsset(url: u)
                do {
                    let vts = try await asset.loadTracks(withMediaType: .video)
                    guard let vt = vts.first else {
                        compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                        continue
                    }
                    let fileOffset = overlapStart - segStart
                    let insertDuration = overlapEnd - overlapStart
                    try track.insertTimeRange(
                        CMTimeRange(start: fileOffset, duration: insertDuration),
                        of: vt,
                        at: compositionCursor
                    )
                    let sz = try await vt.load(.naturalSize)
                    if sz.width > 0, sz.height > 0 { nativeSize = sz }
                    compositionCursor = compositionCursor + insertDuration
                } catch {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                }
            }

            // Scale and position into 1/4 cell.
            let scale = max(cellW / nativeSize.width, cellH / nativeSize.height)
            let scaled = CGSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
            let row = idx / 2, col = idx % 2   // 0=TL, 1=TR, 2=BL, 3=BR
            let cellX = CGFloat(col) * cellW
            let cellY = CGFloat(row) * cellH
            let offsetX = cellX + (cellW - scaled.width) / 2
            let offsetY = cellY + (cellH - scaled.height) / 2

            let t = CGAffineTransform(translationX: offsetX, y: offsetY)
                .scaledBy(x: scale, y: scale)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(t, at: .zero)
            layerInstrs.append(layer)
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: trimDuration)
        instr.layerInstructions = layerInstrs
        videoComp.instructions = [instr]

        return (comp, videoComp)
    }

    // MARK: - watermark + export

    struct WatermarkBakeInfo {
        enum LayoutKind { case single, grid(angles: [CameraAngle]) }
        let position: ExportRequest.WatermarkPosition
        let layoutKind: LayoutKind
        let eventStart: Date
        let rangeStart: CMTime
    }

    private func runExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        watermarkBakeInfo info: WatermarkBakeInfo,
        to url: URL
    ) async throws {
        // AVVideoCompositionCoreAnimationTool uses OpenGL ES + IOSurface via XPC, which crashes
        // on the iOS simulator due to an XPC sandbox violation (_xpc_api_misuse / _ioSurfaceClientCreate).
        // Skip watermark attachment when running in a simulator context.
        #if !targetEnvironment(simulator)
        await MainActor.run {
            attachWatermark(videoComposition: videoComposition, renderSize: renderSize, info: info)
        }
        #endif

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw AppError.exportFailed(underlying: NSError(domain: "AVComposer", code: 2)) }

        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        // iOS 18+ has async export(); fall back to the callback API for iOS 17 compat.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        if session.status != .completed {
            throw AppError.exportFailed(underlying: session.error ?? NSError(domain: "AVComposer", code: 3))
        }
    }

    @MainActor
    private func attachWatermark(
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        info: WatermarkBakeInfo
    ) {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        // Timestamp layer — animated via keyframes over the full duration.
        // CATextLayer.font must be a CTFont (CFTypeRef), not UIFont — passing UIFont causes SIGTRAP.
        let timestamp = CATextLayer()
        timestamp.font = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        timestamp.fontSize = 24
        timestamp.foregroundColor = UIColor.white.cgColor
        timestamp.shadowColor = UIColor.black.cgColor
        timestamp.shadowOpacity = 0.9
        timestamp.shadowRadius = 3
        timestamp.alignmentMode = .left
        timestamp.contentsScale = UIScreen.main.scale
        timestamp.frame = timestampFrame(renderSize: renderSize, position: info.position)
        parent.addSublayer(timestamp)

        let totalSeconds = Int(videoComposition.instructions.first?.timeRange.duration.seconds ?? 0)
        var values: [String] = []
        var keyTimes: [NSNumber] = []
        let base = info.eventStart.addingTimeInterval(info.rangeStart.seconds)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for sec in 0...max(1, totalSeconds) {
            values.append(df.string(from: base.addingTimeInterval(TimeInterval(sec))))
            let frac = totalSeconds > 0 ? Double(sec) / Double(totalSeconds) : 0
            keyTimes.append(NSNumber(value: frac))
        }
        let anim = CAKeyframeAnimation(keyPath: "string")
        anim.values = values
        anim.keyTimes = keyTimes
        anim.calculationMode = .discrete
        anim.duration = max(1, Double(totalSeconds))
        anim.isRemovedOnCompletion = false
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        timestamp.add(anim, forKey: "timestamp")
        timestamp.string = values.first ?? ""

        if case .grid(let angles) = info.layoutKind {
            let cellW = renderSize.width / 2
            let cellH = renderSize.height / 2
            for (idx, angle) in angles.enumerated() {
                let label = CATextLayer()
                label.string = angleLabel(angle)
                label.font = CTFontCreateWithName("Helvetica" as CFString, 20, nil)
                label.fontSize = 20
                label.foregroundColor = UIColor.white.cgColor
                label.shadowColor = UIColor.black.cgColor
                label.shadowOpacity = 0.9
                label.shadowRadius = 3
                label.contentsScale = UIScreen.main.scale
                let row = idx / 2, col = idx % 2
                let x = CGFloat(col) * cellW + 12
                let y = renderSize.height - CGFloat(row) * cellH - 32
                label.frame = CGRect(x: x, y: y, width: 180, height: 24)
                parent.addSublayer(label)
            }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent
        )
    }

    private func timestampFrame(renderSize: CGSize, position: ExportRequest.WatermarkPosition) -> CGRect {
        let w: CGFloat = 320, h: CGFloat = 28, pad: CGFloat = 16
        switch position {
        case .bottomLeft:  return CGRect(x: pad, y: pad, width: w, height: h)
        case .bottomRight: return CGRect(x: renderSize.width - w - pad, y: pad, width: w, height: h)
        case .topLeft:     return CGRect(x: pad, y: renderSize.height - h - pad, width: w, height: h)
        case .topRight:    return CGRect(x: renderSize.width - w - pad, y: renderSize.height - h - pad, width: w, height: h)
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前 Front"
        case .back: return "后 Back"
        case .leftRepeater: return "左后 L-Rep"
        case .rightRepeater: return "右后 R-Rep"
        case .leftPillar: return "左柱 L-Pil"
        case .rightPillar: return "右柱 R-Pil"
        }
    }
}
