import Foundation

final class WatchAPIClient {
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authenticate(
        serverType: WatchServerType,
        baseURL: URL,
        username: String,
        password: String
    ) async throws -> WatchServerConfig {
        switch serverType {
        case .emby:
            return try await authenticateEmby(baseURL: baseURL, username: username, password: password)
        case .folder:
            return try await authenticateFolder(baseURL: baseURL, username: username, password: password)
        }
    }

    func fetchVideos(config: WatchServerConfig, skip: Int, limit: Int) async throws -> WatchVideoPage {
        switch config.serverType {
        case .emby:
            return try await fetchEmbyVideos(config: config, skip: skip, limit: limit)
        case .folder:
            return try await fetchFolderVideos(config: config, skip: skip, limit: limit)
        }
    }

    func videoURL(for item: WatchVideoItem, config: WatchServerConfig) -> URL? {
        switch config.serverType {
        case .emby:
            let useAdaptiveHLS = (item.sizeBytes ?? 0) >= Self.largeVideoThresholdBytes
            let path = useAdaptiveHLS ? "/Videos/\(item.id)/master.m3u8" : "/Videos/\(item.id)/stream.mp4"
            let url = config.baseURL.appendingPathComponent(path)
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }

            var queryItems: [URLQueryItem] = [URLQueryItem(name: "api_key", value: config.token)]
            if !useAdaptiveHLS {
                queryItems.insert(URLQueryItem(name: "Static", value: "true"), at: 0)
            } else {
                queryItems.append(URLQueryItem(name: "StartTimeTicks", value: "0"))
                queryItems.append(URLQueryItem(name: "EnableSubtitlesInManifest", value: "true"))
            }
            components.queryItems = queryItems
            return components.url
        case .folder:
            let url = config.baseURL.appendingPathComponent("/api/folder/stream/\(item.id)")
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            components.queryItems = [URLQueryItem(name: "serviceId", value: config.token)]
            return components.url
        }
    }
}

private extension WatchAPIClient {
    struct EmbyAuthResponse: Decodable {
        struct EmbyUser: Decodable {
            let Id: String
            let Name: String
        }

        let User: EmbyUser
        let AccessToken: String
    }

    struct EmbyVideoResponse: Decodable {
        struct EmbyMediaSource: Decodable {
            let RunTimeTicks: Int64?
            let Size: Int64?
        }

        struct EmbyItem: Decodable {
            let Id: String
            let Name: String
            let Overview: String?
            let RunTimeTicks: Int64?
            let MediaSources: [EmbyMediaSource]?
        }

        let Items: [EmbyItem]
        let TotalRecordCount: Int?
    }

    struct FolderServicesResponse: Decodable {
        struct FolderService: Decodable {
            let id: String
            let name: String
        }

        let items: [FolderService]?
        let currentServiceId: String?
    }

    struct FolderVideosResponse: Decodable {
        struct FolderItem: Decodable {
            let Id: String
            let Name: String
            let Overview: String?
            let durationSeconds: Double?
            let sizeBytes: Int64?

            private enum CodingKeys: String, CodingKey {
                case Id
                case Name
                case Overview
                case Duration
                case DurationMs
                case DurationSeconds
                case RunTimeTicks
                case Size
                case FileSize
                case size
                case sizeBytes
                case fileSize
                case duration
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                Id = try container.decode(String.self, forKey: .Id)
                Name = try container.decode(String.self, forKey: .Name)
                Overview = try container.decodeIfPresent(String.self, forKey: .Overview)

                func decodeDouble(_ key: CodingKeys) -> Double? {
                    (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil
                }

                func decodeInt64(_ key: CodingKeys) -> Int64? {
                    (try? container.decodeIfPresent(Int64.self, forKey: key)) ?? nil
                }

                let durationMs = decodeDouble(.DurationMs) ?? decodeDouble(.Duration) ?? decodeDouble(.duration)
                let durationSecDirect = decodeDouble(.DurationSeconds)
                let ticks = decodeDouble(.RunTimeTicks)
                if let durationSecDirect {
                    durationSeconds = durationSecDirect
                } else if let durationMs {
                    durationSeconds = durationMs > 10_000 ? durationMs / 1_000.0 : durationMs
                } else if let ticks {
                    durationSeconds = ticks / 10_000_000.0
                } else {
                    durationSeconds = nil
                }

                let candidateSizes: [Int64?] = [
                    decodeInt64(.sizeBytes),
                    decodeInt64(.Size),
                    decodeInt64(.FileSize),
                    decodeInt64(.fileSize),
                    decodeInt64(.size)
                ]
                sizeBytes = candidateSizes.compactMap { $0 }.first
            }
        }

        let items: [FolderItem]?
        let totalCount: Int?
        let nextStartIndex: Int?
    }

