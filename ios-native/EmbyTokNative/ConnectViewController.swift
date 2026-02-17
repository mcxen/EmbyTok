import UIKit

final class ConnectViewController: UIViewController {
    private let client = APIClient()

    private let serverTypeControl = UISegmentedControl(items: ServerType.allCases.map { $0.displayName })
    private let urlField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var isConnecting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "EmbyTok"
        navigationController?.navigationBar.prefersLargeTitles = true

        serverTypeControl.selectedSegmentIndex = 0
        serverTypeControl.addTarget(self, action: #selector(serverTypeChanged), for: .valueChanged)

        configureField(urlField, placeholder: "服务器地址 (例如 http://192.168.1.10:8096)")
        configureField(usernameField, placeholder: "用户名 (Emby 可选)")
        configureField(passwordField, placeholder: "密码 / Token / ServiceId")
        passwordField.isSecureTextEntry = false

        connectButton.setTitle("连接", for: .normal)
        connectButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        connectButton.backgroundColor = UIColor.systemIndigo
        connectButton.tintColor = .white
        connectButton.layer.cornerRadius = 12
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        statusLabel.textColor = .systemRed
        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [
            serverTypeControl,
            urlField,
            usernameField,
            passwordField,
            connectButton,
            statusLabel
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])

        loadSavedValues()
        updateFieldHints()
    }

    private func configureField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.backgroundColor = UIColor(white: 0.12, alpha: 1)
        field.textColor = .white
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
    }

    private func loadSavedValues() {
        let defaults = UserDefaults.standard
        urlField.text = defaults.string(forKey: "embytok.url")
        usernameField.text = defaults.string(forKey: "embytok.username")
        passwordField.text = defaults.string(forKey: "embytok.password")
        if let savedType = defaults.string(forKey: "embytok.serverType"), let type = ServerType(rawValue: savedType) {
            serverTypeControl.selectedSegmentIndex = ServerType.allCases.firstIndex(of: type) ?? 0
        }
    }

    private func saveValues(serverType: ServerType) {
        let defaults = UserDefaults.standard
        defaults.set(urlField.text, forKey: "embytok.url")
        defaults.set(usernameField.text, forKey: "embytok.username")
        defaults.set(passwordField.text, forKey: "embytok.password")
        defaults.set(serverType.rawValue, forKey: "embytok.serverType")
    }

    @objc private func serverTypeChanged() {
        updateFieldHints()
    }

    private func updateFieldHints() {
        let serverType = selectedServerType()
        switch serverType {
        case .emby:
            usernameField.placeholder = "用户名"
            passwordField.placeholder = "密码"
        case .folder:
            usernameField.placeholder = "显示名称 (可选)"
            passwordField.placeholder = "ServiceId 或 服务名称"
        }
    }

    private func selectedServerType() -> ServerType {
        let index = max(0, serverTypeControl.selectedSegmentIndex)
        return ServerType.allCases[index]
    }

    @objc private func connectTapped() {
        if isConnecting { return }
        statusLabel.text = ""

        guard let raw = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            statusLabel.text = "请输入服务器地址"
            return
        }

        guard let baseURL = normalizeURL(raw) else {
            statusLabel.text = "服务器地址格式错误"
            return
        }

        let serverType = selectedServerType()
        let username = usernameField.text ?? ""
        let password = passwordField.text ?? ""

        isConnecting = true
        connectButton.setTitle("连接中…", for: .normal)
        connectButton.isEnabled = false

        client.authenticate(serverType: serverType, baseURL: baseURL, username: username, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnecting = false
                self.connectButton.setTitle("连接", for: .normal)
                self.connectButton.isEnabled = true

                switch result {
                case .success(let config):
                    self.saveValues(serverType: serverType)
                    self.loadInitialVideos(config: config)
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func loadInitialVideos(config: ServerConfig) {
        statusLabel.text = "加载视频中…"
        client.fetchVideos(config: config, skip: 0, limit: 20) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let page):
                    let controller = VideoFeedViewController(
                        client: self.client,
                        config: config,
                        initialItems: page.items,
                        totalCount: page.totalCount,
                        nextStartIndex: page.nextStartIndex
                    )
                    self.navigationController?.pushViewController(controller, animated: true)
                    self.statusLabel.text = ""
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func normalizeURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        return URL(string: trimmed)
    }
}
