import SwiftUI

@main
struct AIMXControllerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var bridgeController = WebBridgeController()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel, bridgeController: bridgeController)
                .environmentObject(viewModel)
                .environmentObject(bridgeController)
                .preferredColorScheme(.dark)
        }
    }
}

/// iOS analog of the Android `MainActivity` application-state glue: wires the
/// LAN-reconnect behavior so the controller resumes on next foreground.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        NotificationCenter.default.post(name: .aimxDidEnterForeground, object: nil)
    }
}