    func authenticateEmby(baseURL: URL, username: String, password: String) async throws -> WatchServerConfig {
        let url = baseURL.appendingPathComponent("/Users/AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(buildEmbyAuthHeader(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let auth = try JSONDecoder().decode(EmbyAuthResponse.self, from: data)
        return WatchServerConfig(
            baseURL: baseURL,
            username: auth.User.Name,
            token: auth.AccessToken,
            userId: auth.User.Id,
            serverType: .emby
        )
    }

    func authenticateFolder(baseURL: URL, username: String, password: String) async throws -> WatchServerConfig {
        let pingURL = baseURL.appendingPathComponent("/api/folder/ping")
        _ = try await session.data(from: pingURL)

        let servicesURL = baseURL.appendingPathComponent("/api/folder/services")
        let (servicesData, servicesResponse) = try await session.data(from: servicesURL)
        try validateResponse(servicesResponse)

        let services = try JSONDecoder().decode(FolderServicesResponse.self, from: servicesData)
        let list = services.items ?? []
        let requested = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = list.first(where: { $0.id == requested || $0.name == requested })
            ?? list.first(where: { $0.id == services.currentServiceId })
            ?? list.first

        guard let service = selected else {
            throw WatchAPIError.noFolderService
        }

        return WatchServerConfig(
            baseURL: baseURL,
            username: username.isEmpty ? "Folder User" : username,
            token: service.id,
            userId: service.id,
            serverType: .folder
        )
    }

    func fetchEmbyVideos(config: WatchServerConfig, skip: Int, limit: Int) async throws -> WatchVideoPage {
        let url = config.baseURL.appendingPathComponent("/Users/\(config.userId)/Items")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WatchAPIError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Video,Episode"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "MediaSources,Overview"),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "StartIndex", value: String(skip)),
            URLQueryItem(name: "SortBy", value: "DateCreated"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "_t", value: String(Int(Date().timeIntervalSince1970)))
        ]

        guard let finalURL = components.url else {
            throw WatchAPIError.badURL
        }

        var request = URLRequest(url: finalURL)
        request.setValue(buildEmbyAuthHeader(token: config.token), forHTTPHeaderField: "X-Emby-Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(EmbyVideoResponse.self, from: data)
        let items: [WatchVideoItem] = decoded.Items
            .filter { !$0.Name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".") }
            .map { item in
                let runtimeTicks = item.RunTimeTicks
                    ?? item.MediaSources?.first(where: { ($0.RunTimeTicks ?? 0) > 0 })?.RunTimeTicks
                let duration = runtimeTicks.map { Double($0) / 10_000_000.0 }
                let size = item.MediaSources?.first(where: { ($0.Size ?? 0) > 0 })?.Size
                return WatchVideoItem(
                    id: item.Id,
                    name: item.Name,
                    overview: item.Overview ?? "",
                    durationSeconds: duration,
                    sizeBytes: size
                )
            }
        let total = decoded.TotalRecordCount ?? items.count
        return WatchVideoPage(items: items, totalCount: total, nextStartIndex: skip + items.count)
    }

    func fetchFolderVideos(config: WatchServerConfig, skip: Int, limit: Int) async throws -> WatchVideoPage {
        let url = config.baseURL.appendingPathComponent("/api/folder/videos")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WatchAPIError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "feedType", value: "latest"),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "orientationMode", value: "both"),
            URLQueryItem(name: "serviceId", value: config.token)
        ]

        guard let finalURL = components.url else {
            throw WatchAPIError.badURL
        }

        let (data, response) = try await session.data(from: finalURL)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(FolderVideosResponse.self, from: data)
        let items: [WatchVideoItem] = (decoded.items ?? [])
            .filter { !$0.Name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".") }
            .map { item in
                WatchVideoItem(
                    id: item.Id,
                    name: item.Name,
                    overview: item.Overview ?? "",
                    durationSeconds: item.durationSeconds,
                    sizeBytes: item.sizeBytes
                )
            }

        let total = decoded.totalCount ?? items.count
        return WatchVideoPage(
            items: items,
            totalCount: total,
            nextStartIndex: decoded.nextStartIndex ?? (skip + items.count)
        )
    }

    func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WatchAPIError.requestFailed
        }
    }

    func buildEmbyAuthHeader(token: String?) -> String {
        let clientName = "EmbyTok Watch"
        let clientVersion = "1.0"
        let deviceName = "Apple Watch"
        let deviceId = "embytok-watch"
        if let token, !token.isEmpty {
            return "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\", Token=\"\(token)\""
        }
        return "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\""
    }
}

enum WatchAPIError: LocalizedError {
    case badURL
    case requestFailed
    case noFolderService

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "请求地址无效"
        case .requestFailed:
            return "请求失败，请检查服务器地址和网络"
        case .noFolderService:
            return "未找到可用的文件服务"
        }
    }
}
