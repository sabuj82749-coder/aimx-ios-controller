import SwiftUI
import WebKit

/// WKWebView wrapper hosting the byte-identical controller.html from the Android
/// project, with the injected `window.AndroidBridge` shim.
struct ControllerWebView: UIViewRepresentable {
    @ObservedObject var viewModel: MainViewModel
    let bridge: WebBridgeController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Register the four handlers the shim posts to.
        for name in ["sendStateToPC", "onControlAction", "sendBypassRequest", "onPageLoaded"] {
            configuration.userContentController.add(
                NativeBridge(viewModel: viewModel, bridge: bridge),
                name: name
            )
        }

        // Inject the AndroidBridge shim before any page script runs.
        guard let shimURL = Bundle.main.url(forResource: "bridge_shim", withExtension: "js"),
              let shimSource = try? String(contentsOf: shimURL, encoding: .utf8) else {
            fatalError("bridge_shim.js missing from bundle")
        }
        let shim = WKUserScript(source: shimSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(shim)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.isInspectable = true

        bridge.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "controller", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // ViewModel changes are pushed through the bridge from RootView.
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: ControllerWebView

        init(_ parent: ControllerWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Mirror MainActivity.onWebPageLoaded().
            let state = parent.viewModel.connectionState
            parent.bridge.setConnectionStatus(state, ip: parent.viewModel.pcIP)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error.localizedDescription)")
        }
    }
}