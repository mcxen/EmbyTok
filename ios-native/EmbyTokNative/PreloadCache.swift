import AVFoundation
import CryptoKit
import Foundation

final class PreloadCache {
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024

    private var cache: [String: AVURLAsset] = [:]
    private var lightweightURLs: [String: URL] = [:]
    private var metadata: [String: String] = [:]
    private var order: [String] = []
    private var maxItems: Int

    init(maxItems: Int = 2) {
        self.maxItems = max(0, maxItems)
    }

    func updateMaxItems(_ next: Int) {
        maxItems = max(0, next)
        if maxItems == 0 {
            clear()
            return
        }
        trimIfNeeded()
    }

    func preload(item: VideoItem, url: URL) {
        guard maxItems > 0 else { return }
        let id = item.id
        if cache[id] != nil || lightweightURLs[id] != nil {
            touch(id: id)
            return
        }
        trimIfNeeded(nextAdding: 1)

        if shouldUseLightweightPreload(for: item) {
            lightweightURLs[id] = url
            metadata[id] = item.name
            order.append(id)
            return
        }

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        cache[id] = asset
        lightweightURLs[id] = url
        metadata[id] = item.name
        order.append(id)
    }

    func item(id: String) -> AVPlayerItem? {
        guard cache[id] != nil || lightweightURLs[id] != nil else { return nil }
        touch(id: id)
        if let cachedAsset = cache[id] {
            let playerItem = AVPlayerItem(asset: cachedAsset)
            playerItem.preferredForwardBufferDuration = 2
            return playerItem
        }
        if let url = lightweightURLs[id] {
            let playerItem = AVPlayerItem(url: url)
            playerItem.preferredForwardBufferDuration = 0.3
            return playerItem
        }
        return nil
    }

    func retain(only ids: Set<String>) {
        guard !ids.isEmpty else {
            clear()
            return
        }
        let staleIDs = cache.keys.filter { !ids.contains($0) }
        for id in staleIDs {
            cache.removeValue(forKey: id)
            metadata.removeValue(forKey: id)
            lightweightURLs.removeValue(forKey: id)
        }
        let staleLightweightIDs = lightweightURLs.keys.filter { !ids.contains($0) }
        for id in staleLightweightIDs {
            lightweightURLs.removeValue(forKey: id)
            metadata.removeValue(forKey: id)
        }
        order.removeAll { !ids.contains($0) }
    }

    func clear() {
        cache.removeAll()
        lightweightURLs.removeAll()
        metadata.removeAll()
        order.removeAll()
    }

    func cachedNames() -> [String] {
        return order.compactMap { metadata[$0] }
    }

    private func trimIfNeeded(nextAdding: Int = 0) {
        guard maxItems > 0 else {
            clear()
            return
        }
        while cache.count + lightweightURLs.count + nextAdding > maxItems, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
            lightweightURLs.removeValue(forKey: oldest)
            metadata.removeValue(forKey: oldest)
        }
    }

    private func touch(id: String) {
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        order.append(id)
    }

    private func shouldUseLightweightPreload(for item: VideoItem) -> Bool {
        guard let sizeBytes = item.sizeBytes else { return false }
        return sizeBytes >= Self.largeVideoThresholdBytes
    }
}

final class VideoDiskCache {
    static let shared = VideoDiskCache()

    struct Entry: Codable {
        let remoteURL: String
        let name: String
        let sizeBytes: Int64
        let localFilename: String
        let updatedAt: TimeInterval
    }

    private enum CacheError: LocalizedError {
        case emptyDownload
        case cannotCreateDirectory

        var errorDescription: String? {
            switch self {
            case .emptyDownload: return "下载结果为空"
            case .cannotCreateDirectory: return "创建缓存目录失败"
            }
        }
    }

    private let fileManager = FileManager.default
    private let stateQueue = DispatchQueue(label: "embytok.disk-cache.state")
    private let session: URLSession
    private let cacheDirectory: URL
    private let manifestURL: URL

