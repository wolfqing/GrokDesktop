import Foundation

public enum SelectionCopyPolicy {
    public static let dragThreshold: CGFloat = 4

    /// Copy on mouse-up when the user dragged out a range, or double/triple-clicked a word/line.
    public static func shouldCopyOnMouseUp(
        dragDistance: CGFloat,
        clickCount: Int,
        selected: String
    ) -> Bool {
        guard selected.contains(where: { !$0.isWhitespace && !$0.isNewline }) else { return false }
        if clickCount >= 2 { return true }
        return dragDistance >= dragThreshold
    }

    public static func substring(_ string: String, location: Int, length: Int) -> String? {
        guard location >= 0, length > 0 else { return nil }
        let ns = string as NSString
        guard location + length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: location, length: length))
    }
}
