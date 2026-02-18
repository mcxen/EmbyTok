import SwiftUI

struct WatchConnectView: View {
    @EnvironmentObject private var state: WatchAppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("类型", selection: serverTypeBinding) {
                        ForEach(WatchServerType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.automatic)

                    TextField("服务器地址", text: serverURLBinding)

                    TextField(usernamePlaceholder, text: usernameBinding)

                    TextField(passwordPlaceholder, text: passwordBinding)

                    Button(action: state.connect) {
                        if state.isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("连接服务器")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isConnecting)

                    if let connectionError = state.connectionError, !connectionError.isEmpty {
                        Text(connectionError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .navigationTitle("EmbyTok")
        }
        .onDisappear {
            state.persistDraft()
        }
    }
}

private extension WatchConnectView {
    var usernamePlaceholder: String {
        state.draft.serverType == .folder ? "显示名称(可选)" : "用户名"
    }

    var passwordPlaceholder: String {
        state.draft.serverType == .folder ? "ServiceId或名称" : "密码"
    }

    var serverTypeBinding: Binding<WatchServerType> {
        Binding(
            get: { state.draft.serverType },
            set: { next in
                state.updateDraft { $0.serverType = next }
            }
        )
    }

    var serverURLBinding: Binding<String> {
        Binding(
            get: { state.draft.serverURL },
            set: { next in
                state.updateDraft { $0.serverURL = next }
            }
        )
    }

    var usernameBinding: Binding<String> {
        Binding(
            get: { state.draft.username },
            set: { next in
                state.updateDraft { $0.username = next }
            }
        )
    }

    var passwordBinding: Binding<String> {
        Binding(
            get: { state.draft.password },
            set: { next in
                state.updateDraft { $0.password = next }
            }
        )
    }
}
