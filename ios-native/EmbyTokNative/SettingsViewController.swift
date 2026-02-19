import UIKit

private enum SettingsSection: Hashable {
    case source
    case cacheAndPlayback
    case library
}

private enum PlaybackRow: Hashable {
    case cacheCount
    case playbackEndAction
    case timeDisplayMode
    case speedTest
}

private enum SettingsActionKind: Int, CaseIterable {
    case gestureControl
    case reconnect
    case clearCache
    case apply

    var title: String {
        switch self {
        case .gestureControl: return "手势控制"
        case .reconnect: return "重新连接"
        case .clearCache: return "清除缓存"
        case .apply: return "保存并应用"
        }
    }
}

final class SettingsViewController: UIViewController {
    private static let minCacheCount = 8
    private static let maxCacheCount = 12
    private static let speedTestSeconds = 12

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dimOverlayView = UIView()
    private let grabberView = UIView()
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let errorBannerView = UIView()
    private let errorBannerLabel = UILabel()
    private let errorBannerButton = UIButton(type: .system)
    private var errorBannerHeightConstraint: NSLayoutConstraint?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var cacheCount: Int
    private var serverType: ServerType
    private var playbackEndAction: PlaybackEndAction
    private var timeDisplayMode: TimeDisplayMode
    private var cachedEntries: [VideoDiskCache.Entry] = []

    private var isSpeedTesting = false
    private var speedRemainingSeconds = 0
    private var speedDownloadMbps: Double?
    private var speedUploadMbps: Double?
    private var speedProgress: Double = 0
    private var speedStatusText = "点击开始测速"
    private var speedTimer: Timer?
    private var speedToken = UUID()

    private let speedTestService = SpeedTestService()
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let notifyHaptic = UINotificationFeedbackGenerator()

    private var didNotifyDismissed = false

    var onCacheCountChanged: ((Int) -> Void)?
    var onServerTypeChanged: ((ServerType) -> Void)?
    var onPlaybackEndActionChanged: ((PlaybackEndAction) -> Void)?
    var onTimeDisplayModeChanged: ((TimeDisplayMode) -> Void)?
    var onReconnectRequested: (() -> Void)?
    var onCacheEntryDeleted: ((VideoDiskCache.Entry) -> Void)?
    var onClearCacheRequested: (() -> Int)?
    var onApplyRequested: ((Int, ServerType) -> Void)?
    var onDismissed: (() -> Void)?
    var speedTestURLProvider: (() -> URL?)?
    var favoriteItemsProvider: (() -> [FavoriteVideoRecord])?
    var onFavoriteRemoved: ((String) -> Void)?
    var onFavoriteSelected: ((String) -> Void)?
    var onCachedEntrySelected: ((VideoDiskCache.Entry) -> UIViewController?)?

    init(cacheCount: Int, serverType: ServerType, playbackEndAction: PlaybackEndAction, timeDisplayMode: TimeDisplayMode) {
        self.cacheCount = max(Self.minCacheCount, min(Self.maxCacheCount, cacheCount))
        self.serverType = serverType
        self.playbackEndAction = playbackEndAction
        self.timeDisplayMode = timeDisplayMode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        invalidateSpeedTimer()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0, alpha: 1)
        presentationController?.delegate = self

        configureBackground()
        configureHeader()
        configureErrorBanner()
        configureTableView()

