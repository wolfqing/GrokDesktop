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
    var isNearBottom: Bool {
        ChatScrollMath.isNearBottom(offset: offset, visible: visible, content: content)
    }
    var userReleased: Bool {
        ChatScrollMath.userReleasedBottom(offset: offset, visible: visible, content: content)
    }
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
    var marks: [TurnRailMark] = [] {
        didSet { if marks != oldValue { needsDisplay = true } }
    }
    var previousLabel = ""
    var nextLabel = ""
    var onBegan: () -> Void = {}
    var onSeek: (CGFloat) -> Void = { _ in }
    var onEnded: (CGFloat) -> Void = { _ in }
    var onMark: (String) -> Void = { _ in }
    var onLatest: () -> Void = {}

    private var dragging = false {
        didSet { needsDisplay = true }
    }
    private var hovering = false {
        didSet { needsDisplay = true }
    }
    private var hoveredMarkID: String? {
        didSet { if hoveredMarkID != oldValue { needsDisplay = true } }
    }
    private var labelFrame: NSRect?
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
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard metrics.canScroll, let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if local.x >= bounds.width - 24 { return self }
        if let labelFrame, labelFrame.insetBy(dx: -6, dy: -4).contains(local) { return self }
        return nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard let local = localPoint(for: event, requireInside: true) else { return }
        refreshHover(at: local)
    }
    override func mouseExited(with event: NSEvent) {
        clearHover()
        labelFrame = nil
    }
    override func mouseMoved(with event: NSEvent) {
        guard let local = localPoint(for: event, requireInside: true) else {
            clearHover()
            return
        }
        refreshHover(at: local)
    }
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
        let rect = NSRect(x: bounds.width - width - 3, y: y, width: width, height: geometry.thumb)
        thumbColor(strong: dragging || hovering).setFill()
        NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
        let prompts = promptProgress(progress)
        let shown = cluster(progress: prompts)
        drawTicks(shown, progress: prompts)
    }

    private func thumbColor(strong: Bool) -> NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(strong ? 0.72 : 0.55)
            : NSColor.black.withAlphaComponent(strong ? 0.5 : 0.32)
    }

    private struct MarkCluster {
        var marks: [TurnRailMark]
        var centers: [CGFloat]
        var up: CGFloat
        var down: CGFloat
    }

    private func cluster(progress: CGFloat) -> MarkCluster {
        let active = TurnRail.activeID(marks: marks, progress: progress)
        let activeIndex = marks.firstIndex { $0.id == active } ?? 0
        let range = TurnRail.visibleIndices(
            count: marks.count,
            active: activeIndex,
            limit: TurnRail.capacity(height: bounds.height)
        )
        let shown = Array(marks[range])
        let centers = TurnRail.centers(count: shown.count, height: bounds.height)
        let up = (centers.first ?? bounds.height / 2) - TurnRail.pitch
        let down = (centers.last ?? bounds.height / 2) + TurnRail.pitch
        return MarkCluster(marks: shown, centers: centers, up: up, down: down)
    }

    private func drawTicks(_ cluster: MarkCluster, progress: CGFloat) {
        labelFrame = nil
        guard !cluster.marks.isEmpty else { return }
        let active = TurnRail.activeID(marks: marks, progress: progress)
        let right: CGFloat = bounds.width - 12
        var hovered: (TurnRailMark, CGFloat)?
        for (mark, y) in zip(cluster.marks, cluster.centers) {
            let emphasized = mark.id == active || mark.id == hoveredMarkID
            if mark.id == hoveredMarkID { hovered = (mark, y) }
            let tickWidth: CGFloat = emphasized ? 16 : 8
            let tickHeight: CGFloat = emphasized ? 2 : 1
            let rect = NSRect(x: right - tickWidth, y: y - tickHeight / 2, width: tickWidth, height: tickHeight)
            let alpha: CGFloat = mark.id == hoveredMarkID ? 1 : (mark.id == active ? 0.92 : 0.38)
            let color = isDark
                ? NSColor.white.withAlphaComponent(alpha)
                : NSColor.black.withAlphaComponent(emphasized ? 0.78 : 0.28)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
        drawChevron(up: true, at: cluster.up, enabled: TurnRail.step(marks: marks, progress: progress, forward: false) != nil)
        drawChevron(up: false, at: cluster.down, enabled: TurnRail.step(marks: marks, progress: progress, forward: true) != nil)
        if let hovered {
            drawLabel(hovered.0.label, tickY: hovered.1, tickLeft: right - 16)
        }
    }

    private func drawLabel(_ text: String, tickY: CGFloat, tickLeft: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let color = isDark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.86)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let measured = (text as NSString).size(withAttributes: attributes)
        let width = min(max(measured.width + 16, 36), 200)
        let height: CGFloat = 22
        var rect = NSRect(x: tickLeft - 8 - width, y: tickY - height / 2, width: width, height: height)
        if rect.minX < 4 { rect.origin.x = 4 }
        labelFrame = rect
        let fill = isDark
            ? NSColor(calibratedWhite: 0.16, alpha: 0.96)
            : NSColor(calibratedWhite: 0.97, alpha: 0.96)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let stroke = isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.1)
        stroke.setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).stroke()
        (text as NSString).draw(in: rect.insetBy(dx: 8, dy: 3), withAttributes: attributes)
    }

    private func drawChevron(up: Bool, at centerY: CGFloat, enabled: Bool) {
        guard centerY > 6, centerY < bounds.height - 6 else { return }
        let alpha: CGFloat = enabled ? 0.78 : 0.34
        let color = isDark
            ? NSColor.white.withAlphaComponent(alpha)
            : NSColor.black.withAlphaComponent(enabled ? 0.62 : 0.22)
        color.setFill()
        let midX = bounds.width - 16
        let tipY = up ? centerY - 2.5 : centerY + 2.5
        let baseY = up ? centerY + 2.5 : centerY - 2.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: midX, y: tipY))
        path.line(to: NSPoint(x: midX - 3.5, y: baseY))
        path.line(to: NSPoint(x: midX + 3.5, y: baseY))
        path.close()
        path.fill()
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
            guard let local = localPoint(for: event, requireInside: true), hitsRail(local) else { return false }
            if activate(at: local) { return true }
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
        let inset: CGFloat = 16
        let track = max(bounds.height - inset * 2, 1)
        let thumb = min(max(metrics.visible / max(metrics.content, 1) * track, 28), track)
        return (inset, track, thumb)
    }

    private func currentProgress() -> CGFloat {
        dragging ? dragProgress : metrics.progress
    }

    /// Prompt marks live on the transcript scale. Scroll progress does not.
    private func promptProgress(_ scrollProgress: CGFloat) -> CGFloat {
        TurnRail.markSpace(
            scrollProgress: scrollProgress,
            content: metrics.content,
            visible: metrics.visible
        )
    }

    /// Chevrons and prompt ticks jump. The thumb still drags.
    private func activate(at point: NSPoint) -> Bool {
        guard hitsRail(point) else { return false }
        let scroll = currentProgress()
        let progress = promptProgress(scroll)
        let shown = cluster(progress: progress)
        guard !shown.marks.isEmpty else { return false }
        if point.x >= bounds.width - 28, abs(point.y - shown.up) <= 10 {
            if let id = TurnRail.step(marks: marks, progress: progress, forward: false) {
                onMark(id)
            }
            return true
        }
        if point.x >= bounds.width - 28, abs(point.y - shown.down) <= 10 {
            if let id = TurnRail.step(marks: marks, progress: progress, forward: true) {
                onMark(id)
            } else if scroll < 0.98 {
                onLatest()
            }
            return true
        }
        if labelContains(point), let id = hoveredMarkID {
            onMark(id)
            return true
        }
        if thumbContains(point) { return false }
        if let mark = mark(at: point, cluster: shown) {
            onMark(mark.id)
            return true
        }
        return false
    }

    private func thumbContains(_ point: NSPoint) -> Bool {
        let geometry = trackGeometry()
        let y = geometry.inset + ChatScrollMath.thumbTop(
            progress: currentProgress(),
            track: geometry.track,
            thumb: geometry.thumb
        )
        let rect = NSRect(x: bounds.width - 14, y: y, width: 14, height: geometry.thumb)
        return rect.contains(point)
    }

    /// The overlay is wide enough for the hover label. Only the gutter and that label take clicks.
    private func hitsRail(_ point: NSPoint) -> Bool {
        if point.x >= bounds.width - 28 { return true }
        return labelContains(point)
    }

    private func labelContains(_ point: NSPoint) -> Bool {
        guard let labelFrame else { return false }
        return labelFrame.insetBy(dx: -6, dy: -4).contains(point)
    }

    private func refreshHover(at local: NSPoint) {
        let onRail = local.x >= bounds.width - 28
        if !dragging { hovering = onRail }
        guard onRail || labelContains(local) else {
            if hoveredMarkID != nil { hoveredMarkID = nil }
            if toolTip != nil { toolTip = nil }
            return
        }
        if labelContains(local) { return }
        let shown = cluster(progress: promptProgress(currentProgress()))
        hoveredMarkID = mark(at: local, cluster: shown)?.id
        let tip = tip(at: local, cluster: shown)
        if toolTip != tip { toolTip = tip }
    }

    private func clearHover() {
        if !dragging { hovering = false }
        if hoveredMarkID != nil { hoveredMarkID = nil }
        if toolTip != nil { toolTip = nil }
    }

    private func mark(at point: NSPoint, cluster: MarkCluster) -> TurnRailMark? {
        var best: (TurnRailMark, CGFloat)?
        for (mark, y) in zip(cluster.marks, cluster.centers) {
            let distance = abs(point.y - y)
            guard distance <= TurnRail.pitch / 2 + 2 else { continue }
            if best == nil || distance < best!.1 {
                best = (mark, distance)
            }
        }
        return best?.0
    }

    private func tip(at point: NSPoint, cluster: MarkCluster) -> String? {
        if abs(point.y - cluster.up) <= 10 { return previousLabel.isEmpty ? nil : previousLabel }
        if abs(point.y - cluster.down) <= 10 { return nextLabel.isEmpty ? nil : nextLabel }
        if mark(at: point, cluster: cluster) != nil { return nil }
        return nil
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
    var marks: [TurnRailMark] = []
    var isDark: Bool
    var previousLabel = ""
    var nextLabel = ""
    var driver: ChatScrollDriver? = nil
    var onBegan: () -> Void = {}
    var onSeek: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void = { _ in }
    var onMark: (String) -> Void = { _ in }
    var onLatest: () -> Void = {}

    func makeNSView(context: Context) -> ScrollKnobView {
        let view = ScrollKnobView()
        driver?.knob = view
        apply(view, includeMetrics: true)
        return view
    }

    func updateNSView(_ view: ScrollKnobView, context: Context) {
        driver?.knob = view
        apply(view, includeMetrics: driver?.scroll == nil)
    }

    private func apply(_ view: ScrollKnobView, includeMetrics: Bool) {
        if includeMetrics {
            view.metrics = metrics
        }
        view.marks = marks
        view.isDark = isDark
        view.previousLabel = previousLabel
        view.nextLabel = nextLabel
        view.onBegan = onBegan
        view.onSeek = onSeek
        view.onEnded = onEnded
        view.onMark = onMark
        view.onLatest = onLatest
    }
}

@MainActor
final class ChatScrollDriver {
    weak var scroll: NSScrollView?
    weak var knob: ScrollKnobView?

    func attach(_ scroll: NSScrollView) {
        let changed = self.scroll !== scroll
        self.scroll = scroll
        if changed {
            ThinChatScroller.stripSystemScrollers(on: scroll)
        }
    }

    func update(metrics: ChatScrollMetrics, isDark: Bool) {
        knob?.metrics = metrics
        knob?.isDark = isDark
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
