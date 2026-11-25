import SwiftUI
import CoreMedia

struct GridPlayerView: View {
    @Bindable var viewModel: GridPlayerViewModel
    let onExportTap: () -> Void

    @State private var trimStart: CMTime = .zero
    @State private var trimEnd: CMTime   = CMTime(seconds: 1, preferredTimescale: 600)
    /// When non-nil, a single angle is shown full-screen instead of the 2×2 grid.
    @State private var focusedAngle: CameraAngle?

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            if isLandscape {
                HStack(spacing: 0) {
                    gridView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Controls area on the right in landscape
                    VStack(spacing: 8) {
                        controls
                        layoutPicker
                        telemetryToggle
                        watermarkPicker
                        TrimBarView(
                            totalDuration: viewModel.playback.totalDuration,
                            trimStart: $trimStart,
                            trimEnd: $trimEnd,
                            currentTime: viewModel.playback.currentTime,
                            onScrub: { t in
                                Task { try? await viewModel.playback.seek(to: t) }
                                viewModel.playback.setTrim(start: trimStart, end: trimEnd)
                            }
                        )
                        .padding(.horizontal, 8)

                        exportButtons
                            .padding(.bottom, 8)
                    }
                    .frame(width: min(220, geo.size.width * 0.28))
                    .padding(.top, 8)
                    .background(Color(.systemGray6))
                }
            } else {
                VStack(spacing: 0) {
                    gridView
                    // Controls area with dark background for visibility in light mode
                    VStack(spacing: 8) {
                        controls
                        layoutPicker
                        telemetryToggle
                        watermarkPicker
                        TrimBarView(
                            totalDuration: viewModel.playback.totalDuration,
                            trimStart: $trimStart,
                            trimEnd: $trimEnd,
                            currentTime: viewModel.playback.currentTime,
                            onScrub: { t in
                                Task { try? await viewModel.playback.seek(to: t) }
                                viewModel.playback.setTrim(start: trimStart, end: trimEnd)
                            }
                        )
                        .padding(.horizontal)

                        exportButtons
                            .padding(.bottom, 8)
                    }
                    .padding(.top, 8)
                    .background(Color(.systemGray6))
                }
            }
        }
        .task {
            await viewModel.load()
            // Open in the grid (default 四画面): do not auto-zoom to the
            // trigger camera on open — the 哨兵 button only seeks.
            await viewModel.loadTelemetry()
        }
        .onChange(of: viewModel.playback.totalDuration) { _, newTotal in
            trimStart = .zero
            trimEnd = newTotal
        }
    }

    // MARK: - Grid layout picker (4 / 6 cameras)

    private var layoutPicker: some View {
        Picker("画面", selection: $viewModel.gridLayout) {
            ForEach(GridPlayerViewModel.GridLayout.allCases) { l in
                Text(l.label).tag(l)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .onChange(of: viewModel.gridLayout) { _, _ in focusedAngle = nil }
    }

    // MARK: - Watermark picker

    private var watermarkPicker: some View {
        HStack(spacing: 4) {
            Text("水印").font(.caption2).foregroundStyle(.secondary)
            Picker("水印", selection: $viewModel.watermarkPosition) {
                Text("左上").tag(ExportRequest.WatermarkPosition.topLeft)
                Text("右上").tag(ExportRequest.WatermarkPosition.topRight)
                Text("左下").tag(ExportRequest.WatermarkPosition.bottomLeft)
                Text("右下").tag(ExportRequest.WatermarkPosition.bottomRight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Watermark overlay preview

    private func watermarkOverlay(size: CGSize) -> some View {
        let position = viewModel.watermarkPosition
        let alignment: Alignment = switch position {
        case .topLeft:     .topLeading
        case .topRight:    .topTrailing
        case .bottomLeft:  .bottomLeading
        case .bottomRight: .bottomTrailing
        }
        return ZStack(alignment: alignment) {
            Color.clear
            Text(watermarkTimestamp)
                .font(.system(size: max(10, min(16, size.width * 0.025)), weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(max(4, size.width * 0.015))
        }
    }

    /// Generate a sample timestamp for the watermark preview.
    private var watermarkTimestamp: String {
        let time = viewModel.event.startTime.addingTimeInterval(
            viewModel.playback.currentTime.seconds
        )
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: time)
    }

    // MARK: - Grid view

    private var gridView: some View {
        GeometryReader { geo in
            if let focused = focusedAngle {
                // Single-angle full view — tap to return to grid
                Group {
                    if viewModel.event.availableAngles.contains(focused),
                       let player = viewModel.playback.player(for: focused) {
                        PlayerLayerView(player: player)
                    } else {
                        MissingAngleView(angleName: angleLabel(focused))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .topLeading) {
                    Text(angleLabel(focused))
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.6)).foregroundStyle(.white)
                        .cornerRadius(4)
                        .padding(8)
                }
                .overlay { watermarkOverlay(size: geo.size) }
                .overlay(alignment: telemetryAlignment) { telemetryHUD(size: geo.size) }
                .contentShape(Rectangle())
                .onTapGesture { focusedAngle = nil }
            } else {
                // Real row/column layout: every cell owns a distinct layout
                // frame, so its tap gesture fires only for taps inside that
                // cell. (Previously the cells were absolutely positioned with
                // .position() inside a ZStack, which sizes itself to a single
                // cell — the cells shared one layout slot and taps landed on
                // the wrong cell, enlarging the previously focused camera
                // instead of the one actually tapped.)
                let angles = viewModel.gridAngles
                let cols = CameraAngle.gridColumns(forCount: angles.count)
                let rows = 2
                let cellW = geo.size.width / CGFloat(cols)
                let cellH = geo.size.height / CGFloat(rows)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<cols, id: \.self) { col in
                                let idx = row * cols + col
                                if idx < angles.count {
                                    cell(for: angles[idx], index: idx, columns: cols, size: CGSize(width: cellW, height: cellH))
                                }
                            }
                        }
                    }
                }
                .overlay { watermarkOverlay(size: geo.size) }
                .overlay(alignment: telemetryAlignment) { telemetryHUD(size: geo.size) }
            }
        }
        .clipped()
        .background(.black)
    }

    @ViewBuilder
    private func cell(for angle: CameraAngle, index: Int, columns: Int, size: CGSize) -> some View {
        let row = index / columns, col = index % columns
        // Place angle labels toward the center of the grid to avoid watermark overlap:
        //   cell 0 (top-left)     → label at bottom-right of cell
        //   cell 1 (top-right)    → label at bottom-left of cell
        //   cell 2 (bottom-left)  → label at top-right of cell
        //   cell 3 (bottom-right) → label at top-left of cell
        //   (6-camera grid: middle column → label at bottom/top center)
        let labelAlignment: Alignment = {
            let top = row == 0
            if col == 0 { return top ? .bottomTrailing : .topTrailing }
            if col == columns - 1 { return top ? .bottomLeading : .topLeading }
            return top ? .bottom : .top
        }()
        Group {
            if viewModel.event.availableAngles.contains(angle),
               let player = viewModel.playback.player(for: angle) {
                PlayerLayerView(player: player)
            } else {
                MissingAngleView(angleName: angleLabel(angle))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: labelAlignment) {
            Text(angleLabel(angle))
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.6)).foregroundStyle(.white)
                .cornerRadius(4)
                .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedAngle = angle }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button {
                Task {
                    try? await viewModel.playback.seek(to: CMTime(
                        seconds: max(0, viewModel.playback.currentTime.seconds - 5),
                        preferredTimescale: 600
                    ))
                }
            } label: {
                Image(systemName: "gobackward.5")
            }
            Button {
                if viewModel.playback.isPlaying { viewModel.playback.pause() }
                else { viewModel.playback.play() }
            } label: {
                Image(systemName: viewModel.playback.isPlaying ? "pause.fill" : "play.fill").font(.title)
            }
            Button {
                Task {
                    try? await viewModel.playback.seek(to: CMTime(
                        seconds: min(viewModel.playback.totalDuration.seconds,
                                     viewModel.playback.currentTime.seconds + 5),
                        preferredTimescale: 600
                    ))
                }
            } label: {
                Image(systemName: "goforward.5")
            }
            if let sentryTime = sentryEventTime {
                Button {
                    Task {
                        // Keep the current layout: only re-aim at the trigger
                        // camera when already watching a single camera.
                        // In 4/6 grid mode the grid stays as-is.
                        if focusedAngle != nil, let a = viewModel.sentryTriggerAngle {
                            focusedAngle = a
                        }
                        try? await viewModel.playback.seek(to: sentryTime)
                        viewModel.playback.play()
                    }
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "exclamationmark.shield.fill")
                        Text("哨兵").font(.caption2)
                    }
                    .foregroundStyle(.red)
                }
                .accessibilityLabel("跳转至哨兵触发时刻")
            }
        }
    }

    /// Timeline position of the moment that triggered this Sentry event
    /// (a few seconds early so the lead-up is visible). Nil when unavailable.
    private var sentryEventTime: CMTime? {
        SentryEventLocator.eventTime(
            for: viewModel.event,
            segmentStartTimes: viewModel.playback.segmentStartTimes,
            totalDuration: viewModel.playback.totalDuration
        )
    }

    @ViewBuilder
    private var telemetryToggle: some View {
        if let track = viewModel.telemetry {
            if track.isEmpty {
                Text("此视频无车速/G值数据")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Toggle("显示车速/G值", isOn: $viewModel.showTelemetry)
                    .font(.caption)
                    .padding(.horizontal, 8)
            }
        } else {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("读取车速数据…").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Export buttons

    private var exportButtons: some View {
        VStack(spacing: 6) {
            if let trigger = viewModel.sentryTriggerTime {
                Button {
                    let total = viewModel.playback.totalDuration
                    let s = max(0, trigger.seconds - 10)
                    let e = min(total.seconds, trigger.seconds + 10)
                    trimStart = CMTime(seconds: s, preferredTimescale: 600)
                    trimEnd = CMTime(seconds: e, preferredTimescale: 600)
                    viewModel.playback.setTrim(start: trimStart, end: trimEnd)
                    onExportTap()
                } label: {
                    Label("导出事件前后10秒", systemImage: "scissors")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            Button("导出", action: onExportTap)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Telemetry HUD (speed / G)

    private var telemetryAlignment: Alignment {
        // Opposite vertical edge from the watermark so they never overlap.
        switch viewModel.watermarkPosition {
        case .bottomLeft, .bottomRight: return .top
        case .topLeft, .topRight: return .bottom
        }
    }

    @ViewBuilder
    private func telemetryHUD(size: CGSize) -> some View {
        if viewModel.showTelemetry, let track = viewModel.telemetry, !track.isEmpty,
           let s = track.sample(at: viewModel.playback.currentTime.seconds) {
            let base = max(10, min(15, size.width * 0.024))
            HStack(alignment: .center, spacing: 10) {
                VStack(spacing: 0) {
                    Text("\(Int(s.speedKph.rounded()))")
                        .font(.system(size: base * 2, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("km/h").font(.system(size: base * 0.7))
                }
                Text(s.gear.rawValue)
                    .font(.system(size: base * 1.3, weight: .heavy, design: .rounded))
                    .foregroundStyle(s.gear == .D ? Color.green : (s.gear == .R ? Color.orange : Color.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "纵向 %+.2fG", s.gLongitudinal))
                        .foregroundStyle(gColor(s.gLongitudinal))
                    Text(String(format: "横向 %+.2fG", s.gLateral))
                        .foregroundStyle(gColor(s.gLateral))
                }
                .font(.system(size: base * 0.85, weight: .semibold, design: .monospaced))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left").opacity(s.blinkerLeft ? 1 : 0.25)
                            .foregroundStyle(s.blinkerLeft ? Color.green : Color.white)
                        Image(systemName: "arrow.right").opacity(s.blinkerRight ? 1 : 0.25)
                            .foregroundStyle(s.blinkerRight ? Color.green : Color.white)
                    }
                    HStack(spacing: 4) {
                        Text("刹").foregroundStyle(s.brake ? Color.red : Color.white.opacity(0.3))
                        Text("油\(Int(s.throttlePct.rounded()))%")
                            .foregroundStyle(s.throttlePct > 1 ? Color.green : Color.white.opacity(0.4))
                    }
                    if let ap = autopilotLabel(s.autopilot) {
                        Text(ap).foregroundStyle(.cyan)
                    }
                }
                .font(.system(size: base * 0.75, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
            .allowsHitTesting(false)
        }
    }

    private func gColor(_ g: Double) -> Color {
        let a = abs(g)
        if a >= 0.5 { return .red }
        if a >= 0.25 { return .orange }
        return .white
    }

    private func autopilotLabel(_ a: TelemetrySample.Autopilot) -> String? {
        switch a {
        case .fsd: return "FSD"
        case .autosteer: return "AP"
        case .tacc: return "TACC"
        case .none: return nil
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front:         return "前"
        case .back:          return "后"
        case .leftRepeater:  return "左后视镜"
        case .rightRepeater: return "右后视镜"
        case .leftPillar:    return "左B柱"
        case .rightPillar:   return "右B柱"
        }
    }
}
