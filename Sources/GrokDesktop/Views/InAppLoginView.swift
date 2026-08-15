import AppKit
import SwiftUI
import WebKit

struct InAppLoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.dismissInAppLogin() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(l10n.t("Sign in", "登录"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let code = model.client.authChallenge?.userCode, !code.isEmpty {
                        Text(code)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.secondary)
                    }
                    Button(l10n.t("System browser", "系统浏览器")) {
                        model.openLoginInSystemBrowser()
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    Button(l10n.t("Close", "关闭")) {
                        model.dismissInAppLogin()
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                if let url = model.inAppLoginURL {
                    InAppLoginWebView(
                        url: url,
                        onCallback: { model.handleLoginCallback($0) }
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 720, minHeight: 560)
            .frame(maxWidth: 920, maxHeight: 680)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline)
            )
        }
    }
}

private struct InAppLoginWebView: NSViewRepresentable {
    let url: URL
    var onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: GrokWebSession.configuration())
        view.navigationDelegate = context.coordinator
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onCallback = onCallback
        if context.coordinator.loaded != url {
            context.coordinator.loaded = url
            view.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCallback: (URL) -> Void
        var loaded: URL?

        init(onCallback: @escaping (URL) -> Void) {
            self.onCallback = onCallback
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
                onCallback(url)
                return
            }
            if navigationAction.navigationType == .linkActivated, !GrokWebSession.shouldStayInApp(url) {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
                return
            }
            decisionHandler(.allow)
        }
    }
}
