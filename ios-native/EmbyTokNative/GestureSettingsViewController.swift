import UIKit

enum GestureSettings {
    static let pinchPureModeKey = "embytok.gesture.pinchPureMode"
    static let twoFingerMuteKey = "embytok.gesture.twoFingerMute"
    static let pureModeSwipeSeekKey = "embytok.gesture.pureModeSwipeSeek"

    static let didChangeNotification = Notification.Name("embytok.gesture.settingsChanged")

    static var isPinchPureModeEnabled: Bool {
        get { bool(forKey: pinchPureModeKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: pinchPureModeKey) }
    }

    static var isTwoFingerMuteEnabled: Bool {
        get { bool(forKey: twoFingerMuteKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: twoFingerMuteKey) }
    }

    static var isPureModeSwipeSeekEnabled: Bool {
        get { bool(forKey: pureModeSwipeSeekKey, defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: pureModeSwipeSeekKey) }
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

final class GestureSettingsViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case general
        case pureMode

        var title: String {
            switch self {
            case .general: return "基础手势"
            case .pureMode: return "纯净模式"
            }
        }
    }

    private enum Row: Int {
        case pinchPureMode
        case twoFingerMute
        case pureModeSwipeSeek

        var title: String {
            switch self {
            case .pinchPureMode: return "双指捏合切换纯净模式"
            case .twoFingerMute: return "双指点击切换静音"
            case .pureModeSwipeSeek: return "左右滑动调节进度"
            }
        }

        var detail: String {
            switch self {
            case .pinchPureMode: return "双指张开进入，捏合退出"
            case .twoFingerMute: return "单击或双击均触发"
            case .pureModeSwipeSeek: return "仅在纯净模式下生效"
            }
        }
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "手势控制"
        view.backgroundColor = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0, alpha: 1)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        navigationController?.navigationBar.tintColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.estimatedRowHeight = 56
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func rows(for section: Section) -> [Row] {
        switch section {
        case .general:
            return [.pinchPureMode, .twoFingerMute]
        case .pureMode:
            return [.pureModeSwipeSeek]
        }
    }

    private func isEnabled(for row: Row) -> Bool {
        switch row {
        case .pinchPureMode:
            return GestureSettings.isPinchPureModeEnabled
        case .twoFingerMute:
            return GestureSettings.isTwoFingerMuteEnabled
        case .pureModeSwipeSeek:
            return GestureSettings.isPureModeSwipeSeekEnabled
        }
    }

    private func setEnabled(_ enabled: Bool, for row: Row) {
        switch row {
        case .pinchPureMode:
            GestureSettings.isPinchPureModeEnabled = enabled
        case .twoFingerMute:
            GestureSettings.isTwoFingerMuteEnabled = enabled
        case .pureModeSwipeSeek:
            GestureSettings.isPureModeSwipeSeekEnabled = enabled
        }
        GestureSettings.notifyChanged()
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        let sectionIndex = sender.tag >> 16
        let rowIndex = sender.tag & 0xFFFF
        guard let section = Section(rawValue: sectionIndex) else { return }
        let rows = rows(for: section)
        guard rowIndex >= 0 && rowIndex < rows.count else { return }
        setEnabled(sender.isOn, for: rows[rowIndex])
    }
}

extension GestureSettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return rows(for: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseID = "GestureToggleCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        guard let section = Section(rawValue: indexPath.section) else { return cell }
        let row = rows(for: section)[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.secondaryText = row.detail
        content.textProperties.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        content.secondaryTextProperties.color = UIColor(white: 0.72, alpha: 1)
        cell.contentConfiguration = content

        let toggle = UISwitch()
        toggle.isOn = isEnabled(for: row)
        toggle.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        toggle.tag = (indexPath.section << 16) | indexPath.row
        cell.accessoryView = toggle
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }
}

extension GestureSettingsViewController: UITableViewDelegate {}
