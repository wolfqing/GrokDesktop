import AppKit
import GrokDesktopCore
import SwiftUI

struct ChatScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var visible: CGFloat = 0
    var content: CGFloat = 0

    var canScroll: Bool { content > visible + 12 }
    var travel: CGFloat { max(content - visible, 1) }
    var progress: CGFloat { min(max(offset / travel, 0), 1) }
    var isNearBottom: Bool { content - (offset + visible) <= 56 }
}

final class ScrollKnobView: NSView {
    var metrics = ChatScrollMetrics() {
        didSet {
            if !dragging { needsDisplay = true }
        }
    }
    var isDark = false {
        didSet { needsDisplay = true }
    }
    var onBegan: () -> Void = {}
    var onSeek: (CGFloat) -> Void = { _ in }
    var onEnded: (CGFloat) -> Void = { _ in }

    private var dragging = false {
        didSet { needsDisplay = true }
    }
    private var hovering = false {
        didSet { needsDisplay = true }
    }
    private var grabOffset: CGFloat = 0
    private var dragProgress: CGFloat = 0
    nonisolated(unsafe) private var monitor: Any?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
        updateTrackingAreas()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { removeMonitor() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard metrics.canScroll, bounds.contains(point) else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { if !dragging { hovering = false } }
    override func mouseDown(with event: NSEvent) { _ = consume(event) }
    override func mouseDragged(with event: NSEvent) { _ = consume(event) }
    override func mouseUp(with event: NSEvent) { _ = consume(event) }

    override func draw(_ dirtyRect: NSRect) {
        guard metrics.canScroll || dragging else { return }
        let geometry = trackGeometry()
        let progress = dragging ? dragProgress : metrics.progress
        let y = geometry.inset + ChatScrollMath.thumbTop(
            progress: progress,
            track: geometry.track,
            thumb: geometry.thumb
        )
        let width: CGFloat = (dragging || hovering) ? 6 : 4
        let rect = NSRect(x: (bounds.width - width) / 2, y: y, width: width, height: geometry.thumb)
        let color = isDark
            ? NSColor.white.withAlphaComponent(dragging || hovering ? 0.50 : 0.32)
            : NSColor.black.withAlphaComponent(dragging || hovering ? 0.38 : 0.22)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
    }

    private func installMonitor() {
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.consume(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    @discardableResult
    private func consume(_ event: NSEvent) -> Bool {
        guard window != nil, metrics.canScroll || dragging else { return false }
        switch event.type {
        case .leftMouseDown:
            guard let local = localPoint(for: event, requireInside: true) else { return false }
            beginDrag(at: local)
            return true
        case .leftMouseDragged:
            guard dragging, let local = localPoint(for: event, requireInside: false) else { return false }
            updateDrag(at: local)
            return true
        case .leftMouseUp:
            guard dragging else { return false }
            if let local = localPoint(for: event, requireInside: false) {
                updateDrag(at: local)
            }
            endDrag()
            return true
        default:
            return false
        }
    }

    /// Window-space hit test. SwiftUI hosting flips/transforms the representable,
    /// so `convert(_:from: nil)` + `bounds.contains` often misses even when hover works.
    private func localPoint(for event: NSEvent, requireInside: Bool) -> NSPoint? {
        let frame = convert(bounds, to: nil)
        let p = event.locationInWindow
        let slop: CGFloat = 8
        if requireInside {
            let hit = NSRect(
                x: frame.minX - slop,
                y: frame.minY - slop,
                width: frame.width + slop * 2,
                height: frame.height + slop * 2
            )
            guard hit.contains(p) else { return nil }
        }
        let yFromTop = frame.maxY - p.y
        return NSPoint(x: p.x - frame.minX, y: yFromTop)
    }

    private func trackGeometry() -> (inset: CGFloat, track: CGFloat, thumb: CGFloat) {
        let inset: CGFloat = 8
        let track = max(bounds.height - inset * 2, 1)
        let thumb = min(max(metrics.visible / max(metrics.content, 1) * track, 28), track)
        return (inset, track, thumb)
    }

    private func beginDrag(at point: NSPoint) {
        let geometry = trackGeometry()
        let thumbTop = geometry.inset + ChatScrollMath.thumbTop(
            progress: metrics.progress,
            track: geometry.track,
            thumb: geometry.thumb
        )
        let onThumb = point.y >= thumbTop && point.y <= thumbTop + geometry.thumb
        grabOffset = onThumb ? point.y - thumbTop : geometry.thumb / 2
        dragging = true
        onBegan()
        updateDrag(at: point)
    }

    private func updateDrag(at point: NSPoint) {
        let geometry = trackGeometry()
        dragProgress = ChatScrollMath.progress(
            locationY: point.y - geometry.inset,
            grabOffset: grabOffset,
            track: geometry.track,
            thumb: geometry.thumb
        )
        needsDisplay = true
        onSeek(dragProgress)
    }

    private func endDrag() {
        let progress = dragProgress
        dragging = false
        onEnded(progress)
        needsDisplay = true
    }
}

struct OverlayScrollbar: NSViewRepresentable {
    var metrics: ChatScrollMetrics
    var isDark: Bool
    var onBegan: () -> Void = {}
    var onSeek: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ScrollKnobView {
        let view = ScrollKnobView()
        apply(view)
        return view
    }

    func updateNSView(_ view: ScrollKnobView, context: Context) {
        apply(view)
    }

    private func apply(_ view: ScrollKnobView) {
        view.metrics = metrics
        view.isDark = isDark
        view.onBegan = onBegan
        view.onSeek = onSeek
        view.onEnded = onEnded
    }
}

@MainActor
final class ChatScrollDriver {
    weak var scroll: NSScrollView?

    func attach(_ scroll: NSScrollView) {
        self.scroll = scroll
        ThinChatScroller.stripSystemScrollers(on: scroll)
    }

    func update(metrics: ChatScrollMetrics, isDark: Bool) {
        if let scroll {
            ThinChatScroller.stripSystemScrollers(on: scroll)
        }
    }

    func seek(to progress: CGFloat) {
        guard let scroll else { return }
        let clip = scroll.contentView
        guard let document = clip.documentView else { return }
        let y = ChatScrollMath.originY(
            progress: progress,
            content: max(document.bounds.height, clip.bounds.height),
            visible: max(clip.bounds.height, 1),
            flipped: document.isFlipped
        )
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(clip)
        NSAnimationContext.endGrouping()
    }
}

enum ThinChatScroller {
    @MainActor
    static func stripSystemScrollers(on scroll: NSScrollView) {
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScroller = nil
        scroll.verticalScroller = nil
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.scrollerInsets = NSEdgeInsets()
        if let clip = scroll.contentView as NSClipView? {
            clip.drawsBackground = false
            clip.backgroundColor = .clear
        }
        hideIndicatorViews(in: scroll, owner: scroll)
        if let parent = scroll.superview {
            hideIndicatorViews(in: parent, owner: scroll)
        }
    }

    @MainActor
    private static func hideIndicatorViews(in view: NSView, owner: NSScrollView) {
        if view is ScrollKnobView { return }
        if let other = view as? NSScrollView, other !== owner { return }

        let name = String(describing: type(of: view))
        let looksLikeSystemBar =
            view is NSScroller
            || name.localizedCaseInsensitiveContains("indicator")
            || name.localizedCaseInsensitiveContains("scroller")
            || name.localizedCaseInsensitiveContains("scrollbar")
        if looksLikeSystemBar, !containsKnob(view) {
            view.isHidden = true
            view.alphaValue = 0
            view.wantsLayer = true
            view.layer?.opacity = 0
            view.layer?.borderWidth = 0
            view.layer?.borderColor = NSColor.clear.cgColor
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.shadowOpacity = 0
        }
        hideIndicatorLayers(view.layer)
        for child in view.subviews {
            hideIndicatorViews(in: child, owner: owner)
        }
    }

    @MainActor
    private static func containsKnob(_ view: NSView) -> Bool {
        if view is ScrollKnobView { return true }
        return view.subviews.contains(where: containsKnob)
    }

    @MainActor
    private static func hideIndicatorLayers(_ layer: CALayer?) {
        guard let layer else { return }
        let name = layer.name ?? String(describing: type(of: layer))
        if name.localizedCaseInsensitiveContains("indicator")
            || name.localizedCaseInsensitiveContains("scroller")
            || name.localizedCaseInsensitiveContains("scrollbar")
            || name.localizedCaseInsensitiveContains("slot")
            || name.localizedCaseInsensitiveContains("track") {
            layer.opacity = 0
            layer.borderWidth = 0
            layer.borderColor = NSColor.clear.cgColor
            layer.backgroundColor = NSColor.clear.cgColor
            layer.shadowOpacity = 0
        }
        for child in layer.sublayers ?? [] {
            hideIndicatorLayers(child)
        }
    }
}
