import Foundation

enum WatchServerType: String, CaseIterable, Identifiable {
    case emby
    case folder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emby: return "Emby"
        case .folder: return "Folder"
        }
    }
}

struct WatchServerConfig {
    let baseURL: URL
    let username: String
    let token: String
    let userId: String
    let serverType: WatchServerType
}

struct WatchVideoItem: Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String
    let durationSeconds: Double?
    let sizeBytes: Int64?
}

struct WatchVideoPage {
    let items: [WatchVideoItem]
    let totalCount: Int
    let nextStartIndex: Int
}

struct WatchConnectionDraft {
    var serverType: WatchServerType
    var serverURL: String
    var username: String
    var password: String

    private static let serverTypeKey = "embytok.watch.serverType"
    private static let serverURLKey = "embytok.watch.serverURL"
    private static let usernameKey = "embytok.watch.username"
    private static let passwordKey = "embytok.watch.password"

    static func load() -> WatchConnectionDraft {
        let defaults = UserDefaults.standard
        let typeRaw = defaults.string(forKey: serverTypeKey) ?? WatchServerType.emby.rawValue
        let type = WatchServerType(rawValue: typeRaw) ?? .emby
        return WatchConnectionDraft(
            serverType: type,
            serverURL: defaults.string(forKey: serverURLKey) ?? "",
            username: defaults.string(forKey: usernameKey) ?? "",
            password: defaults.string(forKey: passwordKey) ?? ""
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(serverType.rawValue, forKey: Self.serverTypeKey)
        defaults.set(serverURL, forKey: Self.serverURLKey)
        defaults.set(username, forKey: Self.usernameKey)
        defaults.set(password, forKey: Self.passwordKey)
    }
}
