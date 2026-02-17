import UIKit
import AVFoundation

final class VideoCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseId = "VideoCell"
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024

    private let playerView = PlayerView()
    private let titleLabel = UILabel()
    private let posterView = UIImageView()
    private let controlsContainer = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let progressSlider = UISlider()
    private let floatingStack = UIStackView()
    private let cacheControlStack = UIStackView()
    private let cacheButton = UIButton(type: .system)
    private let cacheSizeLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    private let randomButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let pureModeButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var posterTask: URLSessionDataTask?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var imageGenerator: AVAssetImageGenerator?
    private var displayObserver: NSKeyValueObservation?
    private var isSeeking = false
    private var hasRenderedFirstFrame = false
    private var rotationAngle: CGFloat = 0
    private var isMuted = false
    private var isPureMode = false
    private var currentRemoteVideoURL: URL?
    private var currentVideoName: String?
    private var isCachingVideo = false
    private var cacheInfoToken = UUID()
    private var sizeProbeWorkItem: DispatchWorkItem?
    private var hasRequestedRemoteSize = false
    private var isFavorite = false
    private var currentVideoSizeBytes: Int64?

    var onToggleMute: (() -> Void)?
    var onTogglePureMode: (() -> Void)?
    var onCacheStateChanged: (() -> Void)?
    var onToggleFavorite: ((Bool) -> Void)?
    var onRandomRequested: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        playerView.translatesAutoresizingMaskIntoConstraints = false
        posterView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        floatingStack.translatesAutoresizingMaskIntoConstraints = false
        cacheControlStack.translatesAutoresizingMaskIntoConstraints = false
        cacheButton.translatesAutoresizingMaskIntoConstraints = false
        cacheSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        randomButton.translatesAutoresizingMaskIntoConstraints = false
        rotateButton.translatesAutoresizingMaskIntoConstraints = false
        pureModeButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.translatesAutoresizingMaskIntoConstraints = false

        posterView.contentMode = .scaleAspectFit
        posterView.backgroundColor = .black
        posterView.isHidden = true

        titleLabel.textColor = .white
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.numberOfLines = 2

        controlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        controlsContainer.layer.cornerRadius = 14
        controlsContainer.clipsToBounds = true

        playPauseButton.tintColor = .white
        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.9)
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        progressSlider.thumbTintColor = UIColor.white.withAlphaComponent(0.9)
        progressSlider.addTarget(self, action: #selector(seekTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(seekValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(seekTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        floatingStack.axis = .vertical
        floatingStack.alignment = .center
        floatingStack.distribution = .equalSpacing
        floatingStack.spacing = 14

        cacheControlStack.axis = .vertical
        cacheControlStack.alignment = .center
        cacheControlStack.spacing = 4

        configureFloatingButton(cacheButton, systemName: "arrow.down.circle")
        configureFloatingButton(favoriteButton, systemName: "heart")
        configureFloatingButton(randomButton, systemName: "shuffle")
        configureFloatingButton(rotateButton, systemName: "rotate.right")
        configureFloatingButton(pureModeButton, systemName: "eye.slash")
        configureFloatingButton(muteButton, systemName: "speaker.slash")

        cacheSizeLabel.textColor = UIColor(white: 0.85, alpha: 1)
        cacheSizeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        cacheSizeLabel.textAlignment = .center
        cacheSizeLabel.text = "--"
        cacheSizeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        cacheButton.addTarget(self, action: #selector(cacheTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        randomButton.addTarget(self, action: #selector(randomTapped), for: .touchUpInside)
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        pureModeButton.addTarget(self, action: #selector(pureModeTapped), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        contentView.addSubview(playerView)
        contentView.addSubview(posterView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(controlsContainer)
        contentView.addSubview(floatingStack)

        controlsContainer.addSubview(playPauseButton)
        controlsContainer.addSubview(progressSlider)
        cacheControlStack.addArrangedSubview(cacheButton)
        cacheControlStack.addArrangedSubview(cacheSizeLabel)
        floatingStack.addArrangedSubview(cacheControlStack)
        floatingStack.addArrangedSubview(favoriteButton)
        floatingStack.addArrangedSubview(muteButton)
        floatingStack.addArrangedSubview(pureModeButton)
        floatingStack.addArrangedSubview(rotateButton)
        floatingStack.addArrangedSubview(randomButton)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            posterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            posterView.topAnchor.constraint(equalTo: contentView.topAnchor),
            posterView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -8)
        ])

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            controlsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            controlsContainer.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            controlsContainer.heightAnchor.constraint(equalToConstant: 40),

            playPauseButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 24),
            playPauseButton.heightAnchor.constraint(equalToConstant: 24),

            progressSlider.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 10),
            progressSlider.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -12),
            progressSlider.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor)
        ])

        NSLayoutConstraint.activate([
            floatingStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            floatingStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        contentView.addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopPlayback()
        posterTask?.cancel()
        imageGenerator?.cancelAllCGImageGeneration()
        sizeProbeWorkItem?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopPlayback()
        posterTask?.cancel()
        posterTask = nil
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        displayObserver?.invalidate()
        displayObserver = nil
        posterView.image = nil
        posterView.isHidden = true
        hasRenderedFirstFrame = false
        rotationAngle = 0
        currentRemoteVideoURL = nil
        currentVideoName = nil
        isCachingVideo = false
        cacheInfoToken = UUID()
        sizeProbeWorkItem?.cancel()
        sizeProbeWorkItem = nil
        hasRequestedRemoteSize = false
        cacheSizeLabel.text = "--"
        isFavorite = false
        currentVideoSizeBytes = nil
        updateFavoriteIcon()
        setManualCacheState(cached: false, caching: false)
        applyRotation()
    }

    func configure(item: VideoItem, config: ServerConfig, client: APIClient, preloadCache: PreloadCache, isMuted: Bool, isPureMode: Bool, isFavorite: Bool) {
        stopPlayback()
        posterTask?.cancel()
        posterTask = nil
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil

        titleLabel.text = item.name
        hasRenderedFirstFrame = false
        rotationAngle = 0
        self.isMuted = isMuted
        self.isPureMode = isPureMode
        applyPureMode(isPureMode)
        applyRotation()
        progressSlider.value = 0

        let remoteVideoURL = client.videoURL(for: item, config: config)
        currentRemoteVideoURL = remoteVideoURL
        currentVideoName = item.name
        isCachingVideo = false
        currentVideoSizeBytes = item.sizeBytes
        self.isFavorite = isFavorite
        cacheInfoToken = UUID()
        sizeProbeWorkItem?.cancel()
        sizeProbeWorkItem = nil
        hasRequestedRemoteSize = false
        updateFavoriteIcon()

        var resolvedPlayerItem: AVPlayerItem?
        if let remoteVideoURL, let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
            let localPlayerItem = AVPlayerItem(url: localURL)
            localPlayerItem.preferredForwardBufferDuration = 0.2
            resolvedPlayerItem = localPlayerItem
        } else if let preloaded = preloadCache.item(id: item.id) {
            resolvedPlayerItem = preloaded
        } else if let remoteVideoURL {
            let remoteAsset = AVURLAsset(
                url: remoteVideoURL,
                options: remoteAssetOptions()
            )
            let remotePlayerItem = AVPlayerItem(asset: remoteAsset)
            if isLargeCurrentVideo() {
                remotePlayerItem.preferredForwardBufferDuration = 0.4
                remotePlayerItem.preferredPeakBitRate = 12_000_000
            } else {
                remotePlayerItem.preferredForwardBufferDuration = 1.5
            }
            resolvedPlayerItem = remotePlayerItem
        }
        playerItem = resolvedPlayerItem
        refreshCacheUIForCurrentVideo(fetchRemoteSize: false)

        if let posterURL = client.posterURL(for: item, config: config) {
            posterView.isHidden = false
            posterTask = URLSession.shared.dataTask(with: posterURL) { [weak self] data, _, _ in
                guard let self = self, let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.posterView.image = image
                }
            }
            posterTask?.resume()
        } else if let remoteVideoURL {
            posterView.isHidden = false
            if let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
                generateThumbnail(from: localURL)
            } else if !isLargeCurrentVideo() {
                generateThumbnail(from: remoteVideoURL)
            }
        } else {
            posterView.isHidden = true
        }

        if let playerItem = playerItem {
            let player = AVPlayer(playerItem: playerItem)
            // Start fast for short-form feed; let UI handle occasional rebuffering.
            player.automaticallyWaitsToMinimizeStalling = false
            player.isMuted = isMuted
            player.actionAtItemEnd = .none
            self.player = player
            playerView.player = player
            attachDisplayObserver()
            attachTimeObserver()
            attachLoopObserver()
            updateDuration()
            updatePlayPauseIcon()
            updateMuteIcon()
        }

        if posterView.image == nil, let remoteVideoURL {
            if let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
                generateThumbnail(from: localURL)
            } else if !isLargeCurrentVideo() {
                generateThumbnail(from: remoteVideoURL)
            }
        }
    }

    func startPlayback() {
        if posterView.image != nil && !playerView.playerLayer.isReadyForDisplay {
            posterView.isHidden = false
        }
        player?.playImmediately(atRate: 1.0)
        scheduleDeferredSizeProbeIfNeeded()
        updatePlayPauseIcon()
    }

    func stopPlayback() {
        player?.pause()
        updatePlayPauseIcon()
        detachTimeObserver()
        detachLoopObserver()
        displayObserver?.invalidate()
        displayObserver = nil
        playerView.player = nil
        player = nil
        playerItem = nil
    }

    func handleMemoryWarning(isActiveCell: Bool) {
        sizeProbeWorkItem?.cancel()
        sizeProbeWorkItem = nil
        posterTask?.cancel()
        posterTask = nil
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        hasRequestedRemoteSize = false

        if !isActiveCell {
            stopPlayback()
            posterView.image = nil
            posterView.isHidden = true
        }
    }

    func applyMute(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        updateMuteIcon()
    }

    func applyPureMode(_ pure: Bool) {
        isPureMode = pure
        titleLabel.isHidden = pure
        controlsContainer.isHidden = pure
        floatingStack.alpha = pure ? 0.7 : 1.0
        let iconName = pure ? "eye" : "eye.slash"
        pureModeButton.setImage(UIImage(systemName: iconName), for: .normal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyRotation()
    }
}

