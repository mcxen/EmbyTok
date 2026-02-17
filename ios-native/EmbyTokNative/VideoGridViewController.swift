import UIKit

final class VideoGridViewController: UIViewController {
    private let client: APIClient
    private let config: ServerConfig

    private var items: [VideoItem]
    private var totalCount: Int
    private var nextStartIndex: Int
    private var isLoading = false

    var onSelect: ((Int) -> Void)?
    var onDataUpdated: (([VideoItem], Int, Int) -> Void)?

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)

    init(client: APIClient, config: ServerConfig, items: [VideoItem], totalCount: Int, nextStartIndex: Int) {
        self.client = client
        self.config = config
        self.items = items
        self.totalCount = totalCount
        self.nextStartIndex = nextStartIndex

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "全部视频"

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VideoGridCell.self, forCellWithReuseIdentifier: VideoGridCell.reuseId)

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
    }

    private func loadMoreIfNeeded(for index: Int) {
        guard !isLoading, items.count < totalCount, index >= items.count - 8 else { return }
        loadMore()
    }

    private func loadMore() {
        isLoading = true
        spinner.startAnimating()
        client.fetchVideos(config: config, skip: nextStartIndex, limit: 30) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                self.isLoading = false

                switch result {
                case .success(let page):
                    let startIndex = self.items.count
                    self.items.append(contentsOf: page.items)
                    self.totalCount = page.totalCount
                    self.nextStartIndex = page.nextStartIndex
                    let newIndexPaths = (startIndex..<self.items.count).map { IndexPath(item: $0, section: 0) }
                    self.collectionView.performBatchUpdates({
                        self.collectionView.insertItems(at: newIndexPaths)
                    }, completion: nil)
                    self.onDataUpdated?(page.items, page.totalCount, page.nextStartIndex)
                case .failure:
                    break
                }
            }
        }
    }
}

extension VideoGridViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoGridCell.reuseId, for: indexPath) as? VideoGridCell else {
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        cell.configure(item: item, config: config, client: client)
        return cell
    }
}

extension VideoGridViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
        navigationController?.popViewController(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        loadMoreIfNeeded(for: indexPath.item)
    }
}

extension VideoGridViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let columns: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 4 : 3
        let totalSpacing = 12 * 2 + (columns - 1) * 8
        let cellWidth = (width - totalSpacing) / columns
        let cellHeight = cellWidth * 1.6
        return CGSize(width: cellWidth, height: cellHeight)
    }
}
