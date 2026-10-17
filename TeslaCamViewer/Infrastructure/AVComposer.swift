import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import UIKit

public final class AVComposer: ComposerProtocol, @unchecked Sendable {
    public init() {}

    // MARK: Single angle

    public func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL, progress: @escaping @Sendable (Float) -> Void) async throws {
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
            to: url,
            progress: progress
        )
    }

    // MARK: Grid

    public func exportGrid(request: ExportRequest, to url: URL, progress: @escaping @Sendable (Float) -> Void) async throws {
        guard case .gridCombined(let angles) = request.layout, angles.count == 4 else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "AVComposer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "gridCombined requires exactly 4 angles"]
            ))
        }
        // Detect native video size from the first available angle to avoid black bars.
        // Cap grid render size to max 1920 width to ensure smooth playback.
        let info = await detectNativeVideoInfo(event: request.event, angles: angles)
        let rawW = info.size.width * 2
        let rawH = info.size.height * 2
        let maxWidth: CGFloat = 1920
        let scaleFactor = rawW > maxWidth ? maxWidth / rawW : 1.0
        let renderSize = CGSize(width: (rawW * scaleFactor).rounded(.down),
                                height: (rawH * scaleFactor).rounded(.down))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(info.frameRate))
        let (composition, videoComp) = try await gridComposition(
            request: request, angles: angles, renderSize: renderSize, frameDuration: frameDuration
        )
        try await runExport(
            composition: composition,
            videoComposition: videoComp,
            renderSize: renderSize,
            watermarkBakeInfo: .init(
                position: request.watermarkPosition,
                layoutKind: .grid(angles: angles),
                eventStart: request.event.startTime,
                rangeStart: request.range.start
            ),
            to: url,
            progress: progress
        )
    }

    private struct NativeVideoInfo {
        let size: CGSize
        let frameRate: Float  // e.g. 36.0
    }

    /// Detect native video size and frame rate from the first available video track.
    private func detectNativeVideoInfo(event: TeslaEvent, angles: [CameraAngle]) async -> NativeVideoInfo {
        for angle in angles {
            for seg in event.segments {
                guard let u = seg.filesByAngle[angle] else { continue }
                let asset = AVURLAsset(url: u)
                if let vt = try? await asset.loadTracks(withMediaType: .video).first,
                   let sz = try? await vt.load(.naturalSize),
                   sz.width > 0, sz.height > 0 {
                    let rate = (try? await vt.load(.nominalFrameRate)) ?? 36
                    return NativeVideoInfo(size: sz, frameRate: rate > 0 ? rate : 36)
                }
            }
        }
        return NativeVideoInfo(size: CGSize(width: 1280, height: 960), frameRate: 36)
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
        var detectedFrameRate: Float = 36

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
                let rate = (try? await vt.load(.nominalFrameRate)) ?? 0
                if rate > 0 { detectedFrameRate = rate }
                compositionCursor = compositionCursor + insertDuration
            } catch {
                compositionCursor = compositionCursor + (overlapEnd - overlapStart)
            }
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(detectedFrameRate))

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
        renderSize: CGSize,
        frameDuration: CMTime = CMTime(value: 1, timescale: 36)
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
            // AVMutableVideoCompositionLayerInstruction transforms are applied to
            // the source video frame: first scale it down, then translate to the
            // correct cell position. Build the transform in the correct order:
            // T(offset) * S(scale) means "scale at origin, then move into place".
            let scaleF = min(cellW / nativeSize.width, cellH / nativeSize.height)
            let scaled = CGSize(width: nativeSize.width * scaleF, height: nativeSize.height * scaleF)
            let row = idx / 2, col = idx % 2   // 0=TL, 1=TR, 2=BL, 3=BR
            let cellX = CGFloat(col) * cellW
            let cellY = CGFloat(row) * cellH
            let offsetX = cellX + (cellW - scaled.width) / 2
            let offsetY = cellY + (cellH - scaled.height) / 2

            // CGAffineTransform concatenation: a.concatenating(b) = "apply a then b".
            // We want: scale at origin → translate to cell position.
            let t = CGAffineTransform(scaleX: scaleF, y: scaleF)
                .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(t, at: .zero)
            layerInstrs.append(layer)
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = frameDuration
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
        to url: URL,
        progress: @escaping @Sendable (Float) -> Void
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

        // Poll AVAssetExportSession.progress while exporting.
        let pollTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                let p = session.progress  // 0.0 – 1.0
                progress(p)
            }
        }

        // iOS 18+ has async export(); fall back to the callback API for iOS 17 compat.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        pollTask.cancel()
        progress(1.0)

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
        // AVVideoCompositionCoreAnimationTool overlays a CALayer tree onto the
        // rendered video. The CALayer coordinate system is standard CoreAnimation:
        //   • Origin at BOTTOM-LEFT, Y increases UPWARD.
        //   • Y=0 is the bottom of the video, Y=renderSize.height is the top.
        //
        // This is DIFFERENT from the video composition transform coordinate
        // system (which is top-left origin). Do not confuse the two.
        //
        // Constraints:
        //  • Do NOT use isGeometryFlipped or sublayerTransform flips.
        //  • CATextLayer.string is NOT animatable — use per-second layers
        //    with opacity animation instead.

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        // ── Dynamic timestamp (one text layer per second, opacity-animated) ──
        let tsFontSize: CGFloat = max(28, renderSize.width * 0.022)
        let tsFrame = timestampFrame(renderSize: renderSize, position: info.position, fontSize: tsFontSize)
        let totalDur = videoComposition.instructions.first?.timeRange.duration.seconds ?? 0
        let totalSeconds = Int(totalDur)
        let base = info.eventStart.addingTimeInterval(info.rangeStart.seconds)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let scale = UIScreen.main.scale

        for sec in 0...max(0, totalSeconds) {
            let textLayer = CATextLayer()
            textLayer.string = df.string(from: base.addingTimeInterval(TimeInterval(sec)))
            textLayer.font = CTFontCreateWithName("Helvetica-Bold" as CFString, tsFontSize, nil)
            textLayer.fontSize = tsFontSize
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.shadowColor = UIColor.black.cgColor
            textLayer.shadowOpacity = 0.9
            textLayer.shadowRadius = 3
            textLayer.alignmentMode = .left
            textLayer.contentsScale = scale
            textLayer.frame = tsFrame
            textLayer.opacity = 0

            let tStart = totalDur > 0 ? Double(sec) / totalDur : 0
            let tEnd   = totalDur > 0 ? min(1.0, Double(sec + 1) / totalDur) : 1
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values   = [0, 1, 0, 0] as [NSNumber]
            anim.keyTimes = [
                0,
                NSNumber(value: tStart),
                NSNumber(value: tEnd),
                1,
            ]
            anim.duration = max(1, totalDur)
            anim.calculationMode = .discrete
            anim.isRemovedOnCompletion = false
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            textLayer.add(anim, forKey: "show")

            parent.addSublayer(textLayer)
        }

        // ── Per-cell angle labels (grid mode only) ──
        // CA coords: Y=0 bottom, Y=height top.
        // Video grid: row 0 = top of video (high Y in CA), row 1 = bottom (low Y in CA).
        // Labels positioned toward the center of the grid to avoid watermark overlap:
        //   cell 0 (TL) → bottom-right of cell
        //   cell 1 (TR) → bottom-left of cell
        //   cell 2 (BL) → top-right of cell
        //   cell 3 (BR) → top-left of cell
        if case .grid(let angles) = info.layoutKind {
            let cellW = renderSize.width / 2
            let cellH = renderSize.height / 2
            let labelFontSize: CGFloat = max(28, renderSize.width * 0.018)
            let labelH: CGFloat = labelFontSize + 8
            let labelPad: CGFloat = 12
            for (idx, angle) in angles.enumerated() {
                let label = CATextLayer()
                label.string = angleLabel(angle)
                label.font = CTFontCreateWithName("Helvetica-Bold" as CFString, labelFontSize, nil)
                label.fontSize = labelFontSize
                label.foregroundColor = UIColor.white.cgColor
                label.shadowColor = UIColor.black.cgColor
                label.shadowOpacity = 0.9
                label.shadowRadius = 3
                label.contentsScale = scale

                let row = idx / 2, col = idx % 2
                let labelW: CGFloat = 200

                // X position: cell 0,2 (left col) → right side; cell 1,3 (right col) → left side
                let x: CGFloat
                if col == 0 {
                    // Left column → label on right side of cell (toward center)
                    x = cellW - labelW - labelPad
                    label.alignmentMode = .right
                } else {
                    // Right column → label on left side of cell (toward center)
                    x = cellW + labelPad
                    label.alignmentMode = .left
                }

                // Y position (CA coords: Y=0 bottom, Y=height top):
                //   row 0 (top video row) → label at bottom of cell (toward center)
                //   row 1 (bottom video row) → label at top of cell (toward center)
                let y: CGFloat
                if row == 0 {
                    // Top row → label at bottom of cell (low CA Y = near center divider)
                    y = cellH + labelPad
                } else {
                    // Bottom row → label at top of cell (high CA Y = near center divider)
                    y = cellH - labelH - labelPad
                }

                label.frame = CGRect(x: x, y: y, width: labelW, height: labelH)
                parent.addSublayer(label)
            }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent
        )
    }

    /// Timestamp position in CA coordinates (origin bottom-left, Y up).
    /// bottomLeft = low Y (near bottom), topLeft = high Y (near top).
    private func timestampFrame(renderSize: CGSize, position: ExportRequest.WatermarkPosition, fontSize: CGFloat = 42) -> CGRect {
        let w: CGFloat = fontSize * 14, h: CGFloat = fontSize + 8, pad: CGFloat = 20
        switch position {
        case .bottomLeft:  return CGRect(x: pad, y: pad, width: w, height: h)
        case .bottomRight: return CGRect(x: renderSize.width - w - pad, y: pad, width: w, height: h)
        case .topLeft:     return CGRect(x: pad, y: renderSize.height - h - pad, width: w, height: h)
        case .topRight:    return CGRect(x: renderSize.width - w - pad, y: renderSize.height - h - pad, width: w, height: h)
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前"
        case .back: return "后"
        case .leftRepeater: return "左后视镜"
        case .rightRepeater: return "右后视镜"
        case .leftPillar: return "左B柱"
        case .rightPillar: return "右B柱"
        }
    }
}