extension VideoCell {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchedView = touch.view
        if touchedView is UIControl { return false }
        if let touchedView = touchedView, touchedView.isDescendant(of: controlsContainer) {
            return false
        }
        if let touchedView = touchedView, touchedView.isDescendant(of: floatingStack) {
            return false
        }
        return true
    }
}

private extension VideoCell {
    func configureFloatingButton(_ button: UIButton, systemName: String) {
        button.tintColor = .white
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    @objc func handleTap() {
        togglePlayPause()
    }

    @objc func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        updatePlayPauseIcon()
    }

    func updatePlayPauseIcon() {
        let isPlaying = player?.timeControlStatus == .playing
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    func updateMuteIcon() {
        let imageName = isMuted ? "speaker.slash" : "speaker.wave.2"
        muteButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    func attachTimeObserver() {
        guard timeObserverToken == nil, let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.updateDuration()
            if !self.isSeeking {
                self.progressSlider.value = Float(time.seconds)
            }
            self.updatePlayPauseIcon()
        }
    }

    func detachTimeObserver() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
    }

    func updateDuration() {
        guard let duration = playerItem?.duration, duration.isNumeric else { return }
        let seconds = duration.seconds
        if seconds > 0 {
            progressSlider.maximumValue = Float(seconds)
        }
    }