        refreshCachedVideos(VideoDiskCache.shared.cachedEntries())
        rigidHaptic.prepare()
        heavyHaptic.prepare()
        notifyHaptic.prepare()
    }

    func refreshCachedVideos(_ entries: [VideoDiskCache.Entry]) {
        cachedEntries = entries.sorted { $0.updatedAt > $1.updatedAt }
        guard isViewLoaded else { return }
        if let librarySectionIndex = visibleSections.firstIndex(of: .library) {
            tableView.reloadSections(IndexSet(integer: librarySectionIndex), with: .none)
        } else {
            tableView.reloadData()
        }
    }

    func showConnectionErrorBanner(_ message: String = "连接失败，重试？") {
        errorBannerLabel.text = message
        errorBannerHeightConstraint?.constant = 46
        UIView.animate(withDuration: 0.2) {
            self.errorBannerView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private var visibleSections: [SettingsSection] {
        [.source, .cacheAndPlayback, .library]
    }

    private var playbackRows: [PlaybackRow] {
        [.cacheCount, .playbackEndAction, .timeDisplayMode, .speedTest]
    }

    private func configureBackground() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false

        dimOverlayView.translatesAutoresizingMaskIntoConstraints = false
        dimOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        dimOverlayView.isUserInteractionEnabled = false

        view.addSubview(blurView)
        view.addSubview(dimOverlayView)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            dimOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureHeader() {
        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.backgroundColor = UIColor(white: 0.45, alpha: 1)
        grabberView.layer.cornerRadius = 2.5
        grabberView.accessibilityLabel = "拖拽指示条"

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .clear

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle(" 视频", for: .normal)
        backButton.tintColor = UIColor(white: 0.92, alpha: 1)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "返回视频"
        backButton.accessibilityHint = "关闭设置并返回视频"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "设置"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("完成", for: .normal)
        doneButton.tintColor = UIColor(white: 0.92, alpha: 1)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.accessibilityLabel = "完成"
        doneButton.accessibilityHint = "关闭设置面板"

        view.addSubview(grabberView)
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 38),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            headerView.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 9),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),

            doneButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            doneButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func configureErrorBanner() {
        errorBannerView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.95)
        errorBannerView.layer.cornerRadius = 12
        errorBannerView.alpha = 0

        errorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        errorBannerLabel.text = "连接失败，重试？"
        errorBannerLabel.textColor = .white
        errorBannerLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        errorBannerLabel.numberOfLines = 1

        errorBannerButton.translatesAutoresizingMaskIntoConstraints = false
        errorBannerButton.setTitle("重连", for: .normal)
        errorBannerButton.setTitleColor(.white, for: .normal)
        errorBannerButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        errorBannerButton.addTarget(self, action: #selector(retryFromBannerTapped), for: .touchUpInside)
        errorBannerButton.accessibilityLabel = "重连"
        errorBannerButton.accessibilityHint = "重新连接到数据源"

        view.addSubview(errorBannerView)
        errorBannerView.addSubview(errorBannerLabel)
        errorBannerView.addSubview(errorBannerButton)

        errorBannerHeightConstraint = errorBannerView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            errorBannerView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 6),
            errorBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            errorBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            errorBannerHeightConstraint!,

            errorBannerLabel.leadingAnchor.constraint(equalTo: errorBannerView.leadingAnchor, constant: 12),
            errorBannerLabel.centerYAnchor.constraint(equalTo: errorBannerView.centerYAnchor),

            errorBannerButton.trailingAnchor.constraint(equalTo: errorBannerView.trailingAnchor, constant: -12),
            errorBannerButton.centerYAnchor.constraint(equalTo: errorBannerView.centerYAnchor),
            errorBannerButton.leadingAnchor.constraint(greaterThanOrEqualTo: errorBannerLabel.trailingAnchor, constant: 12)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderTopPadding = 8
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.rowHeight = 56
        tableView.estimatedRowHeight = 56

        tableView.register(SourceSelectionCell.self, forCellReuseIdentifier: SourceSelectionCell.reuseID)
        tableView.register(CacheStepperCell.self, forCellReuseIdentifier: CacheStepperCell.reuseID)
        tableView.register(PlaybackEndActionCell.self, forCellReuseIdentifier: PlaybackEndActionCell.reuseID)
        tableView.register(TimeDisplayModeCell.self, forCellReuseIdentifier: TimeDisplayModeCell.reuseID)
        tableView.register(SpeedTestCell.self, forCellReuseIdentifier: SpeedTestCell.reuseID)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: errorBannerView.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func hideErrorBanner() {
        guard errorBannerView.alpha > 0 else { return }
        errorBannerHeightConstraint?.constant = 0
        UIView.animate(withDuration: 0.2) {
            self.errorBannerView.alpha = 0
            self.view.layoutIfNeeded()
        }
    }

    private func applyServerType(index: Int) {
        let boundedIndex = max(0, min(index, ServerType.allCases.count - 1))
        let selectedType = ServerType.allCases[boundedIndex]
        guard selectedType != serverType else { return }

        rigidHaptic.impactOccurred()
        serverType = selectedType
        onServerTypeChanged?(selectedType)

        stopSpeedTestUI(resetStatusText: true)

        UIView.transition(with: tableView, duration: 0.2, options: .transitionCrossDissolve) {
            self.tableView.reloadData()
        }
    }

    private func applyCacheCount(_ value: Int) {
        let clamped = max(Self.minCacheCount, min(Self.maxCacheCount, value))
        guard clamped != cacheCount else { return }

        rigidHaptic.impactOccurred()
        cacheCount = clamped
        onCacheCountChanged?(clamped)
    }

    private func applyPlaybackEndAction(index: Int) {
        let boundedIndex = max(0, min(index, PlaybackEndAction.allCases.count - 1))
        let selected = PlaybackEndAction.allCases[boundedIndex]
        guard selected != playbackEndAction else { return }
        rigidHaptic.impactOccurred()
        playbackEndAction = selected
        onPlaybackEndActionChanged?(selected)
    }

    private func applyTimeDisplayMode(index: Int) {
        let boundedIndex = max(0, min(index, TimeDisplayMode.allCases.count - 1))
        let selected = TimeDisplayMode.allCases[boundedIndex]
        guard selected != timeDisplayMode else { return }
        rigidHaptic.impactOccurred()
        timeDisplayMode = selected
        onTimeDisplayModeChanged?(selected)
    }

    private func startSpeedTest() {
        guard !isSpeedTesting else { return }
        guard let url = speedTestURLProvider?() else {
            speedStatusText = "没有可测速的视频"
            showConnectionErrorBanner()
            reloadSpeedSection()
            notifyHaptic.notificationOccurred(.error)
            return
        }

        hideErrorBanner()
        heavyHaptic.impactOccurred()

        isSpeedTesting = true
        speedRemainingSeconds = Self.speedTestSeconds
        speedDownloadMbps = 0
        speedUploadMbps = 0
        speedProgress = 0
        speedStatusText = "测速中…"

        let currentToken = UUID()
        speedToken = currentToken
        startSpeedTimer(with: currentToken)
        reloadSpeedSection()

        speedTestService.runLiveTest(
            url: url,
            sampleCount: Self.speedTestSeconds,
            onUpdate: { [weak self] update in
                guard let self = self, self.speedToken == currentToken else { return }
                self.speedDownloadMbps = update.downloadMbps
                self.speedUploadMbps = update.uploadMbps
                self.speedProgress = update.progress
                self.speedStatusText = String(
                    format: "下载 %.2f Mbps · 上传估算 %.2f Mbps",
                    update.downloadMbps,
                    update.uploadMbps
                )
                self.reloadSpeedSection()
            },
            completion: { [weak self] result in
                guard let self = self, self.speedToken == currentToken else { return }
                self.stopSpeedTimer()
                self.isSpeedTesting = false
                self.speedRemainingSeconds = 0
                self.speedProgress = 1

                switch result {
                case .success(let final):
                    self.speedDownloadMbps = final.downloadMbps
                    self.speedUploadMbps = final.uploadMbps
                    self.speedStatusText = String(
                        format: "完成：下载 %.2f Mbps · 上传估算 %.2f Mbps",
                        final.downloadMbps,
                        final.uploadMbps
                    )
                    self.notifyHaptic.notificationOccurred(.success)
                case .failure(let error):
                    self.speedStatusText = "测速失败：\(error.localizedDescription)"
                    self.showConnectionErrorBanner()
                    self.notifyHaptic.notificationOccurred(.error)
                }

                self.reloadSpeedSection()
            }
        )
    }

    private func toggleSpeedTest() {
        if isSpeedTesting {
            cancelSpeedTest()
        } else {
            startSpeedTest()
        }
    }

    private func cancelSpeedTest() {
        guard isSpeedTesting else { return }
        stopSpeedTestUI(resetStatusText: false)
        speedStatusText = "测速已取消"
        speedDownloadMbps = nil
        speedUploadMbps = nil
        notifyHaptic.notificationOccurred(.warning)
        reloadSpeedSection()
    }

    private func startSpeedTimer(with token: UUID) {
        stopSpeedTimer()
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            guard self.speedToken == token else {
                timer.invalidate()
                return
            }

            if self.speedRemainingSeconds > 0 {
                self.speedRemainingSeconds -= 1
                self.reloadSpeedSection()
            } else {
                timer.invalidate()
            }
        }
        if let speedTimer {
            RunLoop.main.add(speedTimer, forMode: .common)
        }
    }

    private func stopSpeedTimer() {
        speedTimer?.invalidate()
        speedTimer = nil
    }

    private func invalidateSpeedTimer() {
        stopSpeedTimer()
    }

    private func stopSpeedTestUI(resetStatusText: Bool) {
        speedToken = UUID()
        isSpeedTesting = false
        speedRemainingSeconds = 0
        speedProgress = 0
        stopSpeedTimer()
        if resetStatusText {
            speedStatusText = "点击开始测速"
            speedDownloadMbps = nil
            speedUploadMbps = nil
        }
    }

    private func reloadSpeedSection() {
        guard let sectionIndex = visibleSections.firstIndex(of: .cacheAndPlayback) else { return }
        guard let rowIndex = playbackRows.firstIndex(of: .speedTest) else { return }
        tableView.reloadRows(at: [IndexPath(row: rowIndex, section: sectionIndex)], with: .none)
    }

    private func deleteCachedEntry(_ entry: VideoDiskCache.Entry) {
        guard VideoDiskCache.shared.removeCachedVideo(remoteURL: entry.remoteURL) else { return }
        cachedEntries.removeAll { $0.remoteURL == entry.remoteURL }
        onCacheEntryDeleted?(entry)
        notifyHaptic.notificationOccurred(.success)
        refreshCachedVideos(VideoDiskCache.shared.cachedEntries())
    }

    private func shareCachedEntry(_ entry: VideoDiskCache.Entry) {
        let item: Any = VideoDiskCache.shared.localFileURL(for: entry) ?? entry.remoteURL
        let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(activity, animated: true)
    }

    private func presentClearCacheConfirmation() {
        let alert = UIAlertController(title: "清除缓存", message: "确认清除所有已缓存视频？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let removed = self.onClearCacheRequested?() ?? VideoDiskCache.shared.clearAllCachedVideos()
            self.refreshCachedVideos(VideoDiskCache.shared.cachedEntries())
            self.speedStatusText = removed > 0 ? "已清除 \(removed) 项缓存" : "暂无可清除缓存"
            self.notifyHaptic.notificationOccurred(.success)
            self.reloadSpeedSection()
        })
        present(alert, animated: true)
    }

    private func presentFavoritesManagement() {
        let records = favoriteItemsProvider?() ?? []
        let favoritesController = FavoritesManagementViewController(records: records)
        favoritesController.reloadProvider = { [weak self] in
            self?.favoriteItemsProvider?() ?? []
        }
        favoritesController.onFavoriteRemoved = { [weak self] favoriteID in
            self?.onFavoriteRemoved?(favoriteID)
        }
        favoritesController.onFavoriteSelected = { [weak self] favoriteID in
            self?.onFavoriteSelected?(favoriteID)
        }
        let navigation = UINavigationController(rootViewController: favoritesController)
        navigation.overrideUserInterfaceStyle = .dark
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(navigation, animated: true)
    }

    private func presentCachedVideosManagement() {
        let managementController = CachedVideosManagementViewController(entries: cachedEntries)
        managementController.reloadProvider = {
            VideoDiskCache.shared.cachedEntries()
        }
        managementController.onDeleteEntry = { [weak self] entry in
            self?.deleteCachedEntry(entry)
        }
        managementController.onShareEntry = { [weak self] entry in
            self?.shareCachedEntry(entry)
        }
        managementController.onEntrySelected = { [weak self] entry in
            return self?.onCachedEntrySelected?(entry)
        }

        let navigation = UINavigationController(rootViewController: managementController)
        navigation.overrideUserInterfaceStyle = .dark
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(navigation, animated: true)
    }

    private func presentGestureSettings() {
        let controller = GestureSettingsViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.overrideUserInterfaceStyle = .dark
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(navigation, animated: true)
    }

    private func dismissPanel(triggerApply: Bool) {
        if triggerApply {
            onApplyRequested?(cacheCount, serverType)
        }
        dismiss(animated: true) { [weak self] in
            self?.notifyDismissedIfNeeded()
        }
    }

    private func notifyDismissedIfNeeded() {
        guard !didNotifyDismissed else { return }
        didNotifyDismissed = true
        onDismissed?()
    }

    @objc private func backTapped() {
        dismissPanel(triggerApply: false)
    }

    @objc private func doneTapped() {
        dismissPanel(triggerApply: false)
    }

    @objc private func retryFromBannerTapped() {
        heavyHaptic.impactOccurred()
        onReconnectRequested?()
        dismissPanel(triggerApply: false)
    }
}

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = visibleSections[section]
        switch sectionType {
        case .source:
            return 1
        case .cacheAndPlayback:
            return playbackRows.count
        case .library:
            return 1 + SettingsActionKind.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionType = visibleSections[indexPath.section]

        switch sectionType {
        case .source:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: SourceSelectionCell.reuseID, for: indexPath) as? SourceSelectionCell else {
                return UITableViewCell()
            }
            cell.configure(serverType: serverType)
            cell.onSourceChanged = { [weak self] selectedIndex in
                self?.applyServerType(index: selectedIndex)
            }
            return cell

        case .cacheAndPlayback:
            let rowType = playbackRows[indexPath.row]
            switch rowType {
            case .cacheCount:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: CacheStepperCell.reuseID, for: indexPath) as? CacheStepperCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    cacheCount: cacheCount,
                    minValue: Self.minCacheCount,
                    maxValue: Self.maxCacheCount
                )
                cell.onCacheCountChanged = { [weak self] newValue in
                    self?.applyCacheCount(newValue)
                }
                return cell
            case .playbackEndAction:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: PlaybackEndActionCell.reuseID, for: indexPath) as? PlaybackEndActionCell else {
                    return UITableViewCell()
                }
                cell.configure(action: playbackEndAction)
                cell.onActionChanged = { [weak self] selectedIndex in
                    self?.applyPlaybackEndAction(index: selectedIndex)
                }
                return cell
            case .timeDisplayMode:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: TimeDisplayModeCell.reuseID, for: indexPath) as? TimeDisplayModeCell else {
                    return UITableViewCell()
                }
                cell.configure(mode: timeDisplayMode)
                cell.onModeChanged = { [weak self] selectedIndex in
                    self?.applyTimeDisplayMode(index: selectedIndex)
                }
                return cell
            case .speedTest:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: SpeedTestCell.reuseID, for: indexPath) as? SpeedTestCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    isTesting: isSpeedTesting,
                    downloadMbps: speedDownloadMbps,
                    uploadMbps: speedUploadMbps,
                    remainingSeconds: speedRemainingSeconds,
                    progress: speedProgress,
                    statusText: speedStatusText
                )
                cell.onStartTapped = { [weak self] in
                    self?.toggleSpeedTest()
                }
                return cell
            }

        case .library:
            if indexPath.row == 0 {
                let reuseID = "CachedVideosEntryCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
                cell.backgroundColor = .clear
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator

                var content = cell.defaultContentConfiguration()
                content.text = "已缓存视频"
                if cachedEntries.isEmpty {
                    content.secondaryText = "暂无缓存，进入后可管理视频缓存"
                } else {
                    let totalBytes = cachedEntries.reduce(Int64(0)) { $0 + $1.sizeBytes }
                    content.secondaryText = "\(cachedEntries.count) 项 · \(VideoDiskCache.formatSize(totalBytes))"
                }
                content.textProperties.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13, weight: .regular)
                content.secondaryTextProperties.color = UIColor(white: 0.72, alpha: 1)
                cell.contentConfiguration = content
                cell.accessibilityLabel = content.secondaryText == nil ? "已缓存视频" : "已缓存视频，\(content.secondaryText!)"
                cell.accessibilityHint = "打开缓存视频管理页面"
                return cell
            }

            guard let action = SettingsActionKind(rawValue: indexPath.row - 1) else {
                return UITableViewCell()
            }
            let reuseID = "LibraryActionCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
            cell.backgroundColor = .clear
            cell.selectionStyle = .default
            cell.accessoryType = action == .gestureControl ? .disclosureIndicator : .none

            var content = cell.defaultContentConfiguration()
            content.text = action.title
            content.textProperties.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            content.secondaryTextProperties.color = UIColor(white: 0.72, alpha: 1)
            content.imageProperties.tintColor = UIColor(white: 0.8, alpha: 1)

            switch action {
            case .gestureControl:
                content.secondaryText = "开启与配置播放手势"
                content.image = UIImage(systemName: "hand.tap")
                content.textProperties.color = .white
                content.imageProperties.tintColor = UIColor(white: 0.8, alpha: 1)
            case .reconnect:
                content.secondaryText = "重新连接当前数据源"
                content.image = UIImage(systemName: "arrow.clockwise")
                content.textProperties.color = .systemBlue
            case .clearCache:
                content.secondaryText = "删除所有本地缓存文件"
                content.image = UIImage(systemName: "trash")
                content.textProperties.color = .systemRed
                content.imageProperties.tintColor = .systemRed
            case .apply:
                content.secondaryText = "保存当前设置并立即生效"
                content.image = UIImage(systemName: "checkmark.circle")
                content.textProperties.color = .systemGreen
                content.imageProperties.tintColor = .systemGreen
            }

            cell.contentConfiguration = content
            cell.accessibilityLabel = action.title
            return cell
        }
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let sectionType = visibleSections[indexPath.section]
        switch sectionType {
        case .source:
            return 68
        case .cacheAndPlayback:
            let rowType = playbackRows[indexPath.row]
            switch rowType {
            case .cacheCount:
                return 56
            case .playbackEndAction:
                return 68
            case .timeDisplayMode:
                return 68
            case .speedTest:
                return 78
            }
        case .library:
            return 56
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleSections[section] {
        case .source:
            return "数据源"
        case .cacheAndPlayback:
            return "缓存与播放"
        case .library:
            return "已缓存视频"
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        24
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        6
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        let sectionType = visibleSections[indexPath.section]
        guard sectionType == .library else { return }

        if indexPath.row == 0 {
            presentCachedVideosManagement()
            return
        }

        guard let action = SettingsActionKind(rawValue: indexPath.row - 1) else { return }
        switch action {
        case .gestureControl:
            rigidHaptic.impactOccurred()
            presentGestureSettings()
        case .reconnect:
            heavyHaptic.impactOccurred()
            onReconnectRequested?()
            dismissPanel(triggerApply: false)
        case .clearCache:
            presentClearCacheConfirmation()
        case .apply:
            notifyHaptic.notificationOccurred(.success)
            dismissPanel(triggerApply: true)
        }
    }
}

