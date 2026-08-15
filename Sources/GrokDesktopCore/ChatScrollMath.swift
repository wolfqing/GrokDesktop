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
        let usable = max(track - thumb, 1)
        return min(max((locationY - thumb / 2) / usable, 0), 1)
    }
}
