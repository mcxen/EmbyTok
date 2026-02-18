import Foundation
import SwiftUI

@MainActor
final class WatchAppState: ObservableObject {
    @Published var draft: WatchConnectionDraft
    @Published var isMuted = true
    @Published var isPureMode = true

    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var videos: [WatchVideoItem] = []
    @Published private(set) var selectedIndex = 0
    @Published var connectionError: String?

    private let client = WatchAPIClient()

    private var config: WatchServerConfig?
    private var totalCount = 0
    private var nextStartIndex = 0
    private var isLoadingMore = false

    init(draft: WatchConnectionDraft = .load()) {
        self.draft = draft
    }

    var currentItem: WatchVideoItem? {
        guard selectedIndex >= 0, selectedIndex < videos.count else { return nil }
        return videos[selectedIndex]
    }

    func updateDraft(_ mutate: (inout WatchConnectionDraft) -> Void) {
        var next = draft
        mutate(&next)
        draft = next
    }

    func persistDraft() {
        draft.save()
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func togglePureMode() {
        isPureMode.toggle()
    }

    func returnToConnect() {
        isConnected = false
        connectionError = nil
    }

    func connect() {
        guard !isConnecting else { return }

        let trimmed = draft.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = normalizeURL(trimmed) else {
            connectionError = "服务器地址格式错误"
            return
        }

        connectionError = nil
        isConnecting = true
        draft.save()

        Task { [weak self] in
            await self?.performConnect(baseURL: baseURL)
        }
    }

    func updateSelectedIndex(_ index: Int) {
        guard !videos.isEmpty else {
            selectedIndex = 0
            return
        }
        let bounded = max(0, min(index, videos.count - 1))
        if bounded != selectedIndex {
            selectedIndex = bounded
        }
        prefetchAround(index: bounded)
        loadMoreIfNeeded(currentIndex: bounded)
    }

    func playbackURL(for item: WatchVideoItem) async -> URL? {
        guard let remoteURL = mediaURL(for: item) else { return nil }
        return await WatchVideoCache.shared.resolvePlaybackURL(remoteURL: remoteURL, name: item.name)
    }
}

private extension WatchAppState {
    func performConnect(baseURL: URL) async {
        defer { isConnecting = false }

        do {
            let config = try await client.authenticate(
                serverType: draft.serverType,
                baseURL: baseURL,
                username: draft.username,
                password: draft.password
            )

            let page = try await client.fetchVideos(config: config, skip: 0, limit: 20)
            self.config = config
            self.videos = page.items
            self.totalCount = max(page.totalCount, page.items.count)
            self.nextStartIndex = page.nextStartIndex
            self.selectedIndex = 0
            self.isConnected = true
            self.connectionError = nil

            prefetchAround(index: 0)
        } catch {
            self.config = nil
            self.videos = []
            self.totalCount = 0
            self.nextStartIndex = 0
            self.selectedIndex = 0
            self.isConnected = false
            self.connectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        guard let config else { return }
        guard !isLoadingMore else { return }
        guard videos.count < totalCount else { return }
        guard currentIndex >= max(0, videos.count - 3) else { return }

        isLoadingMore = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }

            do {
                let page = try await self.client.fetchVideos(
                    config: config,
                    skip: self.nextStartIndex,
                    limit: 20
                )
                let existingIDs = Set(self.videos.map { $0.id })
                let deduped = page.items.filter { !existingIDs.contains($0.id) }
                self.videos.append(contentsOf: deduped)
                self.totalCount = max(page.totalCount, self.videos.count)
                self.nextStartIndex = page.nextStartIndex
            } catch {
                // Keep current feed uninterrupted when pagination fails.
            }
        }
    }

    func prefetchAround(index: Int) {
        guard let config else { return }
        guard !videos.isEmpty else { return }

        let candidates = [index, index + 1, index + 2]
            .filter { $0 >= 0 && $0 < videos.count }
            .map { videos[$0] }

        let resolved = candidates.compactMap { item -> (remoteURL: URL, name: String)? in
            guard let remoteURL = client.videoURL(for: item, config: config) else { return nil }
            return (remoteURL, item.name)
        }

        guard !resolved.isEmpty else { return }
        Task {
            await WatchVideoCache.shared.prefetch(items: resolved)
        }
    }

    func mediaURL(for item: WatchVideoItem) -> URL? {
        guard let config else { return nil }
        return client.videoURL(for: item, config: config)
    }

    func normalizeURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        var value = raw
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "http://" + value
        }
        return URL(string: value)
    }
}
