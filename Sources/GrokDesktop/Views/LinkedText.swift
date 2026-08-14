import AppKit
import GrokDesktopCore
import SwiftUI

struct LinkedText: View {
    let text: String
    var fontSize: CGFloat = 16
    var monospaced = false
    var markdown = true
    var fillsWidth = true
    var color: Color?
    var maxContentWidth: CGFloat = 520

    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @EnvironmentObject private var model: AppModel

    var live = false

    var body: some View {
        if live || !Self.shouldUseNativeView(text, baseDirectory: model.client.workingDirectory) {
            plainText
        } else {
            LinkedTextNSView(
                text: text,
                fontSize: fontSize,
                monospaced: monospaced,
                markdown: markdown,
                fillsWidth: fillsWidth,
                maxContentWidth: maxContentWidth,
                textColor: NSColor(color ?? palette.text),
                linkColor: .linkColor,
                baseDirectory: model.client.workingDirectory,
                chinese: l10n.language == .chinese
            )
            .frame(maxWidth: fillsWidth ? .infinity : maxContentWidth, alignment: .leading)
            .fixedSize(horizontal: !fillsWidth, vertical: true)
        }
    }

    private var plainText: some View {
        Group {
            if markdown {
                Text(Self.swiftUIMarkdown(text))
            } else {
                Text(text)
            }
        }
        .font(monospaced ? .system(size: fontSize, design: .monospaced) : .system(size: fontSize))
        .foregroundStyle(color ?? palette.text)
        .textSelection(.enabled)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }

    private static func shouldUseNativeView(_ text: String, baseDirectory: URL) -> Bool {
        guard ChatLinkDetector.likelyContainsLinks(text) else { return false }
        return !ChatLinkDetector.detect(in: text, baseDirectory: baseDirectory).isEmpty
    }

    private static func swiftUIMarkdown(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct ChatLinkContextButtons: View {
    let url: URL
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(l10n.t("Open", "打开")) {
            ChatLinkActions.open(url)
        }
        Menu(l10n.t("Open With", "打开方式")) {
            let apps = ChatLinkActions.applications(for: url)
            let defaultApp = ChatLinkActions.defaultApplication(for: url)
            ForEach(apps.prefix(12), id: \.path) { app in
                let name = ChatLinkActions.appName(app)
                Button(app.path == defaultApp?.path ? l10n.t("\(name) (Default)", "\(name)（默认）") : name) {
                    ChatLinkActions.open(url, with: app)
                }
            }
            Divider()
            Button(l10n.t("Other…", "其他…")) {
                ChatLinkActions.chooseApp(for: url)
            }
        }
        if url.isFileURL {
            Button(l10n.t("Show in Finder", "在 Finder 中显示")) {
                ChatLinkActions.reveal(url)
            }
        }
        Button(url.isFileURL ? l10n.t("Copy Path", "复制路径") : l10n.t("Copy Link", "复制链接")) {
            ChatLinkActions.copy(url)
        }
    }
}

private struct LinkedTextNSView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let monospaced: Bool
    let markdown: Bool
    let fillsWidth: Bool
    let maxContentWidth: CGFloat
    let textColor: NSColor
    let linkColor: NSColor
    let baseDirectory: URL
    let chinese: Bool

    func makeCoordinator() -> LinkedTextCoordinator {
        LinkedTextCoordinator()
    }

