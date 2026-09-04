import AppKit
import GrokDesktopCore
import SwiftUI

extension Notification.Name {
    static let grokCopyOnSelect = Notification.Name("GrokDesktop.copyOnSelect")
}

@MainActor
enum SelectionCopyAction {
    private static var lastText = ""
    private static var lastDate = Date.distantPast

    static func emit(
        _ text: String,
        dragDistance: CGFloat,
        clickCount: Int
    ) {
        guard SelectionCopyPolicy.shouldCopyOnMouseUp(
            dragDistance: dragDistance,
            clickCount: clickCount,
            selected: text
        ) else { return }
        let now = Date()
        if text == lastText, now.timeIntervalSince(lastDate) < 0.25 { return }
        lastText = text
        lastDate = now
        NotificationCenter.default.post(name: .grokCopyOnSelect, object: text)
    }

    static func selectedString(in textView: NSTextView) -> String? {
        SelectionCopyPolicy.substring(
            textView.string,
            location: textView.selectedRange().location,
            length: textView.selectedRange().length
        )
    }

    static func selectedString(in root: NSView, firstResponder: NSResponder?) -> String? {
        var preferred: String?
        var fallback: String?
        func consider(_ textView: NSTextView) {
            guard !textView.isEditable else { return }
            guard let text = selectedString(in: textView),
                  text.contains(where: { !$0.isWhitespace && !$0.isNewline }) else { return }
            if belongs(textView, to: root) {
                preferred = text
            } else if fallback == nil {
                fallback = text
            }
        }
        if let textView = firstResponder as? NSTextView {
            consider(textView)
        }
        if let window = root.window, let editor = window.fieldEditor(false, for: nil) as? NSTextView {
            consider(editor)
        }
        func walk(_ view: NSView) {
            if preferred != nil { return }
            if let textView = view as? NSTextView {
                consider(textView)
            }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        if preferred == nil, let window = root.window, let content = window.contentView {
            walk(content)
        }
        return preferred ?? fallback
    }

    private static func belongs(_ textView: NSTextView, to root: NSView) -> Bool {
        if textView.isDescendant(of: root) { return true }
        if textView.isFieldEditor, let host = textView.superview, host.isDescendant(of: root) {
            return true
        }
        return false
    }
}

struct CopyOnSelectMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> CopyOnSelectMonitorView {
        CopyOnSelectMonitorView()
    }

    func updateNSView(_ view: CopyOnSelectMonitorView, context: Context) {}
}

final class CopyOnSelectMonitorView: NSView {
    private var downPoint: NSPoint?
    private var clickCount = 1
    private var armed = false
    nonisolated(unsafe) private var token: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { remove() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    private func install() {
        remove()
        guard window != nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.handle(event)
            }
            return event
        }
    }

    private func remove() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }

    @MainActor
    private func handle(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        switch event.type {
        case .leftMouseDown:
            armed = shouldArm(event)
            downPoint = event.locationInWindow
            clickCount = event.clickCount
        case .leftMouseUp:
            guard armed else { return }
            armed = false
            let start = downPoint ?? event.locationInWindow
            let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            let count = max(event.clickCount, clickCount)
            downPoint = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let root = self.conversationRoot() else { return }
                guard let text = SelectionCopyAction.selectedString(in: root, firstResponder: window.firstResponder) else {
                    return
                }
                SelectionCopyAction.emit(text, dragDistance: distance, clickCount: count)
            }
        default:
            break
        }
    }

    private func shouldArm(_ event: NSEvent) -> Bool {
        guard let window, let content = window.contentView else { return false }
        if hitsScrollbar(content.hitTest(event.locationInWindow)) { return false }
        guard let root = conversationRoot() else { return false }
        let frame = root.convert(root.bounds, to: nil)
        return frame.contains(event.locationInWindow)
    }

    private func hitsScrollbar(_ view: NSView?) -> Bool {
        var current = view
        while let node = current {
            if node is ScrollKnobView { return true }
            current = node.superview
        }
        return false
    }

    private func conversationRoot() -> NSView? {
        if let scroll = enclosingScrollView { return scroll }
        var current: NSView? = self
        for _ in 0..<12 {
            if let scroll = current as? NSScrollView { return scroll }
            if let scroll = current?.enclosingScrollView { return scroll }
            current = current?.superview
        }
        return nil
    }
}
