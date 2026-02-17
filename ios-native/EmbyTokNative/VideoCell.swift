import UIKit
import AVFoundation

final class VideoCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseId = "VideoCell"

    private let playerView = PlayerView()
    private let titleLabel = UILabel()
    private let posterView = UIImageView()
    private let controlsContainer = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let progressSlider = UISlider()

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var posterTask: URLSessionDataTask?
    private var timeObserverToken: Any?
    private var isSeeking = false
    private var hasRenderedFirstFrame = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        playerView.translatesAutoresizingMaskIntoConstraints = false
        posterView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.translatesAutoresizingMaskIntoConstraints = false

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

        contentView.addSubview(playerView)
        contentView.addSubview(posterView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(controlsContainer)

        controlsContainer.addSubview(playPauseButton)
        controlsContainer.addSubview(progressSlider)

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

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        contentView.addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopPlayback()
        posterTask?.cancel()
        posterTask = nil
        posterView.image = nil
        posterView.isHidden = true
        hasRenderedFirstFrame = false
    }

    func configure(item: VideoItem, config: ServerConfig, client: APIClient, preloadCache: PreloadCache) {
        titleLabel.text = item.name
        hasRenderedFirstFrame = false
        if let preloaded = preloadCache.take(id: item.id) {
            playerItem = preloaded
        } else if let url = client.videoURL(for: item, config: config) {
            playerItem = AVPlayerItem(url: url)
            playerItem?.preferredForwardBufferDuration = 4
        }

        if let posterURL = client.posterURL(for: item, config: config) {
            posterView.isHidden = false
            posterTask = URLSession.shared.dataTask(with: posterURL) { [weak self] data, _, _ in
                guard let self = self, let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.posterView.image = image
                }
            }
            posterTask?.resume()
        } else {
            posterView.isHidden = true
        }

        if let playerItem = playerItem {
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            playerView.player = player
            attachTimeObserver()
            updateDuration()
            updatePlayPauseIcon()
        }
    }

    func startPlayback() {
        if posterView.image != nil {
            posterView.isHidden = false
        }
        player?.play()
        updatePlayPauseIcon()
    }

    func stopPlayback() {
        player?.pause()
        updatePlayPauseIcon()
        detachTimeObserver()
        playerView.player = nil
        player = nil
        playerItem = nil
    }
}

extension VideoCell {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchedView = touch.view
        if touchedView is UIControl { return false }
        if let touchedView = touchedView, touchedView.isDescendant(of: controlsContainer) {
            return false
        }
        return true
    }
}

private extension VideoCell {
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

    func attachTimeObserver() {
        guard timeObserverToken == nil, let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.updateDuration()
            if !self.isSeeking {
                self.progressSlider.value = Float(time.seconds)
            }
            if !self.hasRenderedFirstFrame, time.seconds > 0.05 {
                self.hasRenderedFirstFrame = true
                self.posterView.isHidden = true
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
}
