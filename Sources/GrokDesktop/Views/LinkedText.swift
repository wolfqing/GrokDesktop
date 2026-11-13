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
        LinkedTextNSView(
            text: text,
            fontSize: fontSize,
            monospaced: monospaced,
            markdown: markdown && !live,
            fillsWidth: fillsWidth,
            maxContentWidth: maxContentWidth,
            textColor: NSColor(color ?? palette.text),
            linkColor: .linkColor,
            baseDirectory: model.client.workingDirectory,
            chinese: l10n.language == .chinese,
            live: live
        )
        .frame(maxWidth: fillsWidth ? .infinity : maxContentWidth, alignment: .leading)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

struct ChatLinkContextButtons: View {
    let url: URL
    @Environment(\.l10n) private var l10n

    var body: some View {
        if url.isFileURL {
            Button(l10n.t("Preview", "预览")) {
                ChatLinkActions.activate(url)
            }
        }
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
    var live = false

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
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.clipsToBounds = true
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .duringViewResize
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        view.chinese = chinese
        view.tracksBoundsWidth = fillsWidth
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ChatTextView, context: Context) {
        view.chinese = chinese
        view.delegate = context.coordinator
        view.tracksBoundsWidth = fillsWidth
        apply(to: view)
        view.reflowToBounds()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatTextView, context: Context) -> CGSize? {
        apply(to: nsView)
        let proposedWidth = fillsWidth
            ? (proposal.width ?? maxContentWidth)
            : min(proposal.width ?? maxContentWidth, maxContentWidth)
        let width = max(proposedWidth, 40)
        // Do not write this width onto the live text container. SwiftUI probes
        // several widths during a drag, and a half-applied wrap is what leaves
        // the previous lines sitting under the new ones.
        nsView.tracksBoundsWidth = fillsWidth
        if !fillsWidth {
            nsView.lockedWrapWidth = width
        }
        let measured = nsView.measuredSize(fittingWidth: width)
        if fillsWidth {
            return CGSize(width: width, height: measured.height)
        }
        return CGSize(width: min(width, measured.width), height: measured.height)
    }

    private func apply(to view: ChatTextView) {
        let fingerprint = "\(text.count)|\(text.hashValue)|\(fontSize)|\(monospaced)|\(markdown)|\(live)|\(textColor.hash)|\(GrokTheme.chatLineHeight)|\(baseDirectory.path)"
        if view.appliedFingerprint == fingerprint { return }
        let rendered = Self.attributed(
            text,
            fontSize: fontSize,
            monospaced: monospaced,
            markdown: markdown,
            textColor: textColor,
            linkColor: linkColor,
            baseDirectory: baseDirectory,
            detectLinks: !live
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
        baseDirectory: URL,
        detectLinks: Bool = true
    ) -> NSAttributedString {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if !monospaced {
            paragraph.lineHeightMultiple = GrokTheme.chatLineHeight
            paragraph.paragraphSpacing = GrokTheme.chatParagraphSpacing
        } else {
            paragraph.lineHeightMultiple = 1.18
        }

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

        if detectLinks {
            let displayed = mutable.string
            for link in ChatLinkDetector.detect(in: displayed, baseDirectory: baseDirectory) {
                if link.range.location + link.range.length > mutable.length { continue }
                if mutable.attribute(.link, at: link.range.location, effectiveRange: nil) != nil {
                    continue
                }
                styleLink(link.range, url: link.url)
            }
        }
        return mutable
    }
}

final class ChatTextView: NSTextView {
    var chinese = false
    var appliedFingerprint = ""
    /// Assistant prose follows the view width. A user bubble keeps the width it was measured at.
    var tracksBoundsWidth = true
    var lockedWrapWidth: CGFloat = 0
    private var mouseDownPoint: NSPoint?
    private var measuring = false

    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager, bounds.width > 1 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(ceil(used.height), 20))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged else { return }
        reflowToBounds()
        // SwiftUI is already measuring this drag. Invalidating here re-enters layout.
        if !inLiveResize {
            invalidateIntrinsicContentSize()
        } else {
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        reflowToBounds()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        clipsToBounds = true
        superview?.layerContentsRedrawPolicy = .duringViewResize
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        reflowToBounds()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if inLiveResize, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.compositingOperation = .copy
            NSColor.clear.setFill()
            dirtyRect.fill()
            context.restoreGraphicsState()
        }
        super.draw(dirtyRect)
    }

    /// Lays the visible text out at the width it will actually draw. Skips the work when that width is unchanged.
    func reflowToBounds() {
        guard let container = textContainer, let manager = layoutManager else { return }
        let target = tracksBoundsWidth ? bounds.width - textContainerInset.width * 2 : lockedWrapWidth
        guard target > 1, abs(container.containerSize.width - target) > 0.5 else { return }
        container.containerSize = NSSize(width: target, height: CGFloat.greatestFiniteMagnitude)
        let length = textStorage?.length ?? 0
        if length > 0 {
            manager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: length),
                actualCharacterRange: nil
            )
        }
        manager.ensureLayout(for: container)
    }

    /// Height and width for `width`, without touching the line fragments currently on screen.
    func measuredSize(fittingWidth width: CGFloat) -> CGSize {
        let usable = max(width, 1)
        let minHeight = (font?.pointSize ?? 16) + 2
        guard let storage = textStorage, storage.length > 0 else {
            return CGSize(width: 12, height: minHeight)
        }
        if measuring {
            return CGSize(width: usable, height: minHeight)
        }
        if let container = textContainer,
           let manager = layoutManager,
           container.containerSize.width > 1,
           abs(container.containerSize.width - usable) < 0.5 {
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container)
            return CGSize(width: max(ceil(used.width), 12), height: max(ceil(used.height), minHeight))
        }
        measuring = true
        defer { measuring = false }
        let measureStorage = NSTextStorage(attributedString: storage)
        let container = NSTextContainer(size: NSSize(width: usable, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        measureStorage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return CGSize(width: max(ceil(used.width), 12), height: max(ceil(used.height), minHeight))
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let start = mouseDownPoint ?? event.locationInWindow
        let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
        mouseDownPoint = nil
        let count = event.clickCount
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let selected = SelectionCopyAction.selectedString(in: self) ?? ""
            SelectionCopyAction.emit(selected, dragDistance: distance, clickCount: count)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
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
        ChatLinkActions.activate(url)
        return true
    }
}
