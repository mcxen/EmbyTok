import UIKit

final class VideoGridCell: UICollectionViewCell {
    static let reuseId = "VideoGridCell"

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private var posterTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.numberOfLines = 2

        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        posterTask?.cancel()
        posterTask = nil
        imageView.image = nil
        titleLabel.text = nil
    }

    func configure(item: VideoItem, config: ServerConfig, client: APIClient) {
        titleLabel.text = item.name
        if let posterURL = client.posterURL(for: item, config: config) {
            posterTask = URLSession.shared.dataTask(with: posterURL) { [weak self] data, _, _ in
                guard let self = self, let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.imageView.image = image
                }
            }
            posterTask?.resume()
        }
    }
}
