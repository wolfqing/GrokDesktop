import Foundation

public struct ReviewedFile: Equatable, Sendable {
    public var path: String
    public var baseline: String
    public var working: String
    public var accepted: Bool

    public init(path: String, baseline: String, working: String, accepted: Bool = false) {
        self.path = path
        self.baseline = baseline
        self.working = working
        self.accepted = accepted
    }
}

public enum DiffReview {
    public enum Action: String, Equatable, Sendable {
        case accept
        case reject
        case revert
    }

    public static func next(_ file: ReviewedFile, action: Action) -> ReviewedFile {
        var copy = file
        switch action {
        case .accept:
            copy.accepted = true
        case .reject, .revert:
            copy.working = file.baseline
            copy.accepted = false
        }
        return copy
    }

    /// Accept keeps the working bytes. Reject and revert write the baseline back.
    public static func apply(
        action: Action,
        files: [ReviewedFile],
        paths: [String],
        root: URL
    ) throws -> [ReviewedFile] {
        let chosen = Set(paths)
        return try files.map { file in
            guard chosen.contains(file.path) else { return file }
            let updated = next(file, action: action)
            let url = root.appendingPathComponent(updated.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = action == .accept ? updated.working : updated.baseline
            try text.write(to: url, atomically: true, encoding: .utf8)
            return updated
        }
    }

    /// Put these paths back to HEAD. A path that is not in HEAD is removed.
    /// Returns only the paths that are clean afterwards.
    public static func restore(paths: [String], root: URL) -> [String] {
        guard git(["rev-parse", "--is-inside-work-tree"], root: root).ok else { return [] }
        var done: [String] = []
        for path in paths where !path.isEmpty && staysInside(path, root: root) {
            if restoreOne(path, root: root), clean(path, root: root) {
                done.append(path)
            }
        }
        return done
    }

    private static func restoreOne(_ path: String, root: URL) -> Bool {
        if git(["cat-file", "-e", "HEAD:\(path)"], root: root).ok {
            return git(
                ["restore", "--source=HEAD", "--worktree", "--staged", "--", path],
                root: root
            ).ok
        }
        let url = root.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return false
            }
        }
        _ = git(["rm", "--cached", "--ignore-unmatch", "--", path], root: root)
        return true
    }

    private static func clean(_ path: String, root: URL) -> Bool {
        let status = git(["status", "--porcelain", "--", path], root: root)
        return status.ok && status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func staysInside(_ path: String, root: URL) -> Bool {
        let base = root.standardizedFileURL.path
        let url = root.appendingPathComponent(path).standardizedFileURL.path
        return url == base || url.hasPrefix(base + "/")
    }

    private static func git(_ args: [String], root: URL) -> ProcessCapture {
        TimedProcess.capture(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", root.path] + args,
            cwd: root
        )
    }
}
