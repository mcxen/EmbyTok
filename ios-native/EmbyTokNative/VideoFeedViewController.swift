import UIKit

final class VideoFeedViewController: UIViewController {
    private let client: APIClient
    private let config: ServerConfig

    private var items: [VideoItem] = []
    private var isLoading = false
    private var nextStartIndex = 0
    private var totalCount = 0
    private let preloadCache = PreloadCache()

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)

    private var activeIndex: Int = 0
    private let initialIndex: Int

    init(client: APIClient, config: ServerConfig, initialItems: [VideoItem], totalCount: Int, nextStartIndex: Int, initialIndex: Int = 0) {
        self.client = client
        self.config = config
        self.items = initialItems
        self.totalCount = totalCount
        self.nextStartIndex = nextStartIndex
        self.initialIndex = initialIndex
        self.activeIndex = max(0, min(initialIndex, max(initialItems.count - 1, 0)))

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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "视频"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "全部", style: .plain, target: self, action: #selector(openGrid))

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
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
        if activeIndex == 0 && initialIndex > 0 {
            scrollToIndex(initialIndex, animated: false)
        }
        playVisibleCell()
        preloadNextItems(from: activeIndex)
    }

    private func updateActiveIndex() {
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        let index = Int(round(collectionView.contentOffset.y / height))
        if index != activeIndex {
            activeIndex = max(0, min(index, items.count - 1))
            playVisibleCell()
            preloadNextItems(from: activeIndex)
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
                videoCell.startPlayback()
            } else {
                videoCell.stopPlayback()
            }
        }
    }

    private func maybeLoadMore() {
        guard !isLoading, items.count < totalCount, activeIndex >= items.count - 3 else { return }
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
                case .failure:
                    break
                }
            }
        }
    }

    private func preloadNextItems(from index: Int) {
        let start = index + 1
        let end = min(items.count, start + 2)
        guard start < end else { return }

        for nextIndex in start..<end {
            let item = items[nextIndex]
            if let url = client.videoURL(for: item, config: config) {
                preloadCache.preload(id: item.id, url: url)
            }
        }
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
        activeIndex = safeIndex
        collectionView.scrollToItem(at: IndexPath(item: safeIndex, section: 0), at: .centeredVertically, animated: animated)
        playVisibleCell()
        preloadNextItems(from: activeIndex)
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
        cell.configure(item: item, config: config, client: client, preloadCache: preloadCache)
        return cell
    }
}

extension VideoFeedViewController: UICollectionViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateActiveIndex()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateActiveIndex()
        }
    }
}
