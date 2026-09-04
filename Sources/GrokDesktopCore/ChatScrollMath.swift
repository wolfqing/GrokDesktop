import Foundation

public enum ChatScrollMath {
    public static func originY(
        progress: CGFloat,
        content: CGFloat,
        visible: CGFloat,
        flipped: Bool
    ) -> CGFloat {
        let travel = max(content - visible, 0)
        let offset = min(max(progress, 0), 1) * travel
        if flipped { return offset }
        return max(content - visible - offset, 0)
    }

    public static func progress(locationY: CGFloat, track: CGFloat, thumb: CGFloat) -> CGFloat {
        progress(locationY: locationY, grabOffset: thumb / 2, track: track, thumb: thumb)
    }

    public static func progress(
        locationY: CGFloat,
        grabOffset: CGFloat,
        track: CGFloat,
        thumb: CGFloat
    ) -> CGFloat {
        let usable = max(track - thumb, 1)
        return min(max((locationY - grabOffset) / usable, 0), 1)
    }

    public static func thumbTop(progress: CGFloat, track: CGFloat, thumb: CGFloat) -> CGFloat {
        min(max(progress, 0), 1) * max(track - thumb, 0)
    }

    public static func jumpChromeChanged(
        oldNearBottom: Bool,
        oldCanScroll: Bool,
        newNearBottom: Bool,
        newCanScroll: Bool
    ) -> Bool {
        oldNearBottom != newNearBottom || oldCanScroll != newCanScroll
    }
}
