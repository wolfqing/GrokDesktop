import Foundation

public enum GrokInspect {
    public static func load(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL? = nil
    ) -> (skills: [SkillRecord], mcp: [MCPServerRecord])? {
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
        return (parseSkills(object, cwd: cwd), parseMCP(object))
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
