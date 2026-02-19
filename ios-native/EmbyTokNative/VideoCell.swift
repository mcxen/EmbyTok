import UIKit
import AVFoundation

final class VideoCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseId = "VideoCell"
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024
    private static let floatingButtonSize: CGFloat = 31
    private static let floatingIconPointSize: CGFloat = 12
    private static let floatingStackVerticalOffset: CGFloat = 56
    private static let overlayAutoHideDelay: TimeInterval = 8

    private let playerView = PlayerView()
    private let titleLabel = UILabel()
    private let posterView = UIImageView()
    private let controlsContainer = UIView()
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
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
    private let muteHintView = UIView()
    private let muteHintLabel = UILabel()
    private let seekHintView = UIView()
    private let seekHintLabel = UILabel()

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
    private var playbackEndAction: PlaybackEndAction = .loopCurrent
    private var timeDisplayMode: TimeDisplayMode = .elapsed
    private var currentRemoteVideoURL: URL?
    private var currentVideoName: String?
    private var isCachingVideo = false
    private var cacheInfoToken = UUID()
    private var sizeProbeWorkItem: DispatchWorkItem?
    private var hasRequestedRemoteSize = false
    private var shouldResumeAfterSeek = false
    private var isFavorite = false
    private var currentVideoSizeBytes: Int64?
    private var currentVideoSize: CGSize?
    private var floatingStackCenterYConstraint: NSLayoutConstraint?
    private var pureModeBottomConstraint: NSLayoutConstraint?
    private var overlayHideWorkItem: DispatchWorkItem?
    private var muteHintWorkItem: DispatchWorkItem?
    private var seekHintWorkItem: DispatchWorkItem?
    private var playbackToken = UUID()
    private let muteFeedback = UIImpactFeedbackGenerator(style: .light)
    private let pureModeFeedback = UIImpactFeedbackGenerator(style: .light)
    private let sideButtonFeedback = UIImpactFeedbackGenerator(style: .light)
    private var pinchGesture: UIPinchGestureRecognizer?
    private var twoFingerTapGesture: UITapGestureRecognizer?
    private var twoFingerDoubleTapGesture: UITapGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var panStartTime: Double = 0
    private var panShouldResumeAfterSeek = false

    var onToggleMute: (() -> Void)?
    var onTogglePureMode: (() -> Void)?
    var onCacheStateChanged: (() -> Void)?
    var onToggleFavorite: ((Bool) -> Void)?
    var onRandomRequested: (() -> Void)?
    var onPlaybackEnded: (() -> Void)?

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

        currentTimeLabel.textColor = UIColor(white: 0.92, alpha: 1)
        currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        currentTimeLabel.textAlignment = .left
        currentTimeLabel.text = "00:00"
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false

        totalTimeLabel.textColor = UIColor(white: 0.92, alpha: 1)
        totalTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        totalTimeLabel.textAlignment = .right
        totalTimeLabel.text = "00:00"
        totalTimeLabel.translatesAutoresizingMaskIntoConstraints = false

        playPauseButton.tintColor = .white
        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        playPauseButton.isHidden = true

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
        floatingStack.spacing = 10

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
        controlsContainer.addSubview(currentTimeLabel)
        controlsContainer.addSubview(totalTimeLabel)
        controlsContainer.addSubview(progressSlider)
        cacheControlStack.addArrangedSubview(cacheButton)
        cacheControlStack.addArrangedSubview(cacheSizeLabel)
        floatingStack.addArrangedSubview(cacheControlStack)
        floatingStack.addArrangedSubview(favoriteButton)
        floatingStack.addArrangedSubview(muteButton)
        floatingStack.addArrangedSubview(rotateButton)
        floatingStack.addArrangedSubview(randomButton)
        contentView.addSubview(pureModeButton)
        contentView.addSubview(muteHintView)
        contentView.addSubview(seekHintView)

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
            controlsContainer.heightAnchor.constraint(equalToConstant: 44),

            playPauseButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 0),
            playPauseButton.heightAnchor.constraint(equalToConstant: 0),

            currentTimeLabel.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            currentTimeLabel.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 42),

            totalTimeLabel.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -10),
            totalTimeLabel.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            totalTimeLabel.widthAnchor.constraint(equalToConstant: 42),

            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            progressSlider.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -8),
            progressSlider.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor)
        ])

        floatingStackCenterYConstraint = floatingStack.centerYAnchor.constraint(
            equalTo: contentView.centerYAnchor,
            constant: Self.floatingStackVerticalOffset
        )
        NSLayoutConstraint.activate([
            floatingStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            floatingStackCenterYConstraint!
        ])

        pureModeBottomConstraint = pureModeButton.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        NSLayoutConstraint.activate([
            pureModeButton.trailingAnchor.constraint(equalTo: floatingStack.trailingAnchor),
            pureModeBottomConstraint!
        ])

        muteHintView.translatesAutoresizingMaskIntoConstraints = false
        muteHintView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        muteHintView.layer.cornerRadius = 10
        muteHintView.isHidden = true
        muteHintView.alpha = 0

        muteHintLabel.translatesAutoresizingMaskIntoConstraints = false
        muteHintLabel.textColor = .white
        muteHintLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        muteHintLabel.numberOfLines = 1
        muteHintView.addSubview(muteHintLabel)

        NSLayoutConstraint.activate([
            muteHintLabel.leadingAnchor.constraint(equalTo: muteHintView.leadingAnchor, constant: 8),
            muteHintLabel.trailingAnchor.constraint(equalTo: muteHintView.trailingAnchor, constant: -8),
            muteHintLabel.topAnchor.constraint(equalTo: muteHintView.topAnchor, constant: 4),
            muteHintLabel.bottomAnchor.constraint(equalTo: muteHintView.bottomAnchor, constant: -4),

            muteHintView.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor),
            muteHintView.trailingAnchor.constraint(equalTo: muteButton.leadingAnchor, constant: -8),
            muteHintView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12)
        ])

        seekHintView.translatesAutoresizingMaskIntoConstraints = false
        seekHintView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        seekHintView.layer.cornerRadius = 12
        seekHintView.isHidden = true
        seekHintView.alpha = 0

        seekHintLabel.translatesAutoresizingMaskIntoConstraints = false
        seekHintLabel.textColor = .white
        seekHintLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        seekHintLabel.numberOfLines = 1
        seekHintView.addSubview(seekHintLabel)

        NSLayoutConstraint.activate([
            seekHintLabel.leadingAnchor.constraint(equalTo: seekHintView.leadingAnchor, constant: 10),
            seekHintLabel.trailingAnchor.constraint(equalTo: seekHintView.trailingAnchor, constant: -10),
            seekHintLabel.topAnchor.constraint(equalTo: seekHintView.topAnchor, constant: 6),
            seekHintLabel.bottomAnchor.constraint(equalTo: seekHintView.bottomAnchor, constant: -6),

            seekHintView.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            seekHintView.topAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: 8),
            seekHintView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12),
            seekHintView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)
        ])

        controlsContainer.alpha = 0
        controlsContainer.isHidden = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self

        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.cancelsTouchesInView = false
        twoFingerDoubleTap.delegate = self

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.delegate = self
        twoFingerTap.require(toFail: twoFingerDoubleTap)
        tapGesture.require(toFail: twoFingerTap)

        self.twoFingerTapGesture = twoFingerTap
        self.twoFingerDoubleTapGesture = twoFingerDoubleTap

        contentView.addGestureRecognizer(tapGesture)
        contentView.addGestureRecognizer(twoFingerTap)
        contentView.addGestureRecognizer(twoFingerDoubleTap)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinchGesture.cancelsTouchesInView = false
        pinchGesture.delegate = self
        self.pinchGesture = pinchGesture
        contentView.addGestureRecognizer(pinchGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSeekPan))
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        self.panGesture = panGesture
        contentView.addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopPlayback()
        posterTask?.cancel()
        imageGenerator?.cancelAllCGImageGeneration()
        sizeProbeWorkItem?.cancel()
        overlayHideWorkItem?.cancel()
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
        overlayHideWorkItem?.cancel()
        overlayHideWorkItem = nil
        hasRequestedRemoteSize = false
        shouldResumeAfterSeek = false
        playbackToken = UUID()
        onPlaybackEnded = nil
        controlsContainer.alpha = 0
        controlsContainer.isHidden = true
        cacheSizeLabel.text = "--"
        isFavorite = false
        currentVideoSizeBytes = nil
        currentVideoSize = nil
        timeDisplayMode = .elapsed
        muteHintWorkItem?.cancel()
        muteHintWorkItem = nil
        muteHintView.alpha = 0
        muteHintView.isHidden = true
        seekHintWorkItem?.cancel()
        seekHintWorkItem = nil
        seekHintView.alpha = 0
        seekHintView.isHidden = true
        updateFavoriteIcon()
        setManualCacheState(cached: false, caching: false)
        applyRotation()
    }

    func configure(
        item: VideoItem,
        config: ServerConfig,
        client: APIClient,
        preloadCache: PreloadCache,
        isMuted: Bool,
        isPureMode: Bool,
        isFavorite: Bool,
        playbackEndAction: PlaybackEndAction
    ) {
        stopPlayback()
        posterTask?.cancel()
        posterTask = nil
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        playbackToken = UUID()
        let currentPlaybackToken = playbackToken

        titleLabel.text = item.name
        hasRenderedFirstFrame = false
        rotationAngle = 0
        self.isMuted = isMuted
        self.isPureMode = isPureMode
        self.playbackEndAction = playbackEndAction
        applyPureMode(isPureMode)
        applyRotation()
        progressSlider.value = 0

        let remoteVideoURL = client.videoURL(for: item, config: config)
        currentRemoteVideoURL = remoteVideoURL
        currentVideoName = item.name
        isCachingVideo = false
        currentVideoSizeBytes = item.sizeBytes
        if let width = item.width, let height = item.height, width > 0, height > 0 {
            currentVideoSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        } else {
            currentVideoSize = nil
        }
        self.isFavorite = isFavorite
        cacheInfoToken = UUID()
        sizeProbeWorkItem?.cancel()
        sizeProbeWorkItem = nil
        overlayHideWorkItem?.cancel()
        overlayHideWorkItem = nil
        hasRequestedRemoteSize = false
        shouldResumeAfterSeek = false
        updateFavoriteIcon()
        updateTimeLabels(
            current: 0,
            duration: item.durationSeconds ?? 0
        )

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
                    guard self.playbackToken == currentPlaybackToken else { return }
                    self.posterView.image = image
                }
            }
            posterTask?.resume()
        } else if let remoteVideoURL {
            posterView.isHidden = false
            if let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
                generateThumbnail(from: localURL, token: currentPlaybackToken)
            } else if !isLargeCurrentVideo() {
                generateThumbnail(from: remoteVideoURL, token: currentPlaybackToken)
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
            updatePresentationSizeIfNeeded()
            updatePlayPauseIcon()
            updateMuteIcon()
        }

        if isPureMode {
            hidePlaybackOverlay(animated: false)
        } else {
            showPlaybackOverlay(animated: false, autoHide: false)
        }

        if posterView.image == nil, let remoteVideoURL {
            if let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
                generateThumbnail(from: localURL, token: currentPlaybackToken)
            } else if !isLargeCurrentVideo() {
                generateThumbnail(from: remoteVideoURL, token: currentPlaybackToken)
            }
        }
    }

    func startPlayback() {
        if !hasRenderedFirstFrame, posterView.image != nil && !playerView.playerLayer.isReadyForDisplay {
            posterView.isHidden = false
        }
        player?.playImmediately(atRate: 1.0)
        scheduleDeferredSizeProbeIfNeeded()
        updatePlayPauseIcon()
        if isPureMode {
            hidePlaybackOverlay(animated: false)
        } else {
            showPlaybackOverlay(animated: false, autoHide: false)
        }
    }

    func stopPlayback() {
        player?.pause()
        updatePlayPauseIcon()
        detachTimeObserver()
        detachLoopObserver()
        overlayHideWorkItem?.cancel()
        overlayHideWorkItem = nil
        displayObserver?.invalidate()
        displayObserver = nil
        playerView.player = nil
        player = nil
        playerItem = nil
        shouldResumeAfterSeek = false
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
        if pure {
            hidePlaybackOverlay(animated: false)
            hideMuteHint(animated: false)
        } else {
            showPlaybackOverlay(animated: false, autoHide: false)
        }
        hideSeekHint(animated: false)
        cacheControlStack.isHidden = pure
        favoriteButton.isHidden = pure
        muteButton.isHidden = pure
        rotateButton.isHidden = pure
        randomButton.isHidden = pure
        floatingStack.isHidden = pure
        floatingStack.alpha = pure ? 0 : 1.0
        let iconName = pure ? "eye" : "eye.slash"
        pureModeButton.setImage(UIImage(systemName: iconName), for: .normal)
        pureModeBottomConstraint?.constant = pure ? -40 : -44
        refreshGestureAvailability()
    }

    func applyTimeDisplayMode(_ mode: TimeDisplayMode) {
        timeDisplayMode = mode
        updateTimeLabels(current: nil, duration: currentDurationSeconds())
    }

    func refreshGestureAvailability() {
        let pinchEnabled = GestureSettings.isPinchPureModeEnabled
        pinchGesture?.isEnabled = pinchEnabled

        let twoFingerEnabled = GestureSettings.isTwoFingerMuteEnabled
        twoFingerTapGesture?.isEnabled = twoFingerEnabled
        twoFingerDoubleTapGesture?.isEnabled = twoFingerEnabled

        let swipeEnabled = GestureSettings.isPureModeSwipeSeekEnabled && isPureMode
        panGesture?.isEnabled = swipeEnabled
    }

    func applyFavoriteState(_ favorite: Bool) {
        isFavorite = favorite
        updateFavoriteIcon()
    }

    func refreshCacheBadge() {
        refreshCacheUIForCurrentVideo(fetchRemoteSize: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyRotation()
    }
}

