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

    public static let jumpSlack: CGFloat = 56
    public static let releaseSlack: CGFloat = 8

    public static func distanceFromBottom(offset: CGFloat, visible: CGFloat, content: CGFloat) -> CGFloat {
        max(content - offset - visible, 0)
    }

    public static func isNearBottom(offset: CGFloat, visible: CGFloat, content: CGFloat) -> Bool {
        distanceFromBottom(offset: offset, visible: visible, content: content) <= jumpSlack
    }

    public static func userReleasedBottom(offset: CGFloat, visible: CGFloat, content: CGFloat) -> Bool {
        distanceFromBottom(offset: offset, visible: visible, content: content) > releaseSlack
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

public struct TurnRailMark: Equatable, Sendable {
    public var id: String
    public var progress: CGFloat
    public var label: String

    public init(id: String, progress: CGFloat, label: String) {
        self.id = id
        self.progress = progress
        self.label = label
    }
}

public enum TurnRail {
    public static func progress(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(count - 1)
    }

    /// The mark at the viewport, or the nearest one above it.
    public static func activeID(marks: [TurnRailMark], progress: CGFloat) -> String? {
        marks.last { $0.progress <= progress + 0.012 }?.id ?? marks.first?.id
    }

    /// Next user turn below the viewport, or the previous one above it.
    public static func step(marks: [TurnRailMark], progress: CGFloat, forward: Bool) -> String? {
        let epsilon: CGFloat = 0.012
        if forward {
            return marks.first { $0.progress > progress + epsilon }?.id
        }
        return marks.last { $0.progress < progress - epsilon }?.id
    }
}
