import UIKit

final class VideoFeedViewController: UIViewController {
    private let client: APIClient
    private let config: ServerConfig

    private var items: [VideoItem] = []
    private var isLoading = false
    private var nextStartIndex = 0
    private var totalCount = 0
    private let preloadCache: PreloadCache
    private var cacheCount: Int
    private var isMuted = true
    private var isPureMode = false
    private var favoriteIDs: Set<String>
    private let speedTestService = SpeedTestService()

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private var preloadWorkItem: DispatchWorkItem?
    private var memoryWarningObserver: NSObjectProtocol?

    private var activeIndex: Int = 0
    private let initialIndex: Int

    private static let cacheCountKey = "embytok.cacheCount"
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

    init(client: APIClient, config: ServerConfig, initialItems: [VideoItem], totalCount: Int, nextStartIndex: Int, initialIndex: Int = 0) {
        self.client = client
        self.config = config
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "视频"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), style: .plain, target: self, action: #selector(openGrid))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), style: .plain, target: self, action: #selector(openMenu))

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

    private func cachedDisplayNamesForSettings() -> [String] {
        let local = VideoDiskCache.shared.cachedEntries().map {
            "离线缓存 · \($0.name) (\(VideoDiskCache.formatSize($0.sizeBytes)))"
        }
        let warm = preloadCache.cachedNames().map { "预加载 · \($0)" }
        return local + warm
    }

    private func persistFavoriteIDs() {
        UserDefaults.standard.set(Array(favoriteIDs).sorted(), forKey: Self.favoriteIDsKey)
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

    @objc private func openMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
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
        let grid = VideoGridViewController(client: client, config: config, items: items, totalCount: totalCount, nextStartIndex: nextStartIndex)
        grid.onSelect = { [weak self] index in
            self?.scrollToIndex(index, animated: false)
        }
        grid.onDataUpdated = { [weak self] newItems, total, nextStart in
            self?.appendItems(newItems, totalCount: total, nextStartIndex: nextStart)
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
        let settings = SettingsViewController(cacheCount: cacheCount, serverType: currentType)
        settings.onCacheCountChanged = { [weak self, weak settings] count in
            guard let self = self else { return }
            let clamped = max(Self.minimumCacheCount, min(Self.maxSafeCacheCount, count))
            self.cacheCount = clamped
            UserDefaults.standard.set(clamped, forKey: Self.cacheCountKey)
            self.preloadCache.updateMaxItems(clamped)
            self.preloadCache.clear()
            self.schedulePreload(from: self.activeIndex, direction: .neutral, delay: 0.05)
            settings?.updateCachedVideos(self.cachedDisplayNamesForSettings())
        }
        settings.onServerTypeChanged = { serverType in
            UserDefaults.standard.set(serverType.rawValue, forKey: "embytok.serverType")
        }
        settings.onReconnectRequested = { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
        }
        settings.onSpeedTestRequested = { [weak self] in
            guard let self = self else { return }
            guard let current = self.items.first, let url = self.client.videoURL(for: current, config: self.config) else {
                settings.updateSpeedTestResult("没有可测速的视频")
                return
            }
            self.speedTestService.runTest(url: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (mbps, duration)):
                        settings.updateSpeedTestResult(String(format: "%.2f Mbps (%.2fs)", mbps, duration))
                    case .failure(let error):
                        settings.updateSpeedTestResult("测速失败：\(error.localizedDescription)")
                    }
                }
            }
        }
        settings.updateCachedVideos(cachedDisplayNamesForSettings())
        navigationController?.pushViewController(settings, animated: true)
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
            isFavorite: favoriteIDs.contains(item.id)
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
            if let settings = self.navigationController?.topViewController as? SettingsViewController {
                settings.updateCachedVideos(self.cachedDisplayNamesForSettings())
            }
        }
        cell.onToggleFavorite = { [weak self] nextFavorite in
            self?.setFavorite(nextFavorite, for: item.id)
        }
        cell.onRandomRequested = { [weak self] in
            self?.jumpToRandomVideo(favoritesOnly: false)
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
