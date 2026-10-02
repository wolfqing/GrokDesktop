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
    /// Fixed gap between prompt ticks, in points. The cluster stays centered at this pitch
    /// instead of stretching each prompt along the scrollbar.
    public static let pitch: CGFloat = 16

    public static func progress(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(count - 1)
    }

    /// How many ticks fit in a short band in the middle of `height`.
    public static func capacity(height: CGFloat, pitch: CGFloat = TurnRail.pitch) -> Int {
        let band = min(max(height - 36, pitch), 220)
        return max(Int((band / pitch).rounded(.down)) + 1, 1)
    }

    /// Ticks around the current prompt. A short chat shows every prompt.
    public static func visibleIndices(count: Int, active: Int, limit: Int) -> Range<Int> {
        guard count > 0, limit > 0 else { return 0..<0 }
        if count <= limit { return 0..<count }
        let current = min(max(active, 0), count - 1)
        var start = current - (limit - 1) / 2
        var end = start + limit
        if start < 0 {
            start = 0
            end = limit
        } else if end > count {
            end = count
            start = count - limit
        }
        return start..<end
    }

    /// Fixed-pitch centers. The group sits in the middle of `height`.
    public static func centers(count: Int, height: CGFloat, pitch: CGFloat = TurnRail.pitch) -> [CGFloat] {
        guard count > 0 else { return [] }
        let span = pitch * CGFloat(count - 1)
        let origin = (height - span) / 2
        return (0..<count).map { origin + CGFloat($0) * pitch }
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