extension SettingsViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        notifyDismissedIfNeeded()
    }
}

private final class SourceSelectionCell: UITableViewCell {
    static let reuseID = "SourceSelectionCell"

    let segmentedControl = UISegmentedControl(items: ServerType.allCases.map { $0.displayName })
    var onSourceChanged: ((Int) -> Void)?

    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "数据源"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentTintColor = UIColor.systemIndigo
        segmentedControl.backgroundColor = UIColor(white: 0.15, alpha: 1)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.accessibilityLabel = "数据源切换"
        segmentedControl.accessibilityHint = "切换后将立即刷新可用设置"

        let stack = UIStackView(arrangedSubviews: [titleLabel, segmentedControl])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(serverType: ServerType) {
        segmentedControl.selectedSegmentIndex = ServerType.allCases.firstIndex(of: serverType) ?? 0
    }

    @objc private func segmentChanged() {
        onSourceChanged?(segmentedControl.selectedSegmentIndex)
    }
}

private final class CacheStepperCell: UITableViewCell {
    static let reuseID = "CacheStepperCell"

    var onCacheCountChanged: ((Int) -> Void)?

    private let valueLabel = UILabel()
    private let stepper = UIStepper()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let leftStack = UIStackView()
    private let rightStack = UIStackView()
    private let containerStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.textColor = .white
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        stepper.stepValue = 1
        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        stepper.accessibilityLabel = "缓存数量步进器"
        stepper.accessibilityHint = "双击后上下滑动以调整缓存数量"
        stepper.setContentCompressionResistancePriority(.required, for: .horizontal)
        stepper.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = UIColor(white: 0.7, alpha: 1)
        subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)

        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.addArrangedSubview(titleLabel)
        leftStack.addArrangedSubview(subtitleLabel)

        rightStack.axis = .horizontal
        rightStack.alignment = .center
        rightStack.spacing = 10
        rightStack.addArrangedSubview(valueLabel)
        rightStack.addArrangedSubview(stepper)

        containerStack.axis = .horizontal
        containerStack.alignment = .center
        containerStack.distribution = .fill
        containerStack.spacing = 12
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(leftStack)
        containerStack.addArrangedSubview(rightStack)

        leftStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(containerStack)
        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(cacheCount: Int, minValue: Int, maxValue: Int) {
        titleLabel.text = "缓存数量"
        subtitleLabel.text = "推荐值：5-12"

        stepper.minimumValue = Double(minValue)
        stepper.maximumValue = Double(maxValue)
        stepper.value = Double(cacheCount)
        valueLabel.text = "\(cacheCount)"
        accessibilityLabel = "缓存数量 \(cacheCount)"
    }

    @objc private func stepperChanged() {
        let value = Int(stepper.value)
        valueLabel.text = "\(value)"
        onCacheCountChanged?(value)
    }
}

