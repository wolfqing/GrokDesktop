import AppKit
import SwiftUI

struct PromptEditor: View {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 14
    var minLines: Int = 1
    var maxLines: Int = 4
    var onSubmit: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let line = PromptLineMetrics.lineHeight(for: fontSize)
        let minHeight = line * CGFloat(max(minLines, 1)) + 2
        let maxHeight = line * CGFloat(max(maxLines, 1)) + 2
        PromptEditorView(
            text: $text,
            placeholder: placeholder,
            fontSize: fontSize,
            textColor: NSColor(palette.text),
            placeholderColor: NSColor(palette.secondary),
            minLines: minLines,
            maxLines: maxLines,
            onSubmit: onSubmit
        )
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PromptEditorView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var textColor: NSColor
    var placeholderColor: NSColor
    var minLines: Int
    var maxLines: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> PromptScrollView {
        let font = NSFont.systemFont(ofSize: fontSize)
        let scroll = PromptScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.focusRingType = .none
        scroll.usesPredominantAxisScrolling = true
        scroll.contentView.drawsBackground = false
        scroll.contentView.backgroundColor = .clear
        scroll.setContentHuggingPriority(.required, for: .vertical)
        scroll.setContentCompressionResistancePriority(.required, for: .vertical)
        scroll.lineMetrics = PromptLineMetrics(font: font, minLines: minLines, maxLines: maxLines)

        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.placeholder = placeholder
        textView.placeholderColor = placeholderColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.focusRingType = .none
        textView.insertionPointColor = textColor
        textView.string = text

        scroll.documentView = textView
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateNSView(_ scroll: PromptScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        let font = NSFont.systemFont(ofSize: fontSize)
        scroll.lineMetrics = PromptLineMetrics(font: font, minLines: minLines, maxLines: maxLines)
        guard let textView = scroll.documentView as? PromptTextView else { return }
        textView.font = font
        textView.textColor = textColor
        textView.placeholder = placeholder
        textView.placeholderColor = placeholderColor
        textView.insertionPointColor = textColor
        if !textView.hasMarkedText(), textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, end), length: 0))
        }
        textView.needsDisplay = true
        scroll.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptScrollView, context: Context) -> CGSize {
        let width = proposal.width ?? (nsView.bounds.width > 1 ? nsView.bounds.width : 400)
        let measured = nsView.measuredSize(forWidth: max(width, 10))
        let maxHeight = nsView.lineMetrics.height(for: nsView.lineMetrics.maxLines)
        return CGSize(width: width, height: min(measured.height, maxHeight))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        weak var scroll: PromptScrollView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if !textView.hasMarkedText() {
                text.wrappedValue = textView.string
            }
            textView.needsDisplay = true
            scroll?.invalidateIntrinsicContentSize()
            textView.scrollRangeToVisible(textView.selectedRange())
            scroll?.superview?.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() { return false }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                onSubmit()
                return true
            }
            return false
        }
    }
}

private struct PromptLineMetrics {
    var font: NSFont
    var minLines: Int
    var maxLines: Int

    static func lineHeight(for fontSize: CGFloat) -> CGFloat {
        lineHeight(for: NSFont.systemFont(ofSize: fontSize))
    }

    static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(max(font.boundingRectForFont.height, font.ascender - font.descender + font.leading, 16))
    }

    var lineHeight: CGFloat {
        Self.lineHeight(for: font)
    }

    func height(for lines: Int) -> CGFloat {
        max(lineHeight * CGFloat(max(lines, 1)) + 2, lineHeight)
    }
}

private final class PromptScrollView: NSScrollView {
    var lineMetrics = PromptLineMetrics(font: .systemFont(ofSize: 14), minLines: 1, maxLines: 4)

    override var intrinsicContentSize: NSSize {
        measuredSize(forWidth: bounds.width > 1 ? bounds.width : 320)
    }

    func measuredSize(forWidth width: CGFloat) -> CGSize {
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer,
              let manager = textView.layoutManager
        else {
            return CGSize(width: width, height: lineMetrics.height(for: lineMetrics.minLines))
        }
        let usable = max(width, 10)
        if abs(textView.frame.width - usable) > 0.5 {
            textView.frame.size.width = usable
        }
        container.containerSize = NSSize(width: usable, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let inset = textView.textContainerInset.height * 2
        let content = ceil(used.height + inset)
        let minHeight = lineMetrics.height(for: lineMetrics.minLines)
        let maxHeight = lineMetrics.height(for: lineMetrics.maxLines)
        let documentHeight = max(content, minHeight)
        if abs(textView.frame.height - documentHeight) > 0.5 {
            textView.frame.size.height = documentHeight
        }
        let height = min(documentHeight, maxHeight)
        verticalScrollElasticity = documentHeight > maxHeight + 0.5 ? .automatic : .none
        return CGSize(width: usable, height: height)
    }

    override func scrollWheel(with event: NSEvent) {
        let visible = contentView.bounds.height
        let content = documentView?.bounds.height ?? 0
        if content > visible + 0.5 {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

private final class PromptTextView: NSTextView {
    var placeholder = ""
    var placeholderColor: NSColor = .placeholderTextColor

    override var intrinsicContentSize: NSSize {
        enclosingScrollView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        let inset = textContainerInset
        let pad = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: inset.width + pad,
            y: inset.height,
            width: max(bounds.width - (inset.width + pad) * 2, 0),
            height: bounds.height - inset.height * 2
        )
        placeholder.draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: placeholderColor
            ]
        )
    }

    override func scrollWheel(with event: NSEvent) {
        if let scroll = enclosingScrollView as? PromptScrollView {
            scroll.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
