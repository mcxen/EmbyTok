import UIKit

final class VideoGridViewController: UIViewController {
    private enum DisplayMode: Int {
        case grid = 0
        case list = 1
    }

    private static let displayModeKey = "embytok.grid.displayMode"

    private let client: APIClient
    private let config: ServerConfig

    private var items: [VideoItem]
    private var totalCount: Int
    private var nextStartIndex: Int
    private var isLoading = false
    private var lastLayoutWidth: CGFloat = 0
    private var displayMode: DisplayMode

    var onSelect: ((Int) -> Void)?
    var onDataUpdated: (([VideoItem], Int, Int) -> Void)?

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private let modeControl = UISegmentedControl(items: ["卡片", "列表"])

    init(client: APIClient, config: ServerConfig, items: [VideoItem], totalCount: Int, nextStartIndex: Int) {
        self.client = client
        self.config = config
        self.items = items
        self.totalCount = totalCount
        self.nextStartIndex = nextStartIndex
        if let stored = UserDefaults.standard.object(forKey: Self.displayModeKey) as? Int,
           let mode = DisplayMode(rawValue: stored) {
            self.displayMode = mode
        } else {
            self.displayMode = .grid
        }

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
        modeControl.selectedSegmentIndex = displayMode.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modeControl)

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
        applyDisplayMode(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        if abs(width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = width
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    @objc private func modeChanged() {
        let selected = DisplayMode(rawValue: modeControl.selectedSegmentIndex) ?? .grid
        guard selected != displayMode else { return }
        displayMode = selected
        UserDefaults.standard.set(selected.rawValue, forKey: Self.displayModeKey)
        applyDisplayMode(animated: true)
    }

    private func applyDisplayMode(animated: Bool) {
        let applyChanges = {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.reloadData()
        }
        if animated {
            UIView.transition(
                with: collectionView,
                duration: 0.2,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: applyChanges
            )
        } else {
            applyChanges()
        }
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
        let style: VideoGridCell.LayoutStyle = displayMode == .list ? .list : .grid
        cell.configure(item: item, config: config, client: client, style: style)
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
        let layout = collectionViewLayout as? UICollectionViewFlowLayout
        let sectionInset = layout?.sectionInset ?? .zero
        let spacing = layout?.minimumInteritemSpacing ?? 8
        if displayMode == .list {
            let rowWidth = floor(width - sectionInset.left - sectionInset.right)
            return CGSize(width: rowWidth, height: 92)
        }
        let columns = resolvedColumnCount(
            for: width,
            horizontalPadding: sectionInset.left + sectionInset.right,
            itemSpacing: spacing
        )
        let totalSpacing = sectionInset.left + sectionInset.right + (columns - 1) * spacing
        let cellWidth = floor((width - totalSpacing) / columns)
        let cellHeight = cellWidth * 1.6
        return CGSize(width: cellWidth, height: cellHeight)
    }

    private func resolvedColumnCount(for width: CGFloat, horizontalPadding: CGFloat, itemSpacing: CGFloat) -> CGFloat {
        let minCellWidth: CGFloat = traitCollection.horizontalSizeClass == .regular ? 220 : 160
        let usableWidth = max(0, width - horizontalPadding)
        let raw = floor((usableWidth + itemSpacing) / (minCellWidth + itemSpacing))
        let minColumns: CGFloat = 2
        let maxColumns: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
        return max(minColumns, min(maxColumns, raw))
    }
}
