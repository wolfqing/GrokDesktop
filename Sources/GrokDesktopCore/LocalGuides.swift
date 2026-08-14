import Foundation

public struct LocalGuide: Identifiable, Equatable, Sendable {
    public var id: String { filename }
    public var filename: String
    public var title: String
    public var url: URL

    public init(filename: String, title: String, url: URL) {
        self.filename = filename
        self.title = title
        self.url = url
    }
}

public enum LocalGuides {
    public static func directory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        home.appendingPathComponent("docs/user-guide")
    }

    public static func all(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> [LocalGuide] {
        let root = directory(home: home)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let filename = url.lastPathComponent
                return LocalGuide(filename: filename, title: displayTitle(filename), url: url)
            }
            .sorted { $0.filename < $1.filename }
    }

    public static func tutorial(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> [LocalGuide] {
        let allGuides = all(home: home)
        let topics: [(String, String)] = [
            ("01-getting-started.md", "Your first prompt"),
            ("01-getting-started.md", "Attaching context"),
            ("03-keyboard-shortcuts.md", "Navigation"),
            ("04-slash-commands.md", "Slash commands"),
            ("17-sessions.md", "Worktrees and sessions"),
            ("19-plan-mode.md", "Plan mode"),
            ("05-configuration.md", "Customization"),
            ("08-skills.md", "Switching from another agent")
        ]
        return topics.compactMap { filename, title in
            guard let guide = allGuides.first(where: { $0.filename == filename }) else { return nil }
            return LocalGuide(filename: "\(filename)#\(title)", title: title, url: guide.url)
        }
    }

    public static func match(
        _ query: String,
        in guides: [LocalGuide]
    ) -> LocalGuide? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = guides.first(where: {
            $0.title.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                || $0.filename.compare(needle, options: .caseInsensitive) == .orderedSame
        }) {
            return exact
        }
        return guides.first {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.filename.localizedCaseInsensitiveContains(needle)
        }
    }

    public static func displayTitle(_ filename: String) -> String {
        var stem = filename
        if stem.lowercased().hasSuffix(".md") {
            stem = String(stem.dropLast(3))
        }
        if let regex = try? NSRegularExpression(pattern: #"^\d+-"#),
           let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..<stem.endIndex, in: stem)),
           let range = Range(match.range, in: stem) {
            stem.removeSubrange(range)
        }
        return stem
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

public struct ClaudeMCPImport: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var transport: String
    public var commandOrURL: String
    public var args: [String]

    public init(name: String, transport: String, commandOrURL: String, args: [String]) {
        self.name = name
        self.transport = transport
        self.commandOrURL = commandOrURL
        self.args = args
    }
}

public struct ClaudeImportSnapshot: Equatable, Sendable {
    public var exists: Bool
    public var files: [String]
    public var servers: [ClaudeMCPImport]
    public var envKeys: [String]
    public var permissionAllow: Int
    public var permissionDeny: Int
    public var hookNames: [String]
    public var report: String

    public init(
        exists: Bool = false,
        files: [String] = [],
        servers: [ClaudeMCPImport] = [],
        envKeys: [String] = [],
        permissionAllow: Int = 0,
        permissionDeny: Int = 0,
        hookNames: [String] = [],
        report: String = ""
    ) {
        self.exists = exists
        self.files = files
        self.servers = servers
        self.envKeys = envKeys
        self.permissionAllow = permissionAllow
        self.permissionDeny = permissionDeny
        self.hookNames = hookNames
        self.report = report
    }

    public static func discover(
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
        claudeJSON: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    ) -> ClaudeImportSnapshot {
        let fm = FileManager.default
        var files: [String] = []
        var servers: [ClaudeMCPImport] = []
        var envKeys: [String] = []
        var allow = 0
        var deny = 0
        var hooks: [String] = []

        if fm.fileExists(atPath: claudeJSON.path) {
            files.append("~/.claude.json")
            if let data = try? Data(contentsOf: claudeJSON),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                servers.append(contentsOf: parseMCP(object["mcpServers"]))
            }
        }

        let settingsURL = claudeHome.appendingPathComponent("settings.json")
        if fm.fileExists(atPath: settingsURL.path) {
            files.append("~/.claude/settings.json")
            if let data = try? Data(contentsOf: settingsURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let env = object["env"] as? [String: Any] {
                    envKeys = env.keys.sorted()
                }
                if let permissions = object["permissions"] as? [String: Any] {
                    allow = countList(permissions["allow"])
                    deny = countList(permissions["deny"])
                }
                hooks = hookKeys(object["hooks"])
                servers.append(contentsOf: parseMCP(object["mcpServers"]))
            }
        }

        if fm.fileExists(atPath: claudeHome.appendingPathComponent("CLAUDE.md").path) {
            files.append("~/.claude/CLAUDE.md")
        }

        var unique: [ClaudeMCPImport] = []
        var seen = Set<String>()
        for server in servers where seen.insert(server.name).inserted {
            unique.append(server)
        }

        let exists = !files.isEmpty
        var lines: [String] = []
        if exists {
            lines.append("Found Claude config:")
            lines.append(contentsOf: files.map { "  \($0)" })
            lines.append("")
            if unique.isEmpty {
                lines.append("MCP servers: none")
            } else {
                lines.append("MCP servers:")
                lines.append(contentsOf: unique.map { "  \($0.name) · \($0.transport) · \($0.commandOrURL)" })
            }
            lines.append("")
            lines.append("Environment keys: \(envKeys.isEmpty ? "none" : envKeys.joined(separator: ", "))")
            lines.append("Permissions: allow \(allow), deny \(deny)")
            lines.append("Hooks: \(hooks.isEmpty ? "none" : hooks.joined(separator: ", "))")
            lines.append("")
            lines.append("Import copies MCP servers into grok via `grok mcp add`.")
            lines.append("Permissions, env, and hooks stay in the report; send /import-claude if you want Grok to finish the rest.")
        } else {
            lines.append("No ~/.claude.json or ~/.claude/settings.json found.")
        }

        return ClaudeImportSnapshot(
            exists: exists,
            files: files,
            servers: unique,
            envKeys: envKeys,
            permissionAllow: allow,
            permissionDeny: deny,
            hookNames: hooks,
            report: lines.joined(separator: "\n")
        )
    }

    private static func parseMCP(_ raw: Any?) -> [ClaudeMCPImport] {
        guard let dict = raw as? [String: Any] else { return [] }
        return dict.keys.sorted().compactMap { name in
            guard let body = dict[name] as? [String: Any] else { return nil }
            let type = (body["type"] as? String ?? body["transport"] as? String ?? "stdio").lowercased()
            if let url = body["url"] as? String, !url.isEmpty {
                let transport = (type == "sse") ? "sse" : "http"
                return ClaudeMCPImport(name: name, transport: transport, commandOrURL: url, args: [])
            }
            let command = body["command"] as? String ?? ""
            let args = body["args"] as? [String] ?? []
            guard !command.isEmpty else { return nil }
            return ClaudeMCPImport(name: name, transport: "stdio", commandOrURL: command, args: args)
        }
    }

    private static func countList(_ raw: Any?) -> Int {
        if let list = raw as? [Any] { return list.count }
        return 0
    }

    private static func hookKeys(_ raw: Any?) -> [String] {
        if let dict = raw as? [String: Any] {
            return dict.keys.sorted()
        }
        return []
    }
}
