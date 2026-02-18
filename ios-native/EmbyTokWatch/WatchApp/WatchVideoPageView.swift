import AVKit
import AVFoundation
import SwiftUI

struct WatchVideoPageView: View {
    let item: WatchVideoItem
    let isMuted: Bool

    @EnvironmentObject private var state: WatchAppState
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .allowsHitTesting(false)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .background(Color.black)
        .task(id: item.id) {
            await configurePlayer()
        }
        .onAppear {
            player?.play()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
    }
}

private extension WatchVideoPageView {
    @MainActor
    func configurePlayer() async {
        teardownPlayer()

        guard let resolvedURL = await state.playbackURL(for: item) else {
            return
        }

        let nextPlayer = AVPlayer(url: resolvedURL)
        nextPlayer.actionAtItemEnd = .none
        nextPlayer.isMuted = isMuted

        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nextPlayer.currentItem,
            queue: .main
        ) { _ in
            nextPlayer.seek(to: .zero)
            nextPlayer.play()
        }

        endObserver = observer
        player = nextPlayer
        nextPlayer.play()
    }

    @MainActor
    func teardownPlayer() {
        player?.pause()
        player = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
