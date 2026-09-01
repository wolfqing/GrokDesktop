import Foundation

public enum GrokInspect {
    public static let freshInterval: TimeInterval = 90

    private static let lock = NSLock()
    nonisolated(unsafe) private static var memory: Snapshot?

    private struct Snapshot: Codable {
        var cwd: String
        var savedAt: Date
        var skills: [SkillRecord]
        var mcp: [MCPServerRecord]
    }

    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/desktop/catalog-cache.json")
    }

    public static func cached(
        cwd: URL?,
        now: Date = Date(),
        fileURL: URL? = nil
    ) -> (skills: [SkillRecord], mcp: [MCPServerRecord])? {
        let key = cwd?.standardizedFileURL.path ?? ""
        lock.lock()
        let mem = memory
        lock.unlock()
        if let mem, mem.cwd == key {
            return (mem.skills, mem.mcp)
        }
        let url = fileURL ?? cacheURL
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(Snapshot.self, from: data),
              file.cwd == key,
              now.timeIntervalSince(file.savedAt) < 7 * 24 * 3600
        else { return nil }
        lock.lock()
        memory = file
        lock.unlock()
        return (file.skills, file.mcp)
    }

    public static func isFresh(cwd: URL?, now: Date = Date()) -> Bool {
        let key = cwd?.standardizedFileURL.path ?? ""
        lock.lock()
        let mem = memory
        lock.unlock()
        guard let mem, mem.cwd == key else { return false }
        return now.timeIntervalSince(mem.savedAt) < freshInterval
    }

    public static func load(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL? = nil,
        force: Bool = false
    ) -> (skills: [SkillRecord], mcp: [MCPServerRecord], plugins: [PluginRecord], hooks: [HookDefinition])? {
        if !force, isFresh(cwd: cwd), let hit = cached(cwd: cwd) {
            return (hit.skills, hit.mcp, [], [])
        }
        guard let grok = locator.locate() else { return nil }
        let directory = cwd ?? FileManager.default.homeDirectoryForCurrentUser
        guard let text = TimedProcess.run(
            executable: grok,
            arguments: ["inspect", "--json"],
            cwd: directory,
            timeout: 8,
            limitBytes: 4_000_000
        ), let data = text.data(using: .utf8) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let skills = parseSkills(object, cwd: cwd)
        let mcp = parseMCP(object)
        store(cwd: cwd, skills: skills, mcp: mcp)
        return (skills, mcp, parsePlugins(object), parseHooks(object))
    }

    public static func parsePlugins(_ object: [String: Any]) -> [PluginRecord] {
        PluginCatalog.parseInspect(object)
    }

    public static func parseHooks(_ object: [String: Any]) -> [HookDefinition] {
        HarnessEvents.parseHooks(object)
    }

    public static func store(
        cwd: URL?,
        skills: [SkillRecord],
        mcp: [MCPServerRecord],
        fileURL: URL? = nil
    ) {
        let snapshot = Snapshot(
            cwd: cwd?.standardizedFileURL.path ?? "",
            savedAt: Date(),
            skills: skills,
            mcp: mcp
        )
        lock.lock()
        memory = snapshot
        lock.unlock()
        let url = fileURL ?? cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func parseSkills(_ object: [String: Any], cwd: URL? = nil) -> [SkillRecord] {
        let rows = object["skills"] as? [[String: Any]] ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var seen = Set<String>()
        var records: [SkillRecord] = []
        for row in rows {
            guard let name = row["name"] as? String, seen.insert(name).inserted else { continue }
            let description = row["description"] as? String ?? ""
            let source = row["source"] as? [String: Any] ?? [:]
            let path = source["path"] as? String
            let type = (source["type"] as? String ?? "user").lowercased()
            let plugin = source["plugin_name"] as? String
            var kind = type
            if kind != "plugin", kind != "bundled", let path, let cwd {
                if path.hasPrefix(cwd.path), !path.hasPrefix(home) {
                    kind = "project"
                }
            }
            if kind != "plugin", kind != "bundled", kind != "project" {
                kind = "user"
            }
            let directory: URL?
            if let path {
                let url = URL(fileURLWithPath: path)
                directory = url.lastPathComponent.lowercased() == "skill.md" ? url.deletingLastPathComponent() : url
            } else {
                directory = nil
            }
            records.append(
                SkillRecord(
                    slug: name,
                    title: SkillCatalog.prettyTitle(name),
                    detail: String(description.prefix(140)),
                    icon: SkillCatalog.icon(for: name),
                    directory: directory,
                    sourceKind: kind,
                    userInvocable: (row["userInvocable"] as? Bool) ?? true,
                    pluginName: plugin
                )
            )
        }
        return SkillCatalog.sort(records)
    }

    public static func parseMCP(_ object: [String: Any]) -> [MCPServerRecord] {
        let rows = object["mcpServers"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let name = row["name"] as? String ?? row["id"] as? String else { return nil }
            let transport = row["transport"] as? String ?? "stdio"
            let target = row["target"] as? String
                ?? row["command"] as? String
                ?? row["url"] as? String
                ?? ""
            let source = row["source"] as? [String: Any] ?? [:]
            let sourceType = (source["type"] as? String ?? "user").lowercased()
            let plugin = source["plugin_name"] as? String
            let status = (row["compatibilityStatus"] as? String)?.lowercased()
            let enabled = status != "disabled" && status != "blocked"
            let kind: String
            let label: String
            switch sourceType {
            case "plugin":
                kind = "plugin"
                label = plugin.map { "plugin · \($0)" } ?? "plugin"
            case "claudejson", "claude":
                kind = "claude"
                label = "Claude"
            default:
                kind = sourceType.isEmpty ? "user" : sourceType
                label = kind == "user" ? "" : kind
            }
            return MCPServerRecord(
                name: name,
                transport: transport,
                commandOrURL: target,
                args: row["args"] as? [String] ?? [],
                enabled: enabled,
                scope: kind,
                managed: false,
                sourceLabel: label
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
