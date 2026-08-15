import Foundation

public struct WorkspaceSnapshot: Equatable, Sendable {
    public var path: String
    public var name: String
    public var isRepo: Bool
    public var branch: String?
    public var insertions: Int
    public var deletions: Int
    public var remotes: [String]
    public var contextPercent: Int
    public var contextUsed: Int
    public var contextWindow: Int

    public init(
        path: String = "",
        name: String = "",
        isRepo: Bool = false,
        branch: String? = nil,
        insertions: Int = 0,
        deletions: Int = 0,
        remotes: [String] = [],
        contextPercent: Int = 0,
        contextUsed: Int = 0,
        contextWindow: Int = 0
    ) {
        self.path = path
        self.name = name
        self.isRepo = isRepo
        self.branch = branch
        self.insertions = insertions
        self.deletions = deletions
        self.remotes = remotes
        self.contextPercent = contextPercent
        self.contextUsed = contextUsed
        self.contextWindow = contextWindow
    }

    public static func load(cwd: URL, sessionDirectory: URL? = nil) -> WorkspaceSnapshot {
        var snap = WorkspaceSnapshot(path: cwd.path, name: cwd.lastPathComponent)
        snap.branch = TimedProcess.git(cwd: cwd, ["rev-parse", "--abbrev-ref", "HEAD"])
        snap.isRepo = snap.branch != nil
        if snap.isRepo {
            let numstat = TimedProcess.git(cwd: cwd, ["diff", "--numstat", "HEAD"]) ?? ""
            var plus = 0
            var minus = 0
            for line in numstat.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2 {
                    plus += Int(parts[0]) ?? 0
                    minus += Int(parts[1]) ?? 0
                }
            }
            snap.insertions = plus
            snap.deletions = minus
            let remotes = TimedProcess.git(cwd: cwd, ["remote", "-v"]) ?? ""
            var seen = Set<String>()
            for line in remotes.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 2 else { continue }
                let url = String(parts[1])
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "git@", with: "")
                    .replacingOccurrences(of: ".git", with: "")
                    .replacingOccurrences(of: ":", with: "/")
                if seen.insert(url).inserted {
                    snap.remotes.append(url)
                }
            }
        }
        if let sessionDirectory {
            let signals = sessionDirectory.appendingPathComponent("signals.json")
            if let data = try? Data(contentsOf: signals),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                snap.contextPercent = object["contextWindowUsage"] as? Int ?? 0
                snap.contextUsed = object["contextTokensUsed"] as? Int ?? 0
                snap.contextWindow = object["contextWindowTokens"] as? Int ?? 0
            }
        }
        return snap
    }
}
