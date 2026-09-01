import Foundation

public struct WorktreeRecord: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var branch: String
    public var name: String
    public var kind: String
    public var repo: String

    public init(path: String, branch: String = "", name: String = "", kind: String = "", repo: String = "") {
        self.path = path
        self.branch = branch
        self.name = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        self.kind = kind
        self.repo = repo
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

public enum WorktreeCatalog {
    public static func parse(_ text: String) -> [WorktreeRecord] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] {
            rows = array
        } else if let dict = object as? [String: Any] {
            rows = dict["worktrees"] as? [[String: Any]] ?? dict["trees"] as? [[String: Any]] ?? []
        } else {
            return []
        }
        return rows.compactMap { row in
            let path = row["path"] as? String
                ?? row["directory"] as? String
                ?? row["cwd"] as? String
                ?? ""
            guard !path.isEmpty else { return nil }
            return WorktreeRecord(
                path: path,
                branch: row["branch"] as? String ?? row["head"] as? String ?? "",
                name: row["name"] as? String ?? row["id"] as? String ?? "",
                kind: row["type"] as? String ?? row["kind"] as? String ?? "",
                repo: row["repo"] as? String ?? row["repository"] as? String ?? ""
            )
        }
    }

    public static func load(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL
    ) -> [WorktreeRecord] {
        guard let grok = locator.locate() else { return gitWorktrees(cwd: cwd) }
        let text = TimedProcess.run(
            executable: grok,
            arguments: ["worktree", "list", "--json", "--all"],
            cwd: cwd,
            timeout: 6,
            limitBytes: 500_000
        )
        let tracked = parse(text ?? "[]")
        if !tracked.isEmpty { return tracked }
        return gitWorktrees(cwd: cwd)
    }

    public static func gitWorktrees(cwd: URL) -> [WorktreeRecord] {
        guard let text = TimedProcess.git(cwd: cwd, ["worktree", "list", "--porcelain"], timeout: 4) else {
            return []
        }
        var records: [WorktreeRecord] = []
        var path = ""
        var branch = ""
        func flush() {
            guard !path.isEmpty else { return }
            records.append(WorktreeRecord(path: path, branch: branch))
            path = ""
            branch = ""
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "")
            } else if line.isEmpty {
                flush()
            }
        }
        flush()
        return records
    }

    public static func create(named name: String, cwd: URL) throws -> URL {
        let slug = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        guard !slug.isEmpty else { throw ACPError.rpc("Worktree name is empty") }
        let parent = cwd.deletingLastPathComponent()
        let dest = parent.appendingPathComponent("\(cwd.lastPathComponent)-\(slug)")
        if FileManager.default.fileExists(atPath: dest.path) {
            throw ACPError.rpc("Folder already exists: \(dest.path)")
        }
        let output = TimedProcess.git(
            cwd: cwd,
            ["worktree", "add", "-b", slug, dest.path, "HEAD"],
            timeout: 12
        )
        if output == nil, !FileManager.default.fileExists(atPath: dest.path) {
            throw ACPError.rpc("git worktree add failed")
        }
        return dest
    }
}
