import SwiftUI

/// Root container that swaps between the native connect screen and the WebView
/// controller, mirroring MainActivity's `currentScreen` + `AnimatedVisibility`.
struct RootView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject private(set) var bridgeController: WebBridgeController

    @State private var transitionReverse = false

    var body: some View {
        ZStack {
            Color(red: 0.914, green: 0.929, blue: 0.969).ignoresSafeArea()

            switch viewModel.currentScreen {
            case .connecting:
                ConnectScreenView(viewModel: viewModel, bridge: bridgeController)
                    .transition(
                        transitionReverse
                            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
                    )
            case .controller:
                ControllerScreenRoute(viewModel: viewModel, bridge: bridgeController)
                    .transition(
                        transitionReverse
                            ? .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
                            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                    )
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentScreen)
        .onChange(of: viewModel.currentScreen) { screen in
            if screen == .controller {
                transitionReverse = false
                bridgeController.showController()
                bridgeController.setConnectionStatus(viewModel.connectionState, ip: viewModel.pcIP)
            }
        }
        .onAppear {
            bridgeController.injectSafeInsets(
                top: viewModel.safeAreaTop,
                bottom: viewModel.safeAreaBottom
            )
            bridgeController.setConnectionStatus(viewModel.connectionState, ip: viewModel.pcIP)
        }
    }
}

/// Resolves the controller tree so the web view (WKWebView) is created just
/// once and preserved across screen switches (mirrors `keepWebView` on Android).
private struct ControllerScreenRoute: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var bridge: WebBridgeController

    var body: some View {
        ControllerWebView(viewModel: viewModel, bridge: bridge)
            .animation(nil, value: viewModel.currentScreen)
    }
}
