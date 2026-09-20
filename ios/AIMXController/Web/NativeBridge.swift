import Foundation
import WebKit
import SwiftUI

/// Shared native<->JS bridge used by both the WebView and SwiftUI.
/// Mirrors the Android `AndroidBridge` JavascriptInterface and the native->JS
/// `window.*` calls from MainActivity.kt.
final class WebBridgeController: NSObject, ObservableObject {
    weak var webView: WKWebView?

    func evaluate(_ javaScript: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(javaScript) { _, error in
                if let error = error, (error as NSError).code != WKError.javaScriptExceptionOccurred.rawValue {
                    // Non-fatal; ignore evaluation errors (calls guard on window.* functions).
                }
            }
        }
    }

    /// window.setWifiConnectionStatus(status, ip) — keeps the html status badge in sync.
    func setConnectionStatus(_ state: ConnectionState, ip: String) {
        let status = state.label
        let ipString = state == .connected ? ip : ""
        let js = "javascript:if(window.setWifiConnectionStatus){ window.setWifiConnectionStatus('\(status)', '\(ipString)'); }"
        evaluate(js)
    }

    /// window.showController()
    func showController() {
        evaluate("javascript:showController();")
    }

    /// Injects --safe-inset-top / --safe-inset-bottom CSS vars, matching Android.
    func injectSafeInsets(top: CGFloat, bottom: CGFloat) {
        let js = """
        javascript:(function() { \
        document.documentElement.style.setProperty('--safe-inset-top', '\(top)px'); \
        document.documentElement.style.setProperty('--safe-inset-bottom', '\(bottom)px'); \
        })();
        """
        evaluate(js)
    }

    /// window.setKeybindValue(mode, keyName)
    func setKeybindValue(mode: String, keyName: String) {
        let js = "javascript:if(window.setKeybindValue){ window.setKeybindValue('\(mode)', '\(keyName)'); }"
        evaluate(js)
    }
}

/// Receives messages posted from controller.html via the injected shim.
final class NativeBridge: NSObject, WKScriptMessageHandler {
    private weak var viewModel: MainViewModel?
    private weak var bridge: WebBridgeController?

    init(viewModel: MainViewModel, bridge: WebBridgeController) {
        self.viewModel = viewModel
        self.bridge = bridge
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let viewModel = viewModel else { return }
        let body = message.body as? [String: Any] ?? [:]

        switch message.name {
        case "sendStateToPC":
            let stateJson = body["state"] as? String ?? ""
            viewModel.transmitJsonState(stateJson)
        case "onControlAction":
            let action = body["action"] as? String ?? ""
            let value = body["value"] as? String ?? ""
            viewModel.transmitPlainCommand(action, value)
        case "sendBypassRequest":
            viewModel.sendBypassRequest()
        case "onPageLoaded":
            bridge?.setConnectionStatus(viewModel.connectionState, ip: viewModel.pcIP)
        default:
            break
        }
    }
}