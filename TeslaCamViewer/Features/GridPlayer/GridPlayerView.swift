import SwiftUI
import CoreMedia

struct GridPlayerView: View {
    @Bindable var viewModel: GridPlayerViewModel
    let onExportTap: () -> Void

    @State private var trimStart: CMTime = .zero
    @State private var trimEnd: CMTime   = CMTime(seconds: 1, preferredTimescale: 600)

    var body: some View {
        VStack(spacing: 8) {
            gridView
            controls
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
        .task { await viewModel.load() }
        .onChange(of: viewModel.playback.totalDuration) { _, newTotal in
            trimStart = .zero
            trimEnd = newTotal
        }
    }

    private var gridView: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / 2
            let cellH = geo.size.height / 2
            ZStack {
                ForEach(Array(viewModel.gridAngles.enumerated()), id: \.offset) { idx, angle in
                    cell(for: angle, index: idx, size: CGSize(width: cellW, height: cellH))
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(.black)
    }

    @ViewBuilder
    private func cell(for angle: CameraAngle, index: Int, size: CGSize) -> some View {
        let row = index / 2, col = index % 2
        Group {
            if viewModel.event.availableAngles.contains(angle),
               let player = viewModel.playback.player(for: angle) {
                PlayerLayerView(player: player)
            } else {
                MissingAngleView(angleName: angleLabel(angle))
            }
        }
        .frame(width: size.width, height: size.height)
        .position(x: CGFloat(col) * size.width + size.width / 2,
                  y: CGFloat(row) * size.height + size.height / 2)
        .overlay(alignment: .topLeading) {
            Text(angleLabel(angle))
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.6)).foregroundStyle(.white)
                .cornerRadius(4)
                .padding(4)
                .position(x: CGFloat(col) * size.width + 40,
                          y: CGFloat(row) * size.height + 14)
        }
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
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front:         return "前"
        case .back:          return "后"
        case .leftRepeater:  return "左后"
        case .rightRepeater: return "右后"
        case .leftPillar:    return "左柱"
        case .rightPillar:   return "右柱"
        }
    }
}
