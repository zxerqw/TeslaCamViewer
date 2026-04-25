import SwiftUI
import CoreMedia

struct TrimBarView: View {
    let totalDuration: CMTime
    @Binding var trimStart: CMTime
    @Binding var trimEnd: CMTime
    let currentTime: CMTime
    let onScrub: (CMTime) -> Void

    /// Horizontal inset so handles never sit flush against the screen edge.
    private let inset: CGFloat = 20
    private let handleSize: CGFloat = 20
    /// Minimum hit target per Apple HIG.
    private let hitSize: CGFloat = 44
    /// Vertical center for trim handles.
    private let trimY: CGFloat = 24
    /// Vertical center for the playhead scrub handle (below trim handles).
    private let playheadHandleY: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let total = max(totalDuration.seconds, 0.001)
            let usable = max(1, geo.size.width - inset * 2)
            let startFrac = CGFloat(trimStart.seconds / total)
            let endFrac   = CGFloat(trimEnd.seconds   / total)
            let currFrac  = CGFloat(currentTime.seconds / total)
            let startX = inset + startFrac * usable
            let endX   = inset + endFrac * usable
            let currX  = inset + currFrac * usable

            ZStack(alignment: .topLeading) {
                // Full-duration background bar
                Rectangle().fill(.gray.opacity(0.3))
                    .frame(width: usable, height: 6)
                    .position(x: inset + usable / 2, y: trimY)

                // Selected trim range bar
                Rectangle().fill(.blue.opacity(0.6))
                    .frame(width: max(0, endX - startX), height: 6)
                    .position(x: (startX + endX) / 2, y: trimY)

                // Playhead vertical line (extends from trim row down to scrub handle)
                Rectangle().fill(.white)
                    .frame(width: 2, height: playheadHandleY - trimY + 16)
                    .position(x: currX, y: (trimY + playheadHandleY + 6) / 2)

                // ── Start trim handle ──
                Circle().fill(.white).frame(width: handleSize, height: handleSize)
                    .overlay(Circle().stroke(.blue, lineWidth: 2))
                    .shadow(radius: 2)
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())
                    .position(x: startX, y: trimY)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { g in
                                let clamped = min(max(inset, g.location.x), endX - 4)
                                let frac = Double((clamped - inset) / usable)
                                trimStart = CMTime(seconds: frac * total, preferredTimescale: 600)
                                onScrub(trimStart)
                            }
                    )

                // ── End trim handle ──
                Circle().fill(.white).frame(width: handleSize, height: handleSize)
                    .overlay(Circle().stroke(.blue, lineWidth: 2))
                    .shadow(radius: 2)
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())
                    .position(x: endX, y: trimY)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { g in
                                let clamped = max(min(inset + usable, g.location.x), startX + 4)
                                let frac = Double((clamped - inset) / usable)
                                trimEnd = CMTime(seconds: frac * total, preferredTimescale: 600)
                                onScrub(trimEnd)
                            }
                    )

                // ── Playhead scrub handle (below trim bar) ──
                playheadHandle
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())
                    .position(x: currX, y: playheadHandleY)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { g in
                                let clamped = min(max(inset, g.location.x), inset + usable)
                                let frac = Double((clamped - inset) / usable)
                                let t = CMTime(seconds: frac * total, preferredTimescale: 600)
                                onScrub(t)
                            }
                    )
            }
            .frame(width: geo.size.width, height: 76)
        }
        .frame(height: 76)
    }

    /// Downward-pointing triangle to distinguish from the circular trim handles.
    private var playheadHandle: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .shadow(radius: 2)
    }
}
