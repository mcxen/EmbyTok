import UIKit

final class SettingsViewController: UIViewController {
    private static let minCacheCount = 8
    private static let maxCacheCount = 12

    private let cacheCountLabel = UILabel()
    private let cacheStepper = UIStepper()
    private let serverTypeControl = UISegmentedControl(items: ServerType.allCases.map { $0.displayName })
    private let reconnectButton = UIButton(type: .system)
    private let speedTestTitle = UILabel()
    private let speedTestResult = UILabel()
    private let speedTestButton = UIButton(type: .system)
    private let cacheListTitle = UILabel()
    private let cacheListLabel = UILabel()

    private var cacheCount: Int
    private var serverType: ServerType

    var onCacheCountChanged: ((Int) -> Void)?
    var onServerTypeChanged: ((ServerType) -> Void)?
    var onReconnectRequested: (() -> Void)?
    var onSpeedTestRequested: (() -> Void)?
    var onSpeedTestResult: ((String) -> Void)?

    init(cacheCount: Int, serverType: ServerType) {
        self.cacheCount = max(Self.minCacheCount, min(Self.maxCacheCount, cacheCount))
        self.serverType = serverType
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "设置"

        let cacheTitle = UILabel()
        cacheTitle.text = "缓存数量"
        cacheTitle.textColor = .white
        cacheTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        cacheCountLabel.textColor = .white
        cacheCountLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)

        cacheStepper.minimumValue = Double(Self.minCacheCount)
        cacheStepper.maximumValue = Double(Self.maxCacheCount)
        cacheStepper.stepValue = 1
        cacheStepper.addTarget(self, action: #selector(cacheStepperChanged), for: .valueChanged)

        serverTypeControl.selectedSegmentIndex = ServerType.allCases.firstIndex(of: serverType) ?? 0
        serverTypeControl.addTarget(self, action: #selector(serverTypeChanged), for: .valueChanged)

        reconnectButton.setTitle("重新连接", for: .normal)
        reconnectButton.backgroundColor = UIColor.systemIndigo
        reconnectButton.setTitleColor(.white, for: .normal)
        reconnectButton.layer.cornerRadius = 10
        reconnectButton.addTarget(self, action: #selector(reconnectTapped), for: .touchUpInside)

        speedTestTitle.text = "网络测速"
        speedTestTitle.textColor = .white
        speedTestTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        speedTestResult.textColor = UIColor(white: 0.8, alpha: 1)
        speedTestResult.font = UIFont.systemFont(ofSize: 13)
        speedTestResult.numberOfLines = 2
        speedTestResult.text = "未测速"

        speedTestButton.setTitle("开始测速", for: .normal)
        speedTestButton.backgroundColor = UIColor(white: 0.2, alpha: 1)
        speedTestButton.setTitleColor(.white, for: .normal)
        speedTestButton.layer.cornerRadius = 10
        speedTestButton.addTarget(self, action: #selector(speedTestTapped), for: .touchUpInside)

        cacheListTitle.text = "已缓存视频"
        cacheListTitle.textColor = .white
        cacheListTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        cacheListLabel.textColor = UIColor(white: 0.8, alpha: 1)
        cacheListLabel.font = UIFont.systemFont(ofSize: 12)
        cacheListLabel.numberOfLines = 0
        cacheListLabel.text = "暂无"

        let cacheRow = UIStackView(arrangedSubviews: [cacheTitle, cacheCountLabel])
        cacheRow.axis = .horizontal
        cacheRow.distribution = .equalSpacing

        let cacheContainer = UIStackView(arrangedSubviews: [cacheRow, cacheStepper])
        cacheContainer.axis = .vertical
        cacheContainer.spacing = 12
        cacheContainer.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cacheContainer.layer.cornerRadius = 12
        cacheContainer.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        cacheContainer.isLayoutMarginsRelativeArrangement = true

        let serverTitle = UILabel()
        serverTitle.text = "数据源"
        serverTitle.textColor = .white
        serverTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        let serverContainer = UIStackView(arrangedSubviews: [serverTitle, serverTypeControl])
        serverContainer.axis = .vertical
        serverContainer.spacing = 12
        serverContainer.backgroundColor = UIColor(white: 0.12, alpha: 1)
        serverContainer.layer.cornerRadius = 12
        serverContainer.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        serverContainer.isLayoutMarginsRelativeArrangement = true

        let speedContainer = UIStackView(arrangedSubviews: [speedTestTitle, speedTestResult, speedTestButton])
        speedContainer.axis = .vertical
        speedContainer.spacing = 12
        speedContainer.backgroundColor = UIColor(white: 0.12, alpha: 1)
        speedContainer.layer.cornerRadius = 12
        speedContainer.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        speedContainer.isLayoutMarginsRelativeArrangement = true

        let cacheListContainer = UIStackView(arrangedSubviews: [cacheListTitle, cacheListLabel])
        cacheListContainer.axis = .vertical
        cacheListContainer.spacing = 8
        cacheListContainer.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cacheListContainer.layer.cornerRadius = 12
        cacheListContainer.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        cacheListContainer.isLayoutMarginsRelativeArrangement = true

        let stack = UIStackView(arrangedSubviews: [serverContainer, cacheContainer, cacheListContainer, speedContainer, reconnectButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])

        updateCacheUI()
    }

    private func updateCacheUI() {
        cacheStepper.value = Double(cacheCount)
        cacheCountLabel.text = "\(cacheCount)"
    }

    @objc private func cacheStepperChanged() {
        cacheCount = max(Self.minCacheCount, min(Self.maxCacheCount, Int(cacheStepper.value)))
        updateCacheUI()
        onCacheCountChanged?(cacheCount)
    }

    @objc private func serverTypeChanged() {
        let index = serverTypeControl.selectedSegmentIndex
        serverType = ServerType.allCases[max(0, index)]
        onServerTypeChanged?(serverType)
    }

    @objc private func reconnectTapped() {
        onReconnectRequested?()
    }

    @objc private func speedTestTapped() {
        speedTestResult.text = "测速中..."
        onSpeedTestRequested?()
    }

    func updateSpeedTestResult(_ text: String) {
        speedTestResult.text = text
    }

    func updateCachedVideos(_ names: [String]) {
        if names.isEmpty {
            cacheListLabel.text = "暂无"
        } else {
            cacheListLabel.text = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
    }
}
