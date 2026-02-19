import UIKit

final class VideoFeedViewController: UIViewController {
    enum VideoFeedMode {
        case standard
        case cached
    }

    private let client: APIClient
    private let config: ServerConfig
    private let mode: VideoFeedMode

    private var items: [VideoItem] = []
    private var isLoading = false
    private var nextStartIndex = 0
    private var totalCount = 0
    private let preloadCache: PreloadCache
    private var cacheCount: Int
    private var isMuted = true
    private var isPureMode = true
    private var playbackEndAction: PlaybackEndAction
    private var favoriteIDs: Set<String>
    private weak var activeSettingsViewController: SettingsViewController?

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private var preloadWorkItem: DispatchWorkItem?
    private var memoryWarningObserver: NSObjectProtocol?
    private var gestureSettingsObserver: NSObjectProtocol?

    private var activeIndex: Int = 0
    private let initialIndex: Int

    private static let cacheCountKey = "embytok.cacheCount"
    private static let playbackEndActionKey = "embytok.playbackEndAction"
    private static let favoriteIDsKey = "embytok.favoriteIDs"
    private static let forwardPreloadCount = 5
    private static let backwardPreloadCount = 3
    private static let minimumCacheCount = forwardPreloadCount + backwardPreloadCount
    private static let defaultCacheCount = minimumCacheCount
    private static let maxSafeCacheCount = 12

    private enum ScrollDirection {
        case down
        case up
        case neutral
    }

