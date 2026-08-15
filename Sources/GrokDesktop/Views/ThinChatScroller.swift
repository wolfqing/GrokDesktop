import AppKit

final class ThinChatScroller: NSScroller {
    var isDark = false

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        9
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 2 else { return }
        let width: CGFloat = 3
        let thumb = NSRect(
            x: ((bounds.width - width) / 2).rounded(.toNearestOrAwayFromZero),
            y: knob.minY,
            width: width,
            height: max(knob.height, 18)
        )
        let path = NSBezierPath(roundedRect: thumb, xRadius: width / 2, yRadius: width / 2)
        let alpha: CGFloat = usableParts == .noScrollerParts ? 0 : 0.38
        (isDark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()
        path.fill()
    }

    static func install(on scroll: NSScrollView, isDark: Bool) {
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.horizontalScrollElasticity = .automatic
        scroll.scrollerKnobStyle = isDark ? .light : .dark
        scroll.scrollerInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 2)

        let scroller: ThinChatScroller
        if let existing = scroll.verticalScroller as? ThinChatScroller {
            scroller = existing
        } else {
            scroller = ThinChatScroller()
            scroller.controlSize = .regular
            scroller.scrollerStyle = .overlay
            scroll.verticalScroller = scroller
        }
        scroller.isDark = isDark
        scroller.knobStyle = isDark ? .light : .dark
        scroller.needsDisplay = true
    }
}
