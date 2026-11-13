import Foundation

public enum WorktreeSwitch {
    /// One listed worktree becomes the session cwd. An unknown path is refused.
    public static func cwd(current: String, worktrees: [WorktreeRecord], selected: String) -> String? {
        let wanted = URL(fileURLWithPath: selected).standardizedFileURL.path
        guard let match = worktrees.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == wanted
        }) else { return nil }
        _ = current
        return match.path
    }
}
