import Foundation
import WebKit

@MainActor
enum GrokWebSession {
    static let homeURL = URL(string: "https://grok.com/")!
    private static let storeID = UUID(uuidString: "6B2E0C3A-9F14-4D7E-9C21-8A0B5E4D1F70")!

    static var dataStore: WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: storeID)
    }

    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        return config
    }

    static func isOAuthCallback(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        guard host == "127.0.0.1" || host == "localhost" else { return false }
        let path = url.path.lowercased()
        return path.contains("callback") || path.contains("oauth")
    }

    static func callbackCode(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" || $0.name == "user_code" })?
            .value
    }

    static func shouldStayInApp(_ url: URL) -> Bool {
        if isOAuthCallback(url) { return true }
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
        guard scheme == "https" || scheme == "http" else { return false }
        let host = (url.host ?? "").lowercased()
        let allowed = [
            "grok.com",
            "x.ai",
            "x.com",
            "twitter.com",
            "twimg.com",
            "accounts.google.com",
            "google.com",
            "gstatic.com",
            "appleid.apple.com",
            "apple.com"
        ]
        return allowed.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func chatLikelySignedIn() async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            let name = cookie.name.lowercased()
            let relevant = domain.contains("grok.com") || domain.contains("x.ai")
            let skip = name.contains("csrf") || name.contains("locale") || name.contains("theme")
            return relevant && !skip && cookie.value.count > 10
        }
    }

    static func clear() async {
        let store = dataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
        await GrokWebChatHost.shared.reset()
    }
}

@MainActor
final class GrokWebChatHost {
    static let shared = GrokWebChatHost()

    private(set) var webView: WKWebView?

    func view(delegate: WKNavigationDelegate) -> WKWebView {
        if let webView {
            webView.navigationDelegate = delegate
            webView.removeFromSuperview()
            return webView
        }
        let view = WKWebView(frame: .zero, configuration: GrokWebSession.configuration())
        view.navigationDelegate = delegate
        webView = view
        view.load(URLRequest(url: GrokWebSession.homeURL))
        return view
    }

    func reloadHome() {
        guard let webView else { return }
        webView.load(URLRequest(url: GrokWebSession.homeURL))
    }

    func reset() async {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }
}