extension VideoCell {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPinchGestureRecognizer {
            return true
        }
        if let tap = gestureRecognizer as? UITapGestureRecognizer, tap.numberOfTouchesRequired == 2 {
            return true
        }
        if gestureRecognizer is UIPanGestureRecognizer {
            return true
        }
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

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            guard GestureSettings.isPureModeSwipeSeekEnabled, isPureMode else { return false }
            let velocity = pan.velocity(in: contentView)
            return abs(velocity.x) > abs(velocity.y)
        }
        return true
    }
}

private extension VideoCell {
    func configureFloatingButton(_ button: UIButton, systemName: String) {
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.floatingIconPointSize,
            weight: .semibold,
            scale: .medium
        )
        button.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
        button.tintColor = .white
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = Self.floatingButtonSize * 0.5
        button.clipsToBounds = true
        button.widthAnchor.constraint(equalToConstant: Self.floatingButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.floatingButtonSize).isActive = true
    }

    @objc func handleTap() {
        togglePlayPause()
        showPlaybackOverlay(animated: true, autoHide: isPureMode)
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
                self.updateTimeLabels(current: time.seconds, duration: self.currentDurationSeconds())
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
            updateTimeLabels(current: nil, duration: seconds)
        }
    }

    @objc func seekTouchDown() {
        let status = player?.timeControlStatus
        shouldResumeAfterSeek = (player?.rate ?? 0) > 0
            || status == .playing
            || status == .waitingToPlayAtSpecifiedRate
        isSeeking = true
        showPlaybackOverlay(animated: true, autoHide: isPureMode)
    }

    @objc func seekValueChanged() {
        guard let player = player else { return }
        let time = CMTime(seconds: Double(progressSlider.value), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateTimeLabels(current: time.seconds, duration: currentDurationSeconds())
    }

    @objc func seekTouchUp() {
        guard let player = player else {
            isSeeking = false
            shouldResumeAfterSeek = false
            return
        }

        let time = CMTime(seconds: Double(progressSlider.value), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.isSeeking = false
            if self.shouldResumeAfterSeek {
                player.playImmediately(atRate: 1.0)
                self.updatePlayPauseIcon()
            }
            self.shouldResumeAfterSeek = false
            self.showPlaybackOverlay(animated: true, autoHide: self.isPureMode)
        }
    }

    func showPlaybackOverlay(animated: Bool, autoHide: Bool) {
        overlayHideWorkItem?.cancel()
        overlayHideWorkItem = nil

        if controlsContainer.isHidden || controlsContainer.alpha < 1 {
            controlsContainer.isHidden = false
            if animated {
                controlsContainer.alpha = 0
                UIView.animate(withDuration: 0.2) {
                    self.controlsContainer.alpha = 1
                }
            } else {
                controlsContainer.alpha = 1
            }
        }

        if autoHide {
            schedulePlaybackOverlayHide()
        }
    }

    func hidePlaybackOverlay(animated: Bool) {
        overlayHideWorkItem?.cancel()
        overlayHideWorkItem = nil

        guard !controlsContainer.isHidden else { return }
        if animated {
            UIView.animate(withDuration: 0.2, animations: {
                self.controlsContainer.alpha = 0
            }, completion: { _ in
                self.controlsContainer.isHidden = true
            })
        } else {
            controlsContainer.alpha = 0
            controlsContainer.isHidden = true
        }
    }

    func schedulePlaybackOverlayHide() {
        overlayHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hidePlaybackOverlay(animated: true)
        }
        overlayHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.overlayAutoHideDelay, execute: work)
    }

    func formattedPlaybackTime(_ value: Double) -> String {
        guard value.isFinite && value >= 0 else { return "00:00" }
        let totalSeconds = Int(value.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func currentDurationSeconds() -> Double {
        let duration = playerItem?.duration.seconds ?? Double(progressSlider.maximumValue)
        guard duration.isFinite && duration > 0 else { return 0 }
        return duration
    }

    private func updateTimeLabels(current: Double?, duration: Double?) {
        let durationSeconds = normalizeDurationSeconds(duration ?? currentDurationSeconds())
        let currentSeconds = normalizeCurrentSeconds(current ?? player?.currentTime().seconds ?? Double(progressSlider.value), duration: durationSeconds)
        currentTimeLabel.text = formattedCurrentTimeText(current: currentSeconds, duration: durationSeconds)
        totalTimeLabel.text = durationSeconds > 0 ? formattedPlaybackTime(durationSeconds) : "00:00"
    }

    private func normalizeDurationSeconds(_ duration: Double) -> Double {
        guard duration.isFinite && duration > 0 else { return 0 }
        return duration
    }

    private func normalizeCurrentSeconds(_ current: Double, duration: Double) -> Double {
        let safeCurrent = max(0, current.isFinite ? current : 0)
        guard duration > 0 else { return safeCurrent }
        return min(safeCurrent, duration)
    }

    private func formattedCurrentTimeText(current: Double, duration: Double) -> String {
        switch timeDisplayMode {
        case .elapsed:
            return formattedPlaybackTime(current)
        case .remaining:
            guard duration > 0 else { return formattedPlaybackTime(current) }
            let remaining = max(0, duration - current)
            return "-\(formattedPlaybackTime(remaining))"
        }
    }

    private func formattedSeekHintText(current: Double, duration: Double) -> String {
        let currentText: String
        switch timeDisplayMode {
        case .elapsed:
            currentText = formattedPlaybackTime(current)
        case .remaining:
            guard duration > 0 else { return formattedPlaybackTime(current) }
            let remaining = max(0, duration - current)
            currentText = "-\(formattedPlaybackTime(remaining))"
        }
        guard duration > 0 else { return currentText }
        return "\(currentText) / \(formattedPlaybackTime(duration))"
    }

    func attachLoopObserver() {
        guard endObserver == nil, let item = playerItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            switch self.playbackEndAction {
            case .loopCurrent:
                self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                self.player?.play()
            case .playNext:
                self.onPlaybackEnded?()
            }
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
                self.updatePresentationSizeIfNeeded()
            } else if !self.hasRenderedFirstFrame, self.posterView.image != nil {
                self.posterView.isHidden = false
            }
        }
    }

    @objc func rotateTapped() {
        sideButtonFeedback.impactOccurred()
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
            let videoSize = currentVideoSize ?? playerItem?.presentationSize ?? bounds.size
            let fitted = aspectFitSize(videoSize, in: bounds.size)
            if fitted.width > 0, fitted.height > 0 {
                let rotatedSize = CGSize(width: fitted.height, height: fitted.width)
                scale = min(bounds.width / rotatedSize.width, bounds.height / rotatedSize.height)
            } else {
                let ratio = bounds.width / bounds.height
                scale = min(ratio, 1 / ratio)
            }
        }
        let transform = CGAffineTransform(rotationAngle: normalized).scaledBy(x: scale, y: scale)
        playerView.transform = transform
        posterView.transform = transform
        playerView.playerLayer.videoGravity = .resizeAspect
    }

    private func aspectFitSize(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let widthRatio = bounds.width / size.width
        let heightRatio = bounds.height / size.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func updatePresentationSizeIfNeeded() {
        guard let size = playerItem?.presentationSize, size.width > 0, size.height > 0 else { return }
        let newSize = CGSize(width: size.width, height: size.height)
        if currentVideoSize == nil || currentVideoSize != newSize {
            currentVideoSize = newSize
            applyRotation()
        }
    }

    @objc func pureModeTapped() {
        sideButtonFeedback.impactOccurred()
        onTogglePureMode?()
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard GestureSettings.isTwoFingerMuteEnabled else { return }
        let nextMuted = !isMuted
        muteFeedback.impactOccurred()
        onToggleMute?()
        showMuteHint(isMuted: nextMuted)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard GestureSettings.isPinchPureModeEnabled else { return }
        switch gesture.state {
        case .began:
            pureModeFeedback.prepare()
        case .ended, .cancelled, .failed:
            let scale = gesture.scale
            if scale >= 1.1, !isPureMode {
                pureModeFeedback.impactOccurred()
                onTogglePureMode?()
            } else if scale <= 0.9, isPureMode {
                pureModeFeedback.impactOccurred()
                onTogglePureMode?()
            }
        default:
            break
        }
    }

    @objc private func handleSeekPan(_ gesture: UIPanGestureRecognizer) {
        guard GestureSettings.isPureModeSwipeSeekEnabled, isPureMode else { return }
        guard let player = player, let item = playerItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }

        switch gesture.state {
        case .began:
            panStartTime = normalizeCurrentSeconds(player.currentTime().seconds, duration: duration)
            let status = player.timeControlStatus
            panShouldResumeAfterSeek = (player.rate > 0) || status == .playing || status == .waitingToPlayAtSpecifiedRate
            isSeeking = true
            showPlaybackOverlay(animated: true, autoHide: false)
        case .changed:
            let translation = gesture.translation(in: contentView).x
            let stepSeconds = Double(GestureSettings.swipeSeekStepSeconds)
            let delta = Double(translation / 100.0) * stepSeconds
            let target = min(max(0, panStartTime + delta), duration)
            seekToSeconds(target, updatePlayer: true)
        case .ended, .cancelled, .failed:
            isSeeking = false
            if panShouldResumeAfterSeek {
                player.playImmediately(atRate: 1.0)
                updatePlayPauseIcon()
            }
            panShouldResumeAfterSeek = false
            showPlaybackOverlay(animated: true, autoHide: isPureMode)
        default:
            break
        }
    }

    private func seekToSeconds(_ seconds: Double, updatePlayer: Bool) {
        guard let player = player else { return }
        let clamped = max(0, seconds)
        if updatePlayer {
            let time = CMTime(seconds: clamped, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        progressSlider.value = Float(clamped)
        updateTimeLabels(current: clamped, duration: currentDurationSeconds())
        showSeekHint(current: clamped, duration: currentDurationSeconds())
    }

    private func showMuteHint(isMuted: Bool) {
        muteHintWorkItem?.cancel()
        muteHintLabel.text = isMuted ? "已静音" : "已开启声音"
        muteHintView.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.muteHintView.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hideMuteHint(animated: true)
        }
        muteHintWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func hideMuteHint(animated: Bool) {
        muteHintWorkItem?.cancel()
        muteHintWorkItem = nil
        let changes = {
            self.muteHintView.alpha = 0
        }
        let completion: (Bool) -> Void = { _ in
            self.muteHintView.isHidden = true
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    private func showSeekHint(current: Double, duration: Double) {
        seekHintWorkItem?.cancel()
        let clampedDuration = duration.isFinite && duration > 0 ? duration : 0
        let clampedCurrent = max(0, current.isFinite ? current : 0)
        seekHintLabel.text = formattedSeekHintText(current: clampedCurrent, duration: clampedDuration)
        seekHintView.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.seekHintView.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hideSeekHint(animated: true)
        }
        seekHintWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func hideSeekHint(animated: Bool) {
        seekHintWorkItem?.cancel()
        seekHintWorkItem = nil
        let changes = {
            self.seekHintView.alpha = 0
        }
        let completion: (Bool) -> Void = { _ in
            self.seekHintView.isHidden = true
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    @objc func muteTapped() {
        sideButtonFeedback.impactOccurred()
        onToggleMute?()
    }

    @objc func favoriteTapped() {
        sideButtonFeedback.impactOccurred()
        isFavorite.toggle()
        updateFavoriteIcon()
        onToggleFavorite?(isFavorite)
    }

    @objc func randomTapped() {
        sideButtonFeedback.impactOccurred()
        onRandomRequested?()
    }

    @objc func cacheTapped() {
        sideButtonFeedback.impactOccurred()
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

    func generateThumbnail(from url: URL, token: UUID) {
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
                guard self.playbackToken == token else { return }
                guard !self.hasRenderedFirstFrame, !self.playerView.playerLayer.isReadyForDisplay else { return }
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
