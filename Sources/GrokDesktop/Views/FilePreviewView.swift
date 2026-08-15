import AppKit
import GrokDesktopCore
import SwiftUI
import WebKit

struct FilePreviewPane: View {
    let url: URL
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var document: FilePreviewDocument?

    var body: some View {
        let preview = document ?? FilePreview.load(url)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: preview.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Text(preview.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .help(preview.url.path)
                Spacer(minLength: 4)
                Button {
                    ChatLinkActions.reveal(preview.url)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(l10n.t("Show in Finder", "在 Finder 中显示"))
                Button {
                    ChatLinkActions.open(preview.url)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(l10n.t("Open", "打开"))
                Button {
                    model.clearPreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(l10n.t("Close preview", "关闭预览"))
            }
            .foregroundStyle(palette.secondary)

            Group {
                if !preview.exists {
                    placeholder(l10n.t("This file is not on disk.", "磁盘上没有这个文件。"))
                } else if preview.kind == .directory {
                    placeholder(l10n.t("This is a folder.", "这是一个文件夹。"))
                } else {
                    content(preview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if preview.truncated {
                Text(l10n.t("Showing the first part of the file.", "只显示了文件开头。"))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
        }
        .onAppear { document = FilePreview.load(url) }
        .onChange(of: url) { _, next in
            document = FilePreview.load(next)
        }
    }

    @ViewBuilder
    private func content(_ preview: FilePreviewDocument) -> some View {
        switch preview.kind {
        case .markdown:
            ScrollView {
                MessageMarkdownView(text: preview.text, fontSize: 13)
                    .padding(10)
            }
        case .html:
            HTMLPreviewView(url: preview.url, isDark: palette.isDark)
        case .image:
            if let image = NSImage(contentsOf: preview.url) {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
            } else if preview.url.pathExtension.lowercased() == "svg" {
                HTMLPreviewView(url: preview.url, isDark: palette.isDark)
            } else {
                placeholder(l10n.t("Couldn’t read this image.", "读不了这张图。"))
            }
        case .text:
            ScrollView {
                Text(preview.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        case .binary:
            placeholder(l10n.t("No in-app preview. Open it instead.", "不能在这里预览，请用外部应用打开。"))
        case .directory, .missing:
            EmptyView()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for kind: FilePreviewKind) -> String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .html: return "safari"
        case .image: return "photo"
        case .text: return "doc.text"
        case .binary: return "doc"
        case .directory: return "folder"
        case .missing: return "questionmark.folder"
        }
    }
}

private struct HTMLPreviewView: NSViewRepresentable {
    let url: URL
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.isDark = isDark
        guard context.coordinator.loadedPath != url.path else { return }
        context.coordinator.loadedPath = url.path
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedPath = ""
        var isDark = false

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            Task { @MainActor in
                ChatLinkActions.activate(url)
            }
        }
    }
}
