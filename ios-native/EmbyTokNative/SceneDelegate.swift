import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let root = ConnectViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.barStyle = .black
        nav.navigationBar.tintColor = .white
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        window.rootViewController = nav
        self.window = window
        window.makeKeyAndVisible()
    }
}
