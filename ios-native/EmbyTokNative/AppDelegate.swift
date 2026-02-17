import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        } catch {
            do {
                // Some devices/routes reject Bluetooth A2DP for this category combo.
                try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            } catch {
                print("AVAudioSession category setup failed: \(error.localizedDescription)")
            }
        }
        do {
            try session.setActive(true)
        } catch {
            print("AVAudioSession activate failed: \(error.localizedDescription)")
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
