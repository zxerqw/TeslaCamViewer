import SwiftUI
import AVFoundation
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        PlayerLayerUIView()
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.setPlayer(player)
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError() }

        func setPlayer(_ p: AVPlayer?) {
            if playerLayer.player !== p { playerLayer.player = p }
        }
    }
}

struct MissingAngleView: View {
    let angleName: String
    var body: some View {
        ZStack {
            Color.black
            VStack {
                Image(systemName: "video.slash").foregroundStyle(.white.opacity(0.6))
                Text(angleName).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
