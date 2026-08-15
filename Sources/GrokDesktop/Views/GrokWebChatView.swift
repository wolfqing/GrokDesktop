import AppKit
import SwiftUI
import WebKit

struct GrokWebChatView: NSViewRepresentable {
    var onSignedInChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSignedInChange: onSignedInChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        GrokWebChatHost.shared.view(delegate: context.coordinator)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSignedInChange = onSignedInChange
        view.navigationDelegate = context.coordinator
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSignedInChange: ((Bool) -> Void)?

        init(onSignedInChange: ((Bool) -> Void)?) {
            self.onSignedInChange = onSignedInChange
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if GrokWebSession.isOAuthCallback(url) {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated, !GrokWebSession.shouldStayInApp(url) {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host?.lowercased() ?? ""
            let path = webView.url?.path.lowercased() ?? ""
            let onLogin = host.contains("accounts.x.ai") || path.contains("sign-in") || path.contains("login")
            onSignedInChange?(!onLogin && host.contains("grok.com"))
        }
    }
}
