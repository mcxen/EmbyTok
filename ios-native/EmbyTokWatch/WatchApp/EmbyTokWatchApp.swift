import SwiftUI

@main
struct EmbyTokWatchApp: App {
    @StateObject private var state = WatchAppState()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(state)
        }
    }
}

private struct WatchRootView: View {
    @EnvironmentObject private var state: WatchAppState

    var body: some View {
        Group {
            if state.isConnected {
                WatchVideoFeedView()
            } else {
                WatchConnectView()
            }
        }
        .background(Color.black)
    }
}
