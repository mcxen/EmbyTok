import AVFoundation
import UIKit

final class VideoGridCell: UICollectionViewCell {
    static let reuseId = "VideoGridCell"
    private static let largeVideoThresholdBytes: Int64 = 700 * 1024 * 1024

    enum LayoutStyle {
        case grid
        case list
    }

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let titleBackgroundView = UIView()
    private var posterTask: URLSessionDataTask?
    private var imageGenerator: AVAssetImageGenerator?
    private var representedID: String?
    private var activeStyle: LayoutStyle?
    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)

        titleBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.numberOfLines = 2

        metaLabel.textColor = UIColor(white: 0.8, alpha: 1)
        metaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        metaLabel.numberOfLines = 1

        contentView.addSubview(imageView)
        contentView.addSubview(titleBackgroundView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(metaLabel)

        gridConstraints = [
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleBackgroundView.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -6),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ]

        listConstraints = [
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            imageView.widthAnchor.constraint(equalToConstant: 132),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        ]

        apply(style: .grid)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        posterTask?.cancel()
        posterTask = nil
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        representedID = nil
        imageView.image = nil
        titleLabel.text = nil
        metaLabel.text = nil
    }

    func configure(item: VideoItem, config: ServerConfig, client: APIClient, style: LayoutStyle) {
        representedID = item.id
        apply(style: style)
        titleLabel.text = item.name

        let remoteVideoURL = client.videoURL(for: item, config: config)
        if style == .list {
            metaLabel.text = metadataText(for: item, remoteURL: remoteVideoURL)
        }

        if let posterURL = client.posterURL(for: item, config: config) {
            posterTask = URLSession.shared.dataTask(with: posterURL) { [weak self] data, _, _ in
                guard let self = self, let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard self.representedID == item.id else { return }
                    self.imageView.image = image
                }
            }
            posterTask?.resume()
            return
        }

        guard let remoteVideoURL else { return }
        if let localURL = VideoDiskCache.shared.cachedFileURL(for: remoteVideoURL) {
            generateThumbnail(from: localURL, for: item.id)
        } else if !isLargeVideo(item) {
            generateThumbnail(from: remoteVideoURL, for: item.id)
        }
    }

    private func apply(style: LayoutStyle) {
        if activeStyle == style { return }
        activeStyle = style
        NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

        switch style {
        case .grid:
            NSLayoutConstraint.activate(gridConstraints)
            titleBackgroundView.isHidden = false
            metaLabel.isHidden = true
            titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            titleLabel.numberOfLines = 2
        case .list:
            NSLayoutConstraint.activate(listConstraints)
            titleBackgroundView.isHidden = true
            metaLabel.isHidden = false
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            titleLabel.numberOfLines = 1
        }
    }

    private func metadataText(for item: VideoItem, remoteURL: URL?) -> String {
        let durationText = Self.formatDuration(item.durationSeconds)
        let resolvedSize = item.sizeBytes ?? remoteURL.flatMap { VideoDiskCache.shared.cachedSizeBytes(for: $0) }
        let sizeText = Self.formatSize(resolvedSize)
        return "\(durationText)  ·  \(sizeText)"
    }

    private static func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "--" }
        return sizeFormatter.string(fromByteCount: bytes)
    }

    private func generateThumbnail(from url: URL, for itemID: String) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        imageGenerator = generator
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, _, _ in
            guard let self = self, let cgImage = cgImage else { return }
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                guard self.representedID == itemID else { return }
                if self.imageView.image == nil {
                    self.imageView.image = image
                }
            }
        }
    }

    private func isLargeVideo(_ item: VideoItem) -> Bool {
        guard let size = item.sizeBytes else { return false }
        return size >= Self.largeVideoThresholdBytes
    }
}