private final class PlaybackEndActionCell: UITableViewCell {
    static let reuseID = "PlaybackEndActionCell"

    var onActionChanged: ((Int) -> Void)?
    private let titleLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: PlaybackEndAction.allCases.map { $0.displayName })

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "播放完当前视频后"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentTintColor = UIColor.systemIndigo
        segmentedControl.backgroundColor = UIColor(white: 0.15, alpha: 1)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.accessibilityLabel = "播放结束后动作"
        segmentedControl.accessibilityHint = "选择循环当前视频或切换到下一个视频"

        let stack = UIStackView(arrangedSubviews: [titleLabel, segmentedControl])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(action: PlaybackEndAction) {
        segmentedControl.selectedSegmentIndex = PlaybackEndAction.allCases.firstIndex(of: action) ?? 0
    }

    @objc private func segmentChanged() {
        onActionChanged?(segmentedControl.selectedSegmentIndex)
    }
}

private final class TimeDisplayModeCell: UITableViewCell {
    static let reuseID = "TimeDisplayModeCell"

    var onModeChanged: ((Int) -> Void)?
    private let titleLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: TimeDisplayMode.allCases.map { $0.displayName })

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "时间显示"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentTintColor = UIColor.systemIndigo
        segmentedControl.backgroundColor = UIColor(white: 0.15, alpha: 1)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.accessibilityLabel = "时间显示"
        segmentedControl.accessibilityHint = "切换进度显示的时长样式"

        let stack = UIStackView(arrangedSubviews: [titleLabel, segmentedControl])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(mode: TimeDisplayMode) {
        segmentedControl.selectedSegmentIndex = TimeDisplayMode.allCases.firstIndex(of: mode) ?? 0
    }

    @objc private func segmentChanged() {
        onModeChanged?(segmentedControl.selectedSegmentIndex)
    }
}

