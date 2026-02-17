import AVFoundation

final class PreloadCache {
    private var cache: [String: AVPlayerItem] = [:]
    private let maxItems: Int

    init(maxItems: Int = 2) {
        self.maxItems = maxItems
    }

    func preload(id: String, url: URL) {
        if cache[id] != nil { return }
        if cache.count >= maxItems {
            if let oldest = cache.keys.first {
                cache.removeValue(forKey: oldest)
            }
        }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        cache[id] = item
        asset.loadValuesAsynchronously(forKeys: ["playable"]) { }
    }

    func take(id: String) -> AVPlayerItem? {
        return cache.removeValue(forKey: id)
    }

    func clear() {
        cache.removeAll()
    }
}