    init(
        client: APIClient,
        config: ServerConfig,
        initialItems: [VideoItem],
        totalCount: Int,
        nextStartIndex: Int,
        initialIndex: Int = 0,
        mode: VideoFeedMode = .standard
    ) {
        self.client = client
        self.config = config
        self.mode = mode
        self.items = initialItems
        self.totalCount = totalCount
        self.nextStartIndex = nextStartIndex
        self.initialIndex = initialIndex
        self.activeIndex = max(0, min(initialIndex, max(initialItems.count - 1, 0)))
        let storedObject = UserDefaults.standard.object(forKey: Self.cacheCountKey)
        let storedCount = storedObject as? Int
        let resolvedCount = min(
            Self.maxSafeCacheCount,
            max(Self.minimumCacheCount, storedCount ?? Self.defaultCacheCount)
        )
        self.cacheCount = resolvedCount
        let storedPlaybackEndAction = UserDefaults.standard.string(forKey: Self.playbackEndActionKey)
        self.playbackEndAction = PlaybackEndAction(rawValue: storedPlaybackEndAction ?? PlaybackEndAction.loopCurrent.rawValue) ?? .loopCurrent
        self.favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: Self.favoriteIDsKey) ?? [])
        self.preloadCache = PreloadCache(maxItems: resolvedCount)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = gestureSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch mode {
        case .standard:
            title = "视频"
            let infoButton = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(openInfo))
            let gridButton = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), style: .plain, target: self, action: #selector(openGrid))
            navigationItem.rightBarButtonItems = [infoButton, gridButton]
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), style: .plain, target: self, action: #selector(openMenu))
        case .cached:
            title = "已缓存视频"
            navigationItem.rightBarButtonItems = nil
            navigationItem.leftBarButtonItem = nil
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.isPrefetchingEnabled = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        view.addSubview(collectionView)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure()
        }

        gestureSettingsObserver = NotificationCenter.default.addObserver(
            forName: GestureSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVisibleGestureSettings()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let size = collectionView.bounds.size
            if layout.itemSize != size {
                layout.itemSize = size
                layout.invalidateLayout()
                let offsetIndex = max(0, min(activeIndex, items.count - 1))
                collectionView.setContentOffset(CGPoint(x: 0, y: CGFloat(offsetIndex) * size.height), animated: false)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(isPureMode, animated: false)
        if activeIndex == 0 && initialIndex > 0 {
            scrollToIndex(initialIndex, animated: false)
        }
        playVisibleCell()
        schedulePreload(from: activeIndex, direction: .neutral, delay: 0.2)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        preloadWorkItem?.cancel()
        preloadWorkItem = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        handleMemoryPressure()
    }

    override var prefersStatusBarHidden: Bool {
        return isPureMode
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }

    private func handleMemoryPressure() {
        preloadWorkItem?.cancel()
        preloadWorkItem = nil
        preloadCache.clear()

        for visible in collectionView.visibleCells {
            guard let videoCell = visible as? VideoCell,
                  let indexPath = collectionView.indexPath(for: videoCell) else { continue }
            videoCell.handleMemoryWarning(isActiveCell: indexPath.item == activeIndex)
        }
    }

    private func updateActiveIndex() {
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        let index = Int((collectionView.contentOffset.y + height * 0.5) / height)
        if index != activeIndex {
            let previousIndex = activeIndex
            activeIndex = max(0, min(index, items.count - 1))
            let direction = preloadDirection(from: previousIndex, to: activeIndex)
            playVisibleCell()
            schedulePreload(from: activeIndex, direction: direction)
            maybeLoadMore()
        }
    }

    private func playVisibleCell() {
        for cell in collectionView.visibleCells {
            guard
                let videoCell = cell as? VideoCell,
                let indexPath = collectionView.indexPath(for: videoCell)
            else { continue }

            if indexPath.item == activeIndex {
                videoCell.applyMute(isMuted)
                videoCell.applyPureMode(isPureMode)
                videoCell.startPlayback()
            } else {
                videoCell.stopPlayback()
            }
        }
    }

    private func maybeLoadMore() {
        guard mode == .standard else { return }
        let threshold = max(0, items.count - (Self.forwardPreloadCount + 1))
        guard !isLoading, items.count < totalCount, activeIndex >= threshold else { return }
        loadMore()
    }

    private func loadMore() {
        isLoading = true
        spinner.startAnimating()
        client.fetchVideos(config: config, skip: nextStartIndex, limit: 20) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                self.isLoading = false
                switch result {
                case .success(let page):
                    self.items.append(contentsOf: page.items)
                    self.totalCount = page.totalCount
                    self.nextStartIndex = page.nextStartIndex
                    self.collectionView.reloadData()
                    self.schedulePreload(from: self.activeIndex, direction: .down, delay: 0.05)
                case .failure:
                    break
                }
            }
        }
    }

    private func preloadAround(index: Int, direction: ScrollDirection) {
        guard cacheCount > 0, !items.isEmpty else { return }
        let indexes = preloadIndexes(around: index, direction: direction)
        let keepIDs = Set(indexes.map { items[$0].id })
        preloadCache.retain(only: keepIDs)

        for preloadIndex in indexes {
            let item = items[preloadIndex]
            if let url = client.videoURL(for: item, config: config) {
                preloadCache.preload(item: item, url: url)
            }
        }
    }

    private func preloadIndexes(around index: Int, direction: ScrollDirection) -> [Int] {
        guard !items.isEmpty else { return [] }

        let forwardCount = Self.forwardPreloadCount
        let backwardCount = Self.backwardPreloadCount

        let forwardIndexes: [Int] = forwardCount > 0
            ? (1...forwardCount).map { index + $0 }.filter { $0 < items.count }
            : []
        let backwardIndexes: [Int] = backwardCount > 0
            ? (1...backwardCount).map { index - $0 }.filter { $0 >= 0 }
            : []

        switch direction {
        case .up:
            return backwardIndexes + forwardIndexes
        case .down, .neutral:
            return forwardIndexes + backwardIndexes
        }
    }

    private func preloadDirection(from oldIndex: Int, to newIndex: Int) -> ScrollDirection {
        if newIndex > oldIndex { return .down }
        if newIndex < oldIndex { return .up }
        return .neutral
    }

    private func schedulePreload(from index: Int, direction: ScrollDirection, delay: TimeInterval = 0) {
        preloadWorkItem?.cancel()
        guard cacheCount > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.preloadAround(index: index, direction: direction)
        }
        preloadWorkItem = work
        if delay <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cachedEntriesForSettings() -> [VideoDiskCache.Entry] {
        VideoDiskCache.shared.cachedEntries()
    }

    private func refreshVisibleCacheIndicators() {
        for visible in collectionView.visibleCells {
            (visible as? VideoCell)?.refreshCacheBadge()
        }
    }

    private func refreshVisibleGestureSettings() {
        for visible in collectionView.visibleCells {
            (visible as? VideoCell)?.refreshGestureAvailability()
        }
    }

    private func persistFavoriteIDs() {
        UserDefaults.standard.set(Array(favoriteIDs).sorted(), forKey: Self.favoriteIDsKey)
    }

    private func favoriteRecordsForSettings() -> [FavoriteVideoRecord] {
        var records: [FavoriteVideoRecord] = []

        for item in items where favoriteIDs.contains(item.id) {
            let detail: String
            if let duration = item.durationSeconds, duration > 0 {
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                detail = String(format: "时长 %02d:%02d", minutes, seconds)
            } else {
                detail = "当前列表视频"
            }
            records.append(FavoriteVideoRecord(id: item.id, title: item.name, detail: detail))
        }

        let knownIDs = Set(records.map { $0.id })
        let notLoadedIDs = favoriteIDs.subtracting(knownIDs).sorted()
        for id in notLoadedIDs {
            records.append(FavoriteVideoRecord(id: id, title: "收藏视频 \(String(id.prefix(6)))", detail: "未加载到当前视频流"))
        }
        return records
    }

    private func refreshVisibleFavoriteIndicators() {
        for visible in collectionView.visibleCells {
            guard
                let cell = visible as? VideoCell,
                let indexPath = collectionView.indexPath(for: cell),
                indexPath.item < items.count
            else { continue }
            let item = items[indexPath.item]
            cell.applyFavoriteState(favoriteIDs.contains(item.id))
        }
    }

    private func setFavorite(_ favorite: Bool, for itemID: String) {
        if favorite {
            favoriteIDs.insert(itemID)
        } else {
            favoriteIDs.remove(itemID)
        }
        persistFavoriteIDs()
    }

    private func jumpToRandomVideo(favoritesOnly: Bool = false) {
        guard !items.isEmpty else { return }
        let candidates: [Int]
        if favoritesOnly {
            candidates = items.enumerated().compactMap { favoriteIDs.contains($0.element.id) ? $0.offset : nil }
        } else {
            candidates = Array(items.indices)
        }
        guard !candidates.isEmpty else { return }

        let filtered = candidates.filter { $0 != activeIndex }
        let resolvedPool = filtered.isEmpty ? candidates : filtered
        guard let target = resolvedPool.randomElement() else { return }
        scrollToIndex(target, animated: true)
    }

    private func handlePlaybackEnded(for itemID: String) {
        guard playbackEndAction == .playNext else { return }
        guard let currentIndex = items.firstIndex(where: { $0.id == itemID }) else { return }

        let nextIndex = currentIndex + 1
        guard nextIndex < items.count else { return }
        scrollToIndex(nextIndex, animated: true)
    }

    @objc private func openMenu() {
        guard mode == .standard else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "查看收藏", style: .default) { [weak self] _ in
            self?.openFavorites()
        })
        sheet.addAction(UIAlertAction(title: "设置", style: .default) { [weak self] _ in
            self?.openSettings()
        })
        sheet.addAction(UIAlertAction(title: "全部视频", style: .default) { [weak self] _ in
            self?.openGrid()
        })
        sheet.addAction(UIAlertAction(title: "随机播放", style: .default) { [weak self] _ in
            self?.jumpToRandomVideo(favoritesOnly: false)
        })
        if !favoriteIDs.isEmpty {
            sheet.addAction(UIAlertAction(title: "随机收藏", style: .default) { [weak self] _ in
                self?.jumpToRandomVideo(favoritesOnly: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
            popover.permittedArrowDirections = [.up]
        }
        present(sheet, animated: true)
    }

    @objc private func openGrid() {
        guard mode == .standard else { return }
        let grid = VideoGridViewController(
            client: client,
            config: config,
            items: items,
            totalCount: totalCount,
            nextStartIndex: nextStartIndex,
            initialIndex: activeIndex
        )
        grid.onSelect = { [weak self] index in
            self?.scrollToIndex(index, animated: false)
        }
        grid.onDataUpdated = { [weak self] newItems, total, nextStart in
            self?.appendItems(newItems, totalCount: total, nextStartIndex: nextStart)
        }
        navigationController?.pushViewController(grid, animated: true)
    }

    @objc private func openInfo() {
        guard mode == .standard, !items.isEmpty else { return }
        let safeIndex = max(0, min(activeIndex, items.count - 1))
        let item = items[safeIndex]
        let remoteURL = client.videoURL(for: item, config: config)
        let info = VideoInfoViewController(
            itemID: item.id,
            name: item.name,
            filePath: item.filePath,
            sizeBytes: item.sizeBytes,
            isFavorite: favoriteIDs.contains(item.id),
            serverType: config.serverType,
            remoteURL: remoteURL
        )
        info.onToggleFavorite = { [weak self] itemID, nextFavorite in
            self?.setFavorite(nextFavorite, for: itemID)
            self?.refreshVisibleFavoriteIndicators()
        }
        info.onRenameRequested = { [weak self] itemID, newName, completion in
            self?.handleRename(itemID: itemID, newName: newName, completion: completion)
        }
        let navigation = UINavigationController(rootViewController: info)
        navigation.overrideUserInterfaceStyle = .dark
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(navigation, animated: true)
    }

    private func openFavorites() {
        let favorites = items.filter { favoriteIDs.contains($0.id) }
        let grid = VideoGridViewController(
            client: client,
            config: config,
            items: favorites,
            totalCount: favorites.count,
            nextStartIndex: favorites.count,
            titleText: "收藏",
            allowsLoadMore: false
        )
        grid.onSelect = { [weak self] index in
            guard let self = self, index < favorites.count else { return }
            let selectedID = favorites[index].id
            if let targetIndex = self.items.firstIndex(where: { $0.id == selectedID }) {
                self.scrollToIndex(targetIndex, animated: false)
            }
        }
        navigationController?.pushViewController(grid, animated: true)
    }

    func scrollToIndex(_ index: Int, animated: Bool) {
        guard !items.isEmpty else { return }
        let safeIndex = max(0, min(index, items.count - 1))
        let previousIndex = activeIndex
        activeIndex = safeIndex
        collectionView.scrollToItem(at: IndexPath(item: safeIndex, section: 0), at: .centeredVertically, animated: animated)
        playVisibleCell()
        let direction = preloadDirection(from: previousIndex, to: activeIndex)
        schedulePreload(from: activeIndex, direction: direction)
    }

    func appendItems(_ newItems: [VideoItem], totalCount: Int, nextStartIndex: Int) {
        guard !newItems.isEmpty else { return }
        let startIndex = items.count
        items.append(contentsOf: newItems)
        self.totalCount = totalCount
        self.nextStartIndex = nextStartIndex
        let indexPaths = (startIndex..<items.count).map { IndexPath(item: $0, section: 0) }
        collectionView.performBatchUpdates({
            collectionView.insertItems(at: indexPaths)
        }, completion: nil)
        schedulePreload(from: activeIndex, direction: .down, delay: 0.05)
    }

    @objc private func openSettings() {
        let storedType = UserDefaults.standard.string(forKey: "embytok.serverType")
        let currentType = ServerType(rawValue: storedType ?? config.serverType.rawValue) ?? config.serverType
        let settings = SettingsViewController(
            cacheCount: cacheCount,
            serverType: currentType,
            playbackEndAction: playbackEndAction
        )
        activeSettingsViewController = settings

        settings.onDismissed = { [weak self] in
            self?.activeSettingsViewController = nil
        }

        settings.onCacheCountChanged = { [weak self] count in
            guard let self = self else { return }
            let clamped = max(Self.minimumCacheCount, min(Self.maxSafeCacheCount, count))
            self.cacheCount = clamped
            UserDefaults.standard.set(clamped, forKey: Self.cacheCountKey)
            self.preloadCache.updateMaxItems(clamped)
            self.preloadCache.clear()
            self.schedulePreload(from: self.activeIndex, direction: .neutral, delay: 0.05)
        }
        settings.onServerTypeChanged = { serverType in
            UserDefaults.standard.set(serverType.rawValue, forKey: "embytok.serverType")
        }
        settings.onPlaybackEndActionChanged = { [weak self] action in
            guard let self = self else { return }
            self.playbackEndAction = action
            UserDefaults.standard.set(action.rawValue, forKey: Self.playbackEndActionKey)
        }
        settings.onReconnectRequested = { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
        }
        settings.onCacheEntryDeleted = { [weak self] _ in
            self?.refreshVisibleCacheIndicators()
        }
        settings.onClearCacheRequested = { [weak self] in
            let removed = VideoDiskCache.shared.clearAllCachedVideos()
            self?.preloadCache.clear()
            self?.refreshVisibleCacheIndicators()
            return removed
        }
        settings.onApplyRequested = { count, serverType in
            UserDefaults.standard.set(count, forKey: Self.cacheCountKey)
            UserDefaults.standard.set(serverType.rawValue, forKey: "embytok.serverType")
        }
        settings.speedTestURLProvider = { [weak self] in
            guard let self = self, !self.items.isEmpty else { return nil }
            let safeIndex = max(0, min(self.activeIndex, self.items.count - 1))
            let current = self.items[safeIndex]
            return self.client.videoURL(for: current, config: self.config)
        }
        settings.refreshCachedVideos(cachedEntriesForSettings())
        settings.onCachedEntrySelected = { [weak self] entry in
            return self?.cachedPlaybackController(startingAt: entry)
        }

        if let sheet = settings.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.preferredCornerRadius = 20
        }

        present(settings, animated: true)
    }

    private func handleRename(
        itemID: String,
        newName: String,
        completion: @escaping (Result<VideoInfoRenameResult, Error>) -> Void
    ) {
        guard config.serverType == .folder else {
            completion(.failure(NSError(domain: "VideoInfo", code: -1, userInfo: [NSLocalizedDescriptionKey: "当前数据源不支持改名"])))
            return
        }
        client.renameFolderVideo(config: config, itemId: itemID, newName: newName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    guard let index = self.items.firstIndex(where: { $0.id == itemID }) else {
                        completion(.failure(NSError(domain: "VideoInfo", code: -2, userInfo: [NSLocalizedDescriptionKey: "未找到对应的视频"])))
                        return
                    }
                    let oldItem = self.items[index]
                    let updated = VideoItem(
                        id: response.id,
                        name: response.name,
                        overview: response.relPath,
                        width: oldItem.width,
                        height: oldItem.height,
                        primaryImageTag: oldItem.primaryImageTag,
                        durationSeconds: oldItem.durationSeconds,
                        sizeBytes: oldItem.sizeBytes,
                        filePath: response.relPath
                    )
                    self.items[index] = updated

                    if self.favoriteIDs.contains(itemID) {
                        self.favoriteIDs.remove(itemID)
                        self.favoriteIDs.insert(response.id)
                        self.persistFavoriteIDs()
                        self.refreshVisibleFavoriteIndicators()
                    }

                    if let oldURL = self.client.videoURL(for: oldItem, config: self.config),
                       let newURL = self.client.videoURL(for: updated, config: self.config) {
                        VideoDiskCache.shared.updateRemoteURL(
                            oldRemoteURL: oldURL.absoluteString,
                            newRemoteURL: newURL.absoluteString,
                            newName: response.name
                        )
                    }

                    self.preloadCache.clear()
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    self.activeSettingsViewController?.refreshCachedVideos(self.cachedEntriesForSettings())
                    completion(.success(VideoInfoRenameResult(id: response.id, name: response.name, filePath: response.relPath)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func cachedPlaybackController(startingAt entry: VideoDiskCache.Entry) -> UIViewController? {
        let entries = cachedEntriesForSettings()
        let items = cachedVideoItems(from: entries)
        guard !items.isEmpty else { return nil }
        guard let selectedID = cachedItemID(from: entry),
              let targetIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            return nil
        }
        return VideoFeedViewController(
            client: client,
            config: config,
            initialItems: items,
            totalCount: items.count,
            nextStartIndex: items.count,
            initialIndex: targetIndex,
            mode: .cached
        )
    }

    private func cachedVideoItems(from entries: [VideoDiskCache.Entry]) -> [VideoItem] {
        return entries.compactMap { entry in
            guard let id = cachedItemID(from: entry) else { return nil }
            return VideoItem(
                id: id,
                name: entry.name,
                overview: "",
                width: nil,
                height: nil,
                primaryImageTag: nil,
                durationSeconds: nil,
                sizeBytes: entry.sizeBytes,
                filePath: nil
            )
        }
    }

    private func cachedItemID(from entry: VideoDiskCache.Entry) -> String? {
        guard let url = URL(string: entry.remoteURL) else { return nil }
        let components = url.path.split(separator: "/").map { String($0) }
        if let videosIndex = components.firstIndex(of: "Videos"), components.count > videosIndex + 1 {
            return components[videosIndex + 1]
        }
        if let streamIndex = components.firstIndex(of: "stream"), components.count > streamIndex + 1 {
            return components[streamIndex + 1]
        }
        return nil
    }
}

extension VideoFeedViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseId, for: indexPath) as? VideoCell else {
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        cell.configure(
            item: item,
            config: config,
            client: client,
            preloadCache: preloadCache,
            isMuted: isMuted,
            isPureMode: isPureMode,
            isFavorite: favoriteIDs.contains(item.id),
            playbackEndAction: playbackEndAction
        )
        cell.onToggleMute = { [weak self] in
            guard let self = self else { return }
            self.isMuted.toggle()
            for visible in self.collectionView.visibleCells {
                (visible as? VideoCell)?.applyMute(self.isMuted)
            }
        }
        cell.onTogglePureMode = { [weak self] in
            guard let self = self else { return }
            self.isPureMode.toggle()
            self.navigationController?.setNavigationBarHidden(self.isPureMode, animated: true)
            self.setNeedsStatusBarAppearanceUpdate()
            for visible in self.collectionView.visibleCells {
                (visible as? VideoCell)?.applyPureMode(self.isPureMode)
            }
        }
        cell.onCacheStateChanged = { [weak self] in
            guard let self = self else { return }
            self.activeSettingsViewController?.refreshCachedVideos(self.cachedEntriesForSettings())
        }
        cell.onToggleFavorite = { [weak self] nextFavorite in
            self?.setFavorite(nextFavorite, for: item.id)
        }
        cell.onRandomRequested = { [weak self] in
            self?.jumpToRandomVideo(favoritesOnly: false)
        }
        cell.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackEnded(for: item.id)
        }
        return cell
    }
}

extension VideoFeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item == activeIndex, let videoCell = cell as? VideoCell else { return }
        videoCell.applyMute(isMuted)
        videoCell.applyPureMode(isPureMode)
        videoCell.startPlayback()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateActiveIndex()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateActiveIndex()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? VideoCell)?.stopPlayback()
    }
}