    private var entriesByURL: [String: Entry] = [:]
    private var remoteSizeCache: [String: Int64] = [:]
    private var inFlightCallbacks: [String: [(Result<Entry, Error>) -> Void]] = [:]
    private var inFlightTasks: [String: URLSessionDownloadTask] = [:]
    private var hasLoadedManifest = false
    private var isLoadingManifest = false

    private init() {
        self.session = URLSession(configuration: .default)
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.cacheDirectory = base.appendingPathComponent("EmbyTokVideoCache", isDirectory: true)
        self.manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
        ensureDirectory()
        warmUpManifest()
    }

    func warmUpManifest() {
        stateQueue.async {
            self.loadManifestLockedIfNeeded()
        }
    }

    func cachedFileURL(for remoteURL: URL) -> URL? {
        let direct = localFileURL(for: remoteURL)
        guard fileManager.fileExists(atPath: direct.path) else { return nil }
        return direct
    }

    func cachedSizeBytes(for remoteURL: URL) -> Int64? {
        let key = remoteURL.absoluteString
        if let fromEntry = stateQueue.sync(execute: { entriesByURL[key]?.sizeBytes }), fromEntry > 0 {
            return fromEntry
        }
        return fileSize(at: localFileURL(for: remoteURL))
    }

    func fetchRemoteSize(for remoteURL: URL, completion: @escaping (Int64?) -> Void) {
        let key = remoteURL.absoluteString
        if let size = cachedSizeBytes(for: remoteURL) {
            DispatchQueue.main.async { completion(size) }
            return
        }
        if let cached = stateQueue.sync(execute: { remoteSizeCache[key] }) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        session.dataTask(with: request) { [weak self] _, response, _ in
            let size = Self.extractSize(from: response) ?? Self.extractTotalSizeFromContentRange(response: response)
            if let size {
                self?.stateQueue.async { self?.remoteSizeCache[key] = size }
            }
            DispatchQueue.main.async { completion(size) }
        }.resume()
    }

    func cacheVideo(name: String, remoteURL: URL, completion: @escaping (Result<Entry, Error>) -> Void) {
        let key = remoteURL.absoluteString
        if let entry = cachedEntry(for: remoteURL) {
            DispatchQueue.main.async { completion(.success(entry)) }
            return
        }

        stateQueue.async {
            if self.inFlightCallbacks[key] != nil {
                self.inFlightCallbacks[key]?.append(completion)
                return
            }
            self.inFlightCallbacks[key] = [completion]
            let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
            let task = self.session.downloadTask(with: request) { [weak self] tempURL, response, error in
                self?.handleDownloadFinished(name: name, remoteURL: remoteURL, key: key, tempURL: tempURL, response: response, error: error)
            }
            self.inFlightTasks[key] = task
            task.resume()
        }
    }

