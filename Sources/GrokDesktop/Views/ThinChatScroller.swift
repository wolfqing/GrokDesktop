import AppKit

final class InvisibleChatScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        0
    }

    override func draw(_ dirtyRect: NSRect) {}
    override func drawKnob() {}
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override var intrinsicContentSize: NSSize { .zero }
}

enum ThinChatScroller {
    @MainActor
    static func hideSystemScrollers(on scroll: NSScrollView) {
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.scrollerInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
        if !(scroll.verticalScroller is InvisibleChatScroller) {
            let scroller = InvisibleChatScroller()
            scroller.scrollerStyle = .overlay
            scroller.isHidden = true
            scroller.alphaValue = 0
            scroll.verticalScroller = scroller
        }
        hideAllScrollers(in: scroll)
    }

    @MainActor
    static func hideAllScrollers(in view: NSView) {
        if let scroller = view as? NSScroller {
            scroller.isHidden = true
            scroller.alphaValue = 0
            scroller.wantsLayer = true
            scroller.layer?.opacity = 0
        }
        for child in view.subviews {
            hideAllScrollers(in: child)
        }
    }
}