private final class SpeedTestCell: UITableViewCell {
    static let reuseID = "SpeedTestCell"

    var onStartTapped: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let topStack = UIStackView()
    private let rightStack = UIStackView()
    private let containerStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)

        statusLabel.textColor = UIColor(white: 0.7, alpha: 1)
        statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        statusLabel.numberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var config = UIButton.Configuration.tinted()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        config.baseForegroundColor = .systemBlue
        config.title = "开始测速"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        startButton.configuration = config
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        startButton.accessibilityLabel = "开始测速"
        startButton.accessibilityHint = "点击后将进行约12秒测速"

        spinner.hidesWhenStopped = true
        spinner.color = .systemBlue

        rightStack.axis = .horizontal
        rightStack.alignment = .center
        rightStack.spacing = 8
        rightStack.addArrangedSubview(startButton)
        rightStack.addArrangedSubview(spinner)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)

        topStack.axis = .horizontal
        topStack.alignment = .center
        topStack.distribution = .fill
        topStack.spacing = 12
        topStack.addArrangedSubview(titleLabel)
        topStack.addArrangedSubview(rightStack)

        containerStack.axis = .vertical
        containerStack.alignment = .fill
        containerStack.distribution = .fill
        containerStack.spacing = 4
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(topStack)
        containerStack.addArrangedSubview(statusLabel)

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(containerStack)
        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        isTesting: Bool,
        downloadMbps: Double?,
        uploadMbps: Double?,
        remainingSeconds: Int,
        progress: Double,
        statusText: String
    ) {
        _ = progress
        let down = downloadMbps ?? 0
        let up = uploadMbps ?? 0
        let speedText = String(format: "下载 %.2f Mbps · 上传估算 %.2f Mbps", down, up)
        titleLabel.text = "网络测速"
        statusLabel.text = isTesting ? "\(speedText) · 剩余 \(remainingSeconds)s" : statusText

        if isTesting {
            startButton.configuration?.title = "取消测速"
            startButton.isEnabled = true
            spinner.startAnimating()
        } else {
            startButton.configuration?.title = "开始测速"
            startButton.isEnabled = true
            spinner.stopAnimating()
        }
    }

    @objc private func startTapped() {
        onStartTapped?()
    }
}

