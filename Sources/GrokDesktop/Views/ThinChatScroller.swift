import AppKit

enum ThinChatScroller {
    @MainActor
    static func hideSystemScrollers(on scroll: NSScrollView) {
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScroller?.isHidden = true
        scroll.horizontalScroller?.isHidden = true
        scroll.verticalScroller?.alphaValue = 0
        scroll.horizontalScroller?.alphaValue = 0
        scroll.scrollerInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    }
}
