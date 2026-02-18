import SwiftUI

struct WatchVideoFeedView: View {
    @EnvironmentObject private var state: WatchAppState

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { state.currentItem == nil ? 0 : state.selectedIndex },
            set: { state.updateSelectedIndex($0) }
        )
    }

    var body: some View {
        ZStack {
            if state.videos.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("正在加载视频…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                TabView(selection: selectionBinding) {
                    ForEach(Array(state.videos.enumerated()), id: \.element.id) { index, item in
                        WatchVideoPageView(item: item, isMuted: state.isMuted)
                            .tag(index)
                            .onAppear {
                                state.updateSelectedIndex(index)
                            }
                    }
                }
#if os(watchOS)
                .tabViewStyle(.verticalPage)
#endif
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .trailing) {
            rightControls
                .padding(.trailing, 4)
        }
        .overlay(alignment: .bottomLeading) {
            if !state.isPureMode, let item = state.currentItem {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(2)
                    if !item.overview.isEmpty {
                        Text(item.overview)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.leading, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: 130, alignment: .leading)
            }
        }
        .overlay(alignment: .topLeading) {
            if !state.isPureMode {
                Button(action: state.returnToConnect) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.top, 4)
            }
        }
    }

    private var rightControls: some View {
        VStack(spacing: 8) {
            Button(action: state.togglePureMode) {
                Image(systemName: state.isPureMode ? "eye" : "eye.slash")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: state.toggleMute) {
                Image(systemName: state.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
