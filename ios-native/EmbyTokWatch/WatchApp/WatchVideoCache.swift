import CryptoKit
import Foundation

actor WatchVideoCache {
    static let shared = WatchVideoCache()

    struct Entry: Codable {
        let remoteURL: String
        let name: String
        let localFilename: String
        let sizeBytes: Int64
        var updatedAt: TimeInterval
    }

    private let fileManager = FileManager.default
    private let session: URLSession
    private let cacheDirectory: URL
    private let manifestURL: URL

    private let maxEntries = 5
    private let maxTotalBytes: Int64 = 250 * 1024 * 1024

    private var hasLoadedState = false
    private var entriesByURL: [String: Entry] = [:]
    private var inFlightTasks: [String: Task<URL?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.cacheDirectory = base.appendingPathComponent("EmbyTokWatchCache", isDirectory: true)
        self.manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
    }

    func resolvePlaybackURL(remoteURL: URL, name: String) async -> URL {
        ensureLoadedIfNeeded()
        if let localURL = cachedFileURL(for: remoteURL, touch: true) {
            return localURL
        }
        prefetch(remoteURL: remoteURL, name: name)
        return remoteURL
    }

    func prefetch(remoteURL: URL, name: String) {
        ensureLoadedIfNeeded()
        let key = remoteURL.absoluteString
        if cachedFileURL(for: remoteURL, touch: true) != nil {
            return
        }
        if inFlightTasks[key] != nil {
            return
        }

        let task = Task<URL?, Never> { [session] in
            do {
                let (tempURL, response) = try await session.download(from: remoteURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return nil
                }
                return self.persistDownload(tempURL: tempURL, remoteURL: remoteURL, name: name)
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task

        Task {
            _ = await task.value
            self.finishInFlight(for: key)
        }
    }

    func prefetch(items: [(remoteURL: URL, name: String)]) {
        ensureLoadedIfNeeded()
        for item in items {
            prefetch(remoteURL: item.remoteURL, name: item.name)
        }
    }

    func cachedEntries() -> [Entry] {
        ensureLoadedIfNeeded()
        return entriesByURL.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}

private extension WatchVideoCache {
    func ensureLoadedIfNeeded() {
        guard !hasLoadedState else { return }
        hasLoadedState = true

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        if
            fileManager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        {
            entriesByURL = decoded
        }

        entriesByURL = entriesByURL.filter { _, entry in
            let url = cacheDirectory.appendingPathComponent(entry.localFilename)
            return fileManager.fileExists(atPath: url.path)
        }
    }

    func finishInFlight(for key: String) {
        inFlightTasks.removeValue(forKey: key)
    }

    func persistDownload(tempURL: URL, remoteURL: URL, name: String) -> URL? {
        let key = remoteURL.absoluteString
        let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
        let filename = "\(digest(key)).\(ext)"
        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            let size = fileSize(at: destinationURL)
            guard size > 0 else {
                try? fileManager.removeItem(at: destinationURL)
                return nil
            }

            entriesByURL[key] = Entry(
                remoteURL: key,
                name: name,
                localFilename: filename,
                sizeBytes: size,
                updatedAt: Date().timeIntervalSince1970
            )
            trimIfNeeded()
            saveManifest()
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return nil
        }
    }

    func cachedFileURL(for remoteURL: URL, touch: Bool) -> URL? {
        let key = remoteURL.absoluteString
        guard var entry = entriesByURL[key] else { return nil }

        let localURL = cacheDirectory.appendingPathComponent(entry.localFilename)
        guard fileManager.fileExists(atPath: localURL.path) else {
            entriesByURL.removeValue(forKey: key)
            saveManifest()
            return nil
        }

        if touch {
            entry.updatedAt = Date().timeIntervalSince1970
            entriesByURL[key] = entry
            saveManifest()
        }
        return localURL
    }

    func trimIfNeeded() {
        var sorted = entriesByURL.values.sorted { $0.updatedAt < $1.updatedAt }

        func currentTotalSize() -> Int64 {
            sorted.reduce(0) { $0 + $1.sizeBytes }
        }

        var totalSize = currentTotalSize()
        while sorted.count > maxEntries || totalSize > maxTotalBytes {
            guard let first = sorted.first else { break }
            let localURL = cacheDirectory.appendingPathComponent(first.localFilename)
            if fileManager.fileExists(atPath: localURL.path) {
                try? fileManager.removeItem(at: localURL)
            }
            entriesByURL.removeValue(forKey: first.remoteURL)
            sorted.removeFirst()
            totalSize = currentTotalSize()
        }
    }

    func saveManifest() {
        guard let data = try? JSONEncoder().encode(entriesByURL) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    func digest(_ value: String) -> String {
        let bytes = SHA256.hash(data: Data(value.utf8))
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize {
            return Int64(size)
        }
        return 0
    }
}
