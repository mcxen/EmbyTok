import UIKit

struct VideoInfoRenameResult {
    let id: String
    let name: String
    let filePath: String?
}

final class VideoInfoViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case rename
        case favorite
        case details
    }

    private enum DetailRow: Int, CaseIterable {
        case path
        case size
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let renameFieldCell = TextFieldCell()
    private var isRenaming = false
    private let feedback = UINotificationFeedbackGenerator()

    private var currentItemID: String
    private var currentName: String
    private var currentFilePath: String?
    private var sizeBytes: Int64?
    private var isFavorite: Bool
    private let serverType: ServerType
    private let remoteURL: URL?

    var onToggleFavorite: ((String, Bool) -> Void)?
    var onRenameRequested: ((String, String, @escaping (Result<VideoInfoRenameResult, Error>) -> Void) -> Void)?

    init(
        itemID: String,
        name: String,
        filePath: String?,
        sizeBytes: Int64?,
        isFavorite: Bool,
        serverType: ServerType,
        remoteURL: URL?
    ) {
        self.currentItemID = itemID
        self.currentName = name
        self.currentFilePath = filePath
        self.sizeBytes = sizeBytes
        self.isFavorite = isFavorite
        self.serverType = serverType
        self.remoteURL = remoteURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0, alpha: 1)
        title = "视频信息"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.estimatedRowHeight = 56
        tableView.sectionHeaderTopPadding = 14
        tableView.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 18, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        renameFieldCell.textField.text = currentName
        renameFieldCell.textField.placeholder = "文件名称"
        renameFieldCell.textField.isEnabled = serverType == .folder
        renameFieldCell.textField.returnKeyType = .done
        renameFieldCell.textField.delegate = self
        feedback.prepare()
        fetchSizeIfNeeded()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func fetchSizeIfNeeded() {
        guard (sizeBytes ?? 0) <= 0, let remoteURL else { return }
        VideoDiskCache.shared.fetchRemoteSize(for: remoteURL) { [weak self] bytes in
            guard let self = self else { return }
            self.sizeBytes = bytes
            if let section = Section.allCases.firstIndex(of: .details) {
                let indexPath = IndexPath(row: DetailRow.size.rawValue, section: section)
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }

    private func attemptRename() {
        guard serverType == .folder else { return }
        let newName = renameFieldCell.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !newName.isEmpty else {
            showAlert(title: "名称不能为空", message: "请输入新的文件名称")
            return
        }
        guard newName != currentName else {
            showAlert(title: "名称未改变", message: "请输入不同的名称")
            return
        }
        guard let onRenameRequested else {
            showAlert(title: "无法改名", message: "当前无法完成改名操作")
            return
        }

        isRenaming = true
        reloadRenameAction()
        onRenameRequested(currentItemID, newName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRenaming = false
                self.reloadRenameAction()
                switch result {
                case .success(let response):
                    self.currentItemID = response.id
                    self.currentName = response.name
                    self.currentFilePath = response.filePath
                    self.renameFieldCell.textField.text = response.name
                    self.reloadDetailsSection()
                    self.feedback.notificationOccurred(.success)
                case .failure(let error):
                    self.feedback.notificationOccurred(.error)
                    self.showAlert(title: "改名失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func reloadRenameAction() {
        let section = Section.rename.rawValue
        let indexPath = IndexPath(row: 1, section: section)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func reloadDetailsSection() {
        let section = Section.details.rawValue
        let rows = DetailRow.allCases.map { IndexPath(row: $0.rawValue, section: section) }
        tableView.reloadRows(at: rows, with: .none)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension VideoInfoViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .rename:
            return 2
        case .favorite:
            return 1
        case .details:
            return DetailRow.allCases.count
        case .none:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .rename:
            if indexPath.row == 0 {
                return renameFieldCell
            }
            let reuseID = "RenameActionCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .default, reuseIdentifier: reuseID)
            cell.backgroundColor = .clear
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            cell.textLabel?.text = isRenaming ? "保存中…" : "保存名称"
            let canRename = serverType == .folder && !isRenaming
            cell.textLabel?.textColor = canRename ? UIColor.systemBlue : UIColor(white: 0.5, alpha: 1)
            cell.selectionStyle = canRename ? .default : .none
            if isRenaming {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            } else {
                cell.accessoryView = nil
            }
            return cell
        case .favorite:
            let reuseID = "FavoriteToggleCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .default, reuseIdentifier: reuseID)
            cell.backgroundColor = .clear
            cell.textLabel?.text = "收藏"
            cell.textLabel?.textColor = .white
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = isFavorite
            toggle.addTarget(self, action: #selector(favoriteSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            return cell
        case .details:
            let reuseID = "DetailCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            var content = cell.defaultContentConfiguration()
            content.textProperties.color = .white
            content.secondaryTextProperties.color = UIColor(white: 0.7, alpha: 1)
            content.secondaryTextProperties.numberOfLines = 2

            let detailRow = DetailRow(rawValue: indexPath.row)
            switch detailRow {
            case .path:
                content.text = "路径"
                content.secondaryText = currentFilePath?.isEmpty == false ? currentFilePath : "--"
                content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
            case .size:
                content.text = "大小"
                content.secondaryText = VideoDiskCache.formatSize(sizeBytes)
            case .none:
                content.text = nil
            }
            cell.contentConfiguration = content
            return cell
        }
    }
}

extension VideoInfoViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .rename, serverType != .folder else { return nil }
        return "Emby 暂不支持改名"
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .rename, indexPath.row == 1 else { return }
        attemptRename()
    }
}

extension VideoInfoViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension VideoInfoViewController {
    @objc private func favoriteSwitchChanged(_ sender: UISwitch) {
        isFavorite = sender.isOn
        onToggleFavorite?(currentItemID, sender.isOn)
    }
}

private final class TextFieldCell: UITableViewCell {
    let textField = UITextField()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textColor = .white
        textField.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .whileEditing

        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