    func makeNSView(context: Context) -> ChatTextView {
        let view = ChatTextView()
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.displaysLinkToolTips = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = fillsWidth
        view.textContainer?.heightTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        view.chinese = chinese
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ChatTextView, context: Context) {
        view.chinese = chinese
        view.delegate = context.coordinator
        apply(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatTextView, context: Context) -> CGSize? {
        apply(to: nsView)
        let proposedWidth = fillsWidth
            ? (proposal.width ?? maxContentWidth)
            : min(proposal.width ?? maxContentWidth, maxContentWidth)
        let width = max(proposedWidth, 40)
        nsView.textContainer?.widthTracksTextView = fillsWidth
        nsView.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        nsView.layoutManager?.ensureLayout(for: nsView.textContainer!)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else {
            return CGSize(width: width, height: fontSize + 4)
        }
        let used = manager.usedRect(for: container)
        let height = max(ceil(used.height), fontSize + 2)
        if fillsWidth {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: min(width, max(ceil(used.width + 2), 12)), height: height)
    }

    private func apply(to view: ChatTextView) {
        let fingerprint = "\(text.count)|\(text.hashValue)|\(fontSize)|\(monospaced)|\(markdown)|\(textColor.hash)|\(baseDirectory.path)"
        if view.appliedFingerprint == fingerprint { return }
        let rendered = Self.attributed(
            text,
            fontSize: fontSize,
            monospaced: monospaced,
            markdown: markdown,
            textColor: textColor,
            linkColor: linkColor,
            baseDirectory: baseDirectory
        )
        if view.textStorage?.isEqual(to: rendered) == true {
            view.appliedFingerprint = fingerprint
            return
        }
        view.textStorage?.setAttributedString(rendered)
        view.appliedFingerprint = fingerprint
    }

    static func attributed(
        _ text: String,
        fontSize: CGFloat,
        monospaced: Bool,
        markdown: Bool,
        textColor: NSColor,
        linkColor: NSColor,
        baseDirectory: URL
    ) -> NSAttributedString {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let mutable: NSMutableAttributedString
        if markdown {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            if let parsed = try? AttributedString(markdown: text, options: options) {
                mutable = NSMutableAttributedString(parsed)
            } else {
                mutable = NSMutableAttributedString(string: text)
            }
        } else {
            mutable = NSMutableAttributedString(string: text)
        }

        let full = NSRange(location: 0, length: mutable.length)
        if full.length > 0 {
            mutable.addAttribute(.paragraphStyle, value: paragraph, range: full)
            mutable.addAttribute(.foregroundColor, value: textColor, range: full)
            mutable.enumerateAttribute(.font, in: full) { value, range, _ in
                if let existing = value as? NSFont {
                    let converted = NSFontManager.shared.convert(existing, toSize: fontSize)
                    mutable.addAttribute(.font, value: converted, range: range)
                } else {
                    mutable.addAttribute(.font, value: font, range: range)
                }
            }
        }

        func styleLink(_ range: NSRange, url: URL) {
            mutable.addAttribute(.link, value: url, range: range)
            mutable.addAttribute(.foregroundColor, value: linkColor, range: range)
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            mutable.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
            mutable.addAttribute(.toolTip, value: url.isFileURL ? url.path : url.absoluteString, range: range)
        }

        if full.length > 0 {
            mutable.enumerateAttribute(.link, in: full) { value, range, _ in
                let url: URL?
                if let value = value as? URL {
                    url = value
                } else if let value = value as? String {
                    url = ChatLinkDetector.resolve(value, baseDirectory: baseDirectory)?.url ?? URL(string: value)
                } else {
                    url = nil
                }
                if let url { styleLink(range, url: url) }
            }
        }

        let displayed = mutable.string
        for link in ChatLinkDetector.detect(in: displayed, baseDirectory: baseDirectory) {
            if link.range.location + link.range.length > mutable.length { continue }
            if mutable.attribute(.link, at: link.range.location, effectiveRange: nil) != nil {
                continue
            }
            styleLink(link.range, url: link.url)
        }
        return mutable
    }
}

final class ChatTextView: NSTextView {
    var chinese = false
    var appliedFingerprint = ""

    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func scrollWheel(with event: NSEvent) {
        if let outer = enclosingScrollView {
            outer.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let url = url(at: index) {
            return ChatLinkActions.menu(for: url, chinese: chinese)
        }
        return super.menu(for: event)
    }

    func url(at index: Int) -> URL? {
        guard let storage = textStorage, index >= 0, index < storage.length else { return nil }
        let value = storage.attribute(.link, at: index, effectiveRange: nil)
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }
}

final class LinkedTextCoordinator: NSObject, NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL?
        if let link = link as? URL {
            url = link
        } else if let link = link as? String {
            url = URL(string: link)
        } else {
            url = nil
        }
        guard let url else { return false }
        ChatLinkActions.open(url)
        return true
    }
}