    @objc func seekTouchDown() {
        isSeeking = true
    }

    @objc func seekValueChanged() {
        guard let player = player else { return }
        let time = CMTime(seconds: Double(progressSlider.value), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @objc func seekTouchUp() {
        isSeeking = false
    }

    func attachLoopObserver() {
        guard endObserver == nil, let item = playerItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            self.player?.play()
        }
    }

    func detachLoopObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
    }

    func attachDisplayObserver() {
        displayObserver?.invalidate()
        displayObserver = playerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self = self else { return }
            if layer.isReadyForDisplay {
                self.posterView.isHidden = true
                self.hasRenderedFirstFrame = true
            } else if self.posterView.image != nil {
                self.posterView.isHidden = false
            }
        }
    }

    @objc func rotateTapped() {
        rotationAngle += CGFloat.pi / 2
        if rotationAngle >= CGFloat.pi * 2 {
            rotationAngle = 0
        }
        applyRotation()
    }

    func applyRotation() {
        let normalized = rotationAngle.truncatingRemainder(dividingBy: CGFloat.pi * 2)
        let isRotated = abs(normalized - CGFloat.pi / 2) < 0.01 || abs(normalized - CGFloat.pi * 1.5) < 0.01
        let bounds = contentView.bounds
        var scale: CGFloat = 1
        if isRotated, bounds.width > 0, bounds.height > 0 {
            scale = min(bounds.width / bounds.height, bounds.height / bounds.width)
        }
        let transform = CGAffineTransform(rotationAngle: normalized).scaledBy(x: scale, y: scale)
        playerView.transform = transform
        posterView.transform = transform
        playerView.playerLayer.videoGravity = .resizeAspect
    }

    @objc func pureModeTapped() {
        onTogglePureMode?()
    }

    @objc func muteTapped() {
        onToggleMute?()
    }

    @objc func favoriteTapped() {
        isFavorite.toggle()
        updateFavoriteIcon()
        onToggleFavorite?(isFavorite)
    }

    @objc func randomTapped() {
        onRandomRequested?()
    }

    @objc func cacheTapped() {
        guard let remoteURL = currentRemoteVideoURL, let name = currentVideoName else { return }
        if VideoDiskCache.shared.cachedFileURL(for: remoteURL) != nil {
            refreshCacheUIForCurrentVideo(fetchRemoteSize: false)
            return
        }
        guard !isCachingVideo else { return }

        isCachingVideo = true
        cacheSizeLabel.text = "缓存中"
        setManualCacheState(cached: false, caching: true)
        VideoDiskCache.shared.cacheVideo(name: name, remoteURL: remoteURL) { [weak self] result in
            guard let self = self, self.currentRemoteVideoURL == remoteURL else { return }
            self.isCachingVideo = false
            switch result {
            case .success(let entry):
                self.cacheSizeLabel.text = VideoDiskCache.formatSize(entry.sizeBytes)
                self.setManualCacheState(cached: true, caching: false)
                self.onCacheStateChanged?()
            case .failure:
                self.refreshCacheUIForCurrentVideo(fetchRemoteSize: true)
            }
        }
    }

    func refreshCacheUIForCurrentVideo(fetchRemoteSize: Bool) {
        guard let remoteURL = currentRemoteVideoURL else {
            cacheSizeLabel.text = "--"
            setManualCacheState(cached: false, caching: false)
            return
        }
        if let bytes = VideoDiskCache.shared.cachedSizeBytes(for: remoteURL), bytes > 0 {
            cacheSizeLabel.text = VideoDiskCache.formatSize(bytes)
            setManualCacheState(cached: true, caching: false)
            return
        }
        if isCachingVideo {
            cacheSizeLabel.text = "缓存中"
            setManualCacheState(cached: false, caching: true)
            return
        }

        cacheSizeLabel.text = "--"
        setManualCacheState(cached: false, caching: false)
        guard fetchRemoteSize else { return }

        hasRequestedRemoteSize = true
        let token = UUID()
        cacheInfoToken = token
        VideoDiskCache.shared.fetchRemoteSize(for: remoteURL) { [weak self] bytes in
            guard
                let self = self,
                self.cacheInfoToken == token,
                self.currentRemoteVideoURL == remoteURL
            else { return }
            self.cacheSizeLabel.text = bytes == nil ? "未知" : VideoDiskCache.formatSize(bytes)
        }
    }

    func scheduleDeferredSizeProbeIfNeeded() {
        guard !hasRequestedRemoteSize, !isCachingVideo else { return }
        guard let remoteURL = currentRemoteVideoURL else { return }
        if VideoDiskCache.shared.cachedFileURL(for: remoteURL) != nil { return }
        sizeProbeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshCacheUIForCurrentVideo(fetchRemoteSize: true)
        }
        sizeProbeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func setManualCacheState(cached: Bool, caching: Bool) {
        if caching {
            cacheButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.circle.fill"), for: .normal)
            cacheButton.tintColor = UIColor.systemYellow
        } else if cached {
            cacheButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            cacheButton.tintColor = UIColor.systemGreen
        } else {
            cacheButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            cacheButton.tintColor = .white
        }
    }

    func updateFavoriteIcon() {
        let iconName = isFavorite ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: iconName), for: .normal)
        favoriteButton.tintColor = isFavorite ? UIColor.systemPink : UIColor.white
    }

    func generateThumbnail(from url: URL) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        imageGenerator = generator

        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, _, _ in
            guard let self = self, let cgImage = cgImage else { return }
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                if self.posterView.image == nil {
                    self.posterView.image = image
                    self.posterView.isHidden = false
                }
            }
        }
    }

    func isLargeCurrentVideo() -> Bool {
        guard let size = currentVideoSizeBytes else { return false }
        return size >= Self.largeVideoThresholdBytes
    }

    func remoteAssetOptions() -> [String: Any] {
        return [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            AVURLAssetAllowsExpensiveNetworkAccessKey: true,
            AVURLAssetAllowsCellularAccessKey: true
        ]
    }
}