private final class CachedVideosManagementViewController: UIViewController {
    private var entries: [VideoDiskCache.Entry]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let notifyHaptic = UINotificationFeedbackGenerator()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    var reloadProvider: (() -> [VideoDiskCache.Entry])?
    var onDeleteEntry: ((VideoDiskCache.Entry) -> Void)?
    var onShareEntry: ((VideoDiskCache.Entry) -> Void)?
    var onEntrySelected: ((VideoDiskCache.Entry) -> UIViewController?)?

    init(entries: [VideoDiskCache.Entry]) {
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0, alpha: 1)
        title = "已缓存视频"

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.tintColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.estimatedRowHeight = 56
        tableView.sectionHeaderTopPadding = 14
        tableView.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 18, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        relativeDateFormatter.unitsStyle = .short
        notifyHaptic.prepare()
        reloadData()
    }

    private func reloadData() {
        entries = (reloadProvider?() ?? entries).sorted { $0.updatedAt > $1.updatedAt }
        tableView.reloadData()
    }

    private func removeEntry(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        onDeleteEntry?(entry)
        notifyHaptic.notificationOccurred(.success)
        reloadData()
    }

    private func detailText(for entry: VideoDiskCache.Entry) -> String {
        let sizeText = VideoDiskCache.formatSize(entry.sizeBytes)
        let updatedDate = Date(timeIntervalSince1970: entry.updatedAt)
        let timeText = relativeDateFormatter.localizedString(for: updatedDate, relativeTo: Date())
        return "\(sizeText) · \(timeText)"
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

extension CachedVideosManagementViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, entries.count)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseID = "CachedVideoManagementCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
        cell.backgroundColor = .clear
        cell.selectionStyle = entries.isEmpty ? .none : .default
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = UIColor(white: 0.72, alpha: 1)
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        cell.accessoryType = .none

        if entries.isEmpty {
            cell.textLabel?.text = "暂无缓存视频"
            cell.detailTextLabel?.text = "可在播放页缓存后在此统一管理"
            cell.accessibilityLabel = "暂无缓存视频"
            return cell
        }

        let entry = entries[indexPath.row]
        cell.textLabel?.text = entry.name
        cell.detailTextLabel?.text = detailText(for: entry)
        cell.accessibilityLabel = "\(entry.name)，\(detailText(for: entry))"
        cell.accessibilityHint = "左滑删除，长按可删除或分享"
        return cell
    }
}

