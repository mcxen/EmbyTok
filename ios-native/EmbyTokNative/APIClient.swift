import Foundation

final class APIClient {
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authenticate(
        serverType: ServerType,
        baseURL: URL,
        username: String,
        password: String,
        completion: @escaping (Result<ServerConfig, Error>) -> Void
    ) {
        switch serverType {
        case .emby:
            authenticateEmby(baseURL: baseURL, username: username, password: password, completion: completion)
        case .folder:
            authenticateFolder(baseURL: baseURL, username: username, password: password, completion: completion)
        }
    }

    func fetchVideos(
        config: ServerConfig,
        skip: Int,
        limit: Int,
        completion: @escaping (Result<VideoPage, Error>) -> Void
    ) {
        switch config.serverType {
        case .emby:
            fetchEmbyVideos(config: config, skip: skip, limit: limit, completion: completion)
        case .folder:
            fetchFolderVideos(config: config, skip: skip, limit: limit, completion: completion)
        }
    }

    func videoURL(for item: VideoItem, config: ServerConfig) -> URL? {
        switch config.serverType {
        case .emby:
            let useAdaptiveHLS = (item.sizeBytes ?? 0) >= Self.largeVideoThresholdBytes
            let path = useAdaptiveHLS ? "/Videos/\(item.id)/master.m3u8" : "/Videos/\(item.id)/stream.mp4"
            let url = config.baseURL.appendingPathComponent(path)
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems: [URLQueryItem] = [URLQueryItem(name: "api_key", value: config.token)]
            if !useAdaptiveHLS {
                queryItems.insert(URLQueryItem(name: "Static", value: "true"), at: 0)
            } else {
                queryItems.append(URLQueryItem(name: "StartTimeTicks", value: "0"))
                queryItems.append(URLQueryItem(name: "EnableSubtitlesInManifest", value: "true"))
            }
            comps?.queryItems = queryItems
            return comps?.url
        case .folder:
            let url = config.baseURL.appendingPathComponent("/api/folder/stream/\(item.id)")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            comps.queryItems = [URLQueryItem(name: "serviceId", value: config.token)]
            return comps.url
        }
    }

    func posterURL(for item: VideoItem, config: ServerConfig) -> URL? {
        switch config.serverType {
        case .emby:
            let url = config.baseURL.appendingPathComponent("/Items/\(item.id)/Images/Primary")
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = [
                URLQueryItem(name: "maxWidth", value: "800"),
                URLQueryItem(name: "quality", value: "90"),
                URLQueryItem(name: "api_key", value: config.token)
            ]
            if let tag = item.primaryImageTag, !tag.isEmpty {
                queryItems.append(URLQueryItem(name: "tag", value: tag))
            }
            comps?.queryItems = queryItems
            return comps?.url
        case .folder:
            return nil
        }
    }
}

private extension APIClient {
    struct EmbyAuthResponse: Decodable {
        struct EmbyUser: Decodable {
            let Id: String
            let Name: String
        }
        let User: EmbyUser
        let AccessToken: String
    }

    struct EmbyLibraryResponse: Decodable {
        struct EmbyLibrary: Decodable {
            let Id: String
            let Name: String
        }
        let Items: [EmbyLibrary]
    }

    struct EmbyVideoResponse: Decodable {
        struct EmbyMediaSource: Decodable {
            let RunTimeTicks: Int64?
            let Size: Int64?
        }

        struct EmbyImageTags: Decodable {
            let Primary: String?
        }

        struct EmbyItem: Decodable {
            let Id: String
            let Name: String
            let Overview: String?
            let Width: Int?
            let Height: Int?
            let ImageTags: EmbyImageTags?
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
                    return (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil
                }
                func decodeInt64(_ key: CodingKeys) -> Int64? {
                    return (try? container.decodeIfPresent(Int64.self, forKey: key)) ?? nil
                }

                let durationMs =
                    decodeDouble(.DurationMs)
                    ?? decodeDouble(.Duration)
                    ?? decodeDouble(.duration)
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

