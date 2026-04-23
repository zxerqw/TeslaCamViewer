import SwiftUI
import CoreMedia

struct TrimBarView: View {
    let totalDuration: CMTime
    @Binding var trimStart: CMTime
    @Binding var trimEnd: CMTime
    let currentTime: CMTime
    let onScrub: (CMTime) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(totalDuration.seconds, 0.001)
            let startX = CGFloat(trimStart.seconds / total) * w
            let endX   = CGFloat(trimEnd.seconds   / total) * w
            let currX  = CGFloat(currentTime.seconds / total) * w

            ZStack(alignment: .topLeading) {
                Rectangle().fill(.gray.opacity(0.3)).frame(height: 6).offset(y: 28)
                Rectangle().fill(.blue.opacity(0.6))
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX, y: 28)
                Rectangle().fill(.white).frame(width: 2, height: 40).offset(x: currX)
                handleCircle.offset(x: startX - 10, y: 20)
                    .gesture(DragGesture().onChanged { g in
                        let clamped = min(max(0, g.location.x), endX)
                        trimStart = CMTime(seconds: Double(clamped / w) * total, preferredTimescale: 600)
                        onScrub(trimStart)
                    })
                handleCircle.offset(x: endX - 10, y: 20)
                    .gesture(DragGesture().onChanged { g in
                        let clamped = max(min(w, g.location.x), startX)
                        trimEnd = CMTime(seconds: Double(clamped / w) * total, preferredTimescale: 600)
                        onScrub(trimEnd)
                    })
            }
            .frame(height: 60)
        }
        .frame(height: 60)
    }

    private var handleCircle: some View {
        Circle().fill(.white).frame(width: 20, height: 20)
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .shadow(radius: 2)
    }
}