extension CachedVideosManagementViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "本地缓存"
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !entries.isEmpty
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !entries.isEmpty, entries.indices.contains(indexPath.row) else { return nil }
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.removeEntry(at: indexPath.row)
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed
        let config = UISwipeActionsConfiguration(actions: [deleteAction])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !entries.isEmpty, entries.indices.contains(indexPath.row) else { return nil }
        let entry = entries[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let share = UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.onShareEntry?(entry)
            }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.removeEntry(at: indexPath.row)
            }
            return UIMenu(title: "", children: [share, delete])
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !entries.isEmpty, entries.indices.contains(indexPath.row) else { return }
        let entry = entries[indexPath.row]
        if let controller = onEntrySelected?(entry) {
            navigationController?.pushViewController(controller, animated: true)
            return
        }
        let alert = UIAlertController(title: "无法播放", message: "无法解析该缓存条目", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

private final class FavoritesManagementViewController: UIViewController {
    private var records: [FavoriteVideoRecord]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let notifyHaptic = UINotificationFeedbackGenerator()

    var reloadProvider: (() -> [FavoriteVideoRecord])?
    var onFavoriteRemoved: ((String) -> Void)?
    var onFavoriteSelected: ((String) -> Void)?

    init(records: [FavoriteVideoRecord]) {
        self.records = records
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0, alpha: 1)
        title = "收藏管理"

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.tintColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.sectionHeaderTopPadding = 24
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 18, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        notifyHaptic.prepare()
        reloadData()
    }

    private func reloadData() {
        records = reloadProvider?() ?? records
        tableView.reloadData()
    }

    private func removeFavorite(at index: Int) {
        guard records.indices.contains(index) else { return }
        let record = records[index]
        onFavoriteRemoved?(record.id)
        notifyHaptic.notificationOccurred(.success)
        reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

extension FavoritesManagementViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, records.count)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseID = "FavoriteCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
        cell.backgroundColor = .clear
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = UIColor(white: 0.7, alpha: 1)
        cell.selectionStyle = .none

        if records.isEmpty {
            cell.textLabel?.text = "暂无收藏视频"
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .none
            cell.accessibilityLabel = "暂无收藏视频"
            return cell
        }

        let record = records[indexPath.row]
        cell.textLabel?.text = record.title
        cell.detailTextLabel?.text = record.detail
        cell.accessoryType = .none
        cell.accessibilityLabel = record.detail == nil ? record.title : "\(record.title)，\(record.detail!)"
        cell.accessibilityHint = "左滑可取消收藏"
        return cell
    }
}

extension FavoritesManagementViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "已收藏视频"
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !records.isEmpty
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !records.isEmpty else { return nil }
        let deleteAction = UIContextualAction(style: .destructive, title: "取消收藏") { [weak self] _, _, completion in
            self?.removeFavorite(at: indexPath.row)
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !records.isEmpty, records.indices.contains(indexPath.row) else { return }
        let selected = records[indexPath.row]
        onFavoriteSelected?(selected.id)
    }
}
