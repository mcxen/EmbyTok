import Foundation

enum ServerType: String, CaseIterable {
    case emby = "emby"
    case folder = "folder"

    var displayName: String {
        switch self {
        case .emby: return "Emby"
        case .folder: return "Folder"
        }
    }
}

enum PlaybackEndAction: String, CaseIterable {
    case loopCurrent = "loopCurrent"
    case playNext = "playNext"

    var displayName: String {
        switch self {
        case .loopCurrent: return "循环当前"
        case .playNext: return "下一个"
        }
    }
}

struct ServerConfig {
    let baseURL: URL
    let username: String
    let token: String
    let userId: String
    let serverType: ServerType
}

struct LibraryItem {
    let id: String
    let name: String
}

struct VideoItem: Hashable {
    let id: String
    let name: String
    let overview: String
    let width: Int?
    let height: Int?
    let primaryImageTag: String?
    let durationSeconds: Double?
    let sizeBytes: Int64?
    let filePath: String?
}

struct VideoPage {
    let items: [VideoItem]
    let totalCount: Int
    let nextStartIndex: Int
}

struct FavoriteVideoRecord: Hashable {
    let id: String
    let title: String
    let detail: String?
}