    func authenticateEmby(
        baseURL: URL,
        username: String,
        password: String,
        completion: @escaping (Result<ServerConfig, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/Users/AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(buildEmbyAuthHeader(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard
                let data = data,
                let http = response as? HTTPURLResponse,
                http.statusCode >= 200 && http.statusCode < 300
            else {
                completion(.failure(APIError.requestFailed))
                return
            }

            do {
                let auth = try JSONDecoder().decode(EmbyAuthResponse.self, from: data)
                let config = ServerConfig(
                    baseURL: baseURL,
                    username: auth.User.Name,
                    token: auth.AccessToken,
                    userId: auth.User.Id,
                    serverType: .emby
                )
                completion(.success(config))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func authenticateFolder(
        baseURL: URL,
        username: String,
        password: String,
        completion: @escaping (Result<ServerConfig, Error>) -> Void
    ) {
        let pingURL = baseURL.appendingPathComponent("/api/folder/ping")
        session.dataTask(with: pingURL) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let servicesURL = baseURL.appendingPathComponent("/api/folder/services")
            self.session.dataTask(with: servicesURL) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard
                    let data = data,
                    let http = response as? HTTPURLResponse,
                    http.statusCode >= 200 && http.statusCode < 300
                else {
                    completion(.failure(APIError.requestFailed))
                    return
                }

                do {
                    let services = try JSONDecoder().decode(FolderServicesResponse.self, from: data)
                    let list = services.items ?? []
                    let requested = password.trimmingCharacters(in: .whitespacesAndNewlines)
                    let selected = list.first(where: { $0.id == requested || $0.name == requested })
                        ?? list.first(where: { $0.id == services.currentServiceId })
                        ?? list.first

                    guard let service = selected else {
                        completion(.failure(APIError.noFolderService))
                        return
                    }

                    let config = ServerConfig(
                        baseURL: baseURL,
                        username: username.isEmpty ? "Folder User" : username,
                        token: service.id,
                        userId: service.id,
                        serverType: .folder
                    )
                    completion(.success(config))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }.resume()
    }

    func fetchEmbyVideos(
        config: ServerConfig,
        skip: Int,
        limit: Int,
        completion: @escaping (Result<VideoPage, Error>) -> Void
    ) {
        let url = config.baseURL.appendingPathComponent("/Users/\(config.userId)/Items")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Video,Episode"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "MediaSources,Width,Height,Overview,UserData,ImageTags"),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "StartIndex", value: String(skip)),
            URLQueryItem(name: "SortBy", value: "DateCreated"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "_t", value: String(Int(Date().timeIntervalSince1970)))
        ]

        guard let finalURL = components?.url else {
            completion(.failure(APIError.badURL))
            return
        }

        var request = URLRequest(url: finalURL)
        request.setValue(buildEmbyAuthHeader(token: config.token), forHTTPHeaderField: "X-Emby-Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard
                let data = data,
                let http = response as? HTTPURLResponse,
                http.statusCode >= 200 && http.statusCode < 300
            else {
                completion(.failure(APIError.requestFailed))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(EmbyVideoResponse.self, from: data)
                let items = decoded.Items.filter { item in
                    let name = item.Name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !name.hasPrefix(".")
                }.map { item in
                    let runtimeTicks = item.RunTimeTicks
                        ?? item.MediaSources?.first(where: { ($0.RunTimeTicks ?? 0) > 0 })?.RunTimeTicks
                    let durationSeconds = runtimeTicks.map { Double($0) / 10_000_000.0 }
                    let sizeBytes = item.MediaSources?.first(where: { ($0.Size ?? 0) > 0 })?.Size
                    return VideoItem(
                        id: item.Id,
                        name: item.Name,
                        overview: item.Overview ?? "",
                        width: item.Width,
                        height: item.Height,
                        primaryImageTag: item.ImageTags?.Primary,
                        durationSeconds: durationSeconds,
                        sizeBytes: sizeBytes
                    )
                }
                let total = decoded.TotalRecordCount ?? items.count
                completion(.success(VideoPage(items: items, totalCount: total, nextStartIndex: skip + items.count)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchFolderVideos(
        config: ServerConfig,
        skip: Int,
        limit: Int,
        completion: @escaping (Result<VideoPage, Error>) -> Void
    ) {
        let url = config.baseURL.appendingPathComponent("/api/folder/videos")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "feedType", value: "latest"),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "orientationMode", value: "both"),
            URLQueryItem(name: "serviceId", value: config.token)
        ]

        guard let finalURL = components?.url else {
            completion(.failure(APIError.badURL))
            return
        }

        session.dataTask(with: finalURL) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard
                let data = data,
                let http = response as? HTTPURLResponse,
                http.statusCode >= 200 && http.statusCode < 300
            else {
                completion(.failure(APIError.requestFailed))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(FolderVideosResponse.self, from: data)
                let items = (decoded.items ?? []).filter { item in
                    let name = item.Name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !name.hasPrefix(".")
                }.map { item in
                    return VideoItem(
                        id: item.Id,
                        name: item.Name,
                        overview: item.Overview ?? "",
                        width: nil,
                        height: nil,
                        primaryImageTag: nil,
                        durationSeconds: item.durationSeconds,
                        sizeBytes: item.sizeBytes
                    )
                }
                let total = decoded.totalCount ?? items.count
                completion(.success(VideoPage(items: items, totalCount: total, nextStartIndex: decoded.nextStartIndex ?? skip + items.count)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func buildEmbyAuthHeader(token: String?) -> String {
        let clientName = "EmbyTok iOS"
        let clientVersion = "1.0"
        let deviceName = "iPhone"
        let deviceId = "embytok-ios"
        if let token = token, !token.isEmpty {
            return "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\", Token=\"\(token)\""
        }
        return "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\""
    }
}

enum APIError: LocalizedError {
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
