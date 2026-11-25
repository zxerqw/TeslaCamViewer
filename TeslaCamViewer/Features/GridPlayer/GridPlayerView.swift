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

                        Button("导出", action: onExportTap)
                            .buttonStyle(.borderedProminent)
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

                        Button("导出", action: onExportTap)
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 8)
                    }
                    .padding(.top, 8)
                    .background(Color(.systemGray6))
                }
            }
        }
        .task { await viewModel.load() }
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
                .contentShape(Rectangle())
                .onTapGesture { focusedAngle = nil }
            } else {
                let angles = viewModel.gridAngles
                let cols = CameraAngle.gridColumns(forCount: angles.count)
                let cellW = geo.size.width / CGFloat(cols)
                let cellH = geo.size.height / 2
                ZStack {
                    ForEach(Array(angles.enumerated()), id: \.offset) { idx, angle in
                        cell(for: angle, index: idx, columns: cols, size: CGSize(width: cellW, height: cellH))
                    }
                }
                .overlay { watermarkOverlay(size: geo.size) }
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
        .position(x: CGFloat(col) * size.width + size.width / 2,
                  y: CGFloat(row) * size.height + size.height / 2)
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