    func cachedEntries() -> [Entry] {
        return stateQueue.sync {
            loadManifestLockedIfNeeded()
            let pruned = entriesByURL.filter { fileManager.fileExists(atPath: cacheDirectory.appendingPathComponent($0.value.localFilename).path) }
            if pruned.count != entriesByURL.count {
                entriesByURL = pruned
                saveManifestLocked()
            }
            return entriesByURL.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    @discardableResult
    func removeCachedVideo(remoteURL: String) -> Bool {
        return stateQueue.sync {
            loadManifestLockedIfNeeded()
            guard let entry = entriesByURL[remoteURL] else { return false }
            let fullURL = cacheDirectory.appendingPathComponent(entry.localFilename)
            if fileManager.fileExists(atPath: fullURL.path) {
                try? fileManager.removeItem(at: fullURL)
            }
            entriesByURL.removeValue(forKey: remoteURL)
            remoteSizeCache.removeValue(forKey: remoteURL)
            saveManifestLocked()
            return true
        }
    }

    @discardableResult
    func clearAllCachedVideos() -> Int {
        return stateQueue.sync {
            loadManifestLockedIfNeeded()
            let existing = entriesByURL.values
            for entry in existing {
                let fullURL = cacheDirectory.appendingPathComponent(entry.localFilename)
                if fileManager.fileExists(atPath: fullURL.path) {
                    try? fileManager.removeItem(at: fullURL)
                }
            }
            entriesByURL.removeAll()
            remoteSizeCache.removeAll()
            try? fileManager.removeItem(at: manifestURL)
            saveManifestLocked()
            return existing.count
        }
    }

    func localFileURL(for entry: Entry) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(entry.localFilename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func ensureDirectory() {
        if fileManager.fileExists(atPath: cacheDirectory.path) { return }
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func localFileURL(for remoteURL: URL) -> URL {
        let key = remoteURL.absoluteString
        let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
        let fileName = Self.hashedKey(key) + "." + ext
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func cachedEntry(for remoteURL: URL) -> Entry? {
        let key = remoteURL.absoluteString
        return stateQueue.sync {
            guard let entry = entriesByURL[key] else { return nil }
            let fullURL = cacheDirectory.appendingPathComponent(entry.localFilename)
            return fileManager.fileExists(atPath: fullURL.path) ? entry : nil
        }
    }

    private func handleDownloadFinished(
        name: String,
        remoteURL: URL,
        key: String,
        tempURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        if let error {
            stateQueue.async {
                self.finishCallbacksLocked(for: key, result: .failure(error))
            }
            return
        }
        guard let tempURL else {
            stateQueue.async {
                self.finishCallbacksLocked(for: key, result: .failure(CacheError.emptyDownload))
            }
            return
        }
        ensureDirectory()
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            stateQueue.async {
                self.finishCallbacksLocked(for: key, result: .failure(CacheError.cannotCreateDirectory))
            }
            return
        }

        let destination = localFileURL(for: remoteURL)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)
            let size = fileSize(at: destination)
                ?? (response?.expectedContentLength ?? -1)
            let safeSize = max(0, size)
            let entry = Entry(
                remoteURL: key,
                name: name,
                sizeBytes: safeSize,
                localFilename: destination.lastPathComponent,
                updatedAt: Date().timeIntervalSince1970
            )
            stateQueue.async {
                self.entriesByURL[key] = entry
                if safeSize > 0 {
                    self.remoteSizeCache[key] = safeSize
                }
                self.saveManifestLocked()
                self.finishCallbacksLocked(for: key, result: .success(entry))
            }
        } catch {
            stateQueue.async {
                self.finishCallbacksLocked(for: key, result: .failure(error))
            }
        }
    }

    private func loadManifestLockedIfNeeded() {
        guard !hasLoadedManifest, !isLoadingManifest else { return }
        isLoadingManifest = true
        defer {
            isLoadingManifest = false
            hasLoadedManifest = true
        }

        guard let data = try? Data(contentsOf: manifestURL) else { return }
        guard let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        var mapping: [String: Entry] = [:]
        for entry in decoded {
            let fullURL = cacheDirectory.appendingPathComponent(entry.localFilename)
            if fileManager.fileExists(atPath: fullURL.path) {
                mapping[entry.remoteURL] = entry
                if entry.sizeBytes > 0 {
                    remoteSizeCache[entry.remoteURL] = entry.sizeBytes
                }
            }
        }
        entriesByURL = mapping
    }

    private func saveManifestLocked() {
        hasLoadedManifest = true
        let list = entriesByURL.values.sorted { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func finishCallbacksLocked(for key: String, result: Result<Entry, Error>) {
        let callbacks = inFlightCallbacks.removeValue(forKey: key) ?? []
        inFlightTasks[key] = nil
        DispatchQueue.main.async {
            callbacks.forEach { $0(result) }
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func extractSize(from response: URLResponse?) -> Int64? {
        if let length = response?.expectedContentLength, length > 0, length != -1 {
            return length
        }
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "Content-Length"),
              let bytes = Int64(raw), bytes > 0 else { return nil }
        return bytes
    }

    private static func extractTotalSizeFromContentRange(response: URLResponse?) -> Int64? {
        guard let http = response as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let slashIndex = range.lastIndex(of: "/") else { return nil }
        let totalPart = range[range.index(after: slashIndex)...]
        guard let total = Int64(totalPart), total > 0 else { return nil }
        return total
    }

    private static func hashedKey(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
