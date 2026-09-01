import Foundation

public struct PluginRecord: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public var name: String
    public var status: String
    public var enabled: Bool
    public var version: String
    public var marketplace: String
    public var detail: String
    public var path: String
    public var source: String
    public var skillCount: Int
    public var hasHooks: Bool
    public var hasAgents: Bool
    public var hasMCP: Bool

    public init(
        name: String,
        status: String = "available",
        enabled: Bool = true,
        version: String = "",
        marketplace: String = "",
        detail: String = "",
        path: String = "",
        source: String = "",
        skillCount: Int = 0,
        hasHooks: Bool = false,
        hasAgents: Bool = false,
        hasMCP: Bool = false
    ) {
        self.name = name
        self.status = status
        self.enabled = enabled
        self.version = version
        self.marketplace = marketplace
        self.detail = detail
        self.path = path
        self.source = source
        self.skillCount = skillCount
        self.hasHooks = hasHooks
        self.hasAgents = hasAgents
        self.hasMCP = hasMCP
    }

    public var isInstalled: Bool { status == "installed" || status == "disabled" }
    public var isAvailable: Bool { status == "available" }

    public var providesLabel: String {
        var parts: [String] = []
        if skillCount > 0 { parts.append("\(skillCount) skills") }
        if hasAgents { parts.append("agents") }
        if hasHooks { parts.append("hooks") }
        if hasMCP { parts.append("MCP") }
        return parts.joined(separator: " · ")
    }

    public var installSource: String {
        if !source.isEmpty { return source }
        return name
    }
}

public struct MarketplaceSource: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public var name: String
    public var url: String
    public var kind: String

    public init(name: String, url: String, kind: String = "git") {
        self.name = name
        self.url = url
        self.kind = kind
    }
}

public enum PluginCatalog {
    public static func parseList(_ text: String) -> [PluginRecord] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] {
            rows = array
        } else if let dict = object as? [String: Any] {
            rows = dict["plugins"] as? [[String: Any]] ?? []
        } else {
            return []
        }
        return rows.compactMap(parseRow)
    }

    public static func parseInspect(_ object: [String: Any]) -> [PluginRecord] {
        let rows = object["plugins"] as? [[String: Any]] ?? []
        return rows.compactMap(parseInspectRow)
    }

    public static func parseMarketplaces(_ text: String) -> [MarketplaceSource] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] {
            rows = array
        } else if let dict = object as? [String: Any] {
            rows = dict["marketplaces"] as? [[String: Any]] ?? dict["sources"] as? [[String: Any]] ?? []
        } else {
            return []
        }
        return rows.compactMap { row in
            let name = row["name"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            let source = row["source"] as? [String: Any] ?? [:]
            let url = source["url"] as? String
                ?? row["url"] as? String
                ?? row["git"] as? String
                ?? ""
            return MarketplaceSource(
                name: name,
                url: url,
                kind: row["kind"] as? String ?? "git"
            )
        }
    }

    public static func merge(inspect: [PluginRecord], listed: [PluginRecord]) -> [PluginRecord] {
        var byName: [String: PluginRecord] = [:]
        for item in listed {
            byName[item.name.lowercased()] = item
        }
        for item in inspect {
            let key = item.name.lowercased()
            if var existing = byName[key] {
                existing.enabled = item.enabled
                existing.status = item.enabled ? "installed" : "disabled"
                if existing.detail.isEmpty { existing.detail = item.detail }
                if existing.path.isEmpty { existing.path = item.path }
                if existing.skillCount == 0 { existing.skillCount = item.skillCount }
                existing.hasHooks = existing.hasHooks || item.hasHooks
                existing.hasAgents = existing.hasAgents || item.hasAgents
                existing.hasMCP = existing.hasMCP || item.hasMCP
                byName[key] = existing
            } else {
                byName[key] = item
            }
        }
        return byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func load(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL? = nil
    ) -> (plugins: [PluginRecord], marketplaces: [MarketplaceSource]) {
        guard let grok = locator.locate() else { return ([], []) }
        let directory = cwd ?? FileManager.default.homeDirectoryForCurrentUser
        let listedText = TimedProcess.run(
            executable: grok,
            arguments: ["plugin", "list", "--json", "--available"],
            cwd: directory,
            timeout: 12,
            limitBytes: 4_000_000
        ) ?? "[]"
        let marketText = TimedProcess.run(
            executable: grok,
            arguments: ["plugin", "marketplace", "list", "--json"],
            cwd: directory,
            timeout: 8,
            limitBytes: 500_000
        ) ?? "[]"
        return (parseList(listedText), parseMarketplaces(marketText))
    }

    private static func parseRow(_ row: [String: Any]) -> PluginRecord? {
        guard let name = row["name"] as? String, !name.isEmpty else { return nil }
        let status = (row["status"] as? String ?? "available").lowercased()
        let components = row["components"] as? [String: Any] ?? [:]
        let skills = components["skills"] as? [[String: Any]] ?? []
        let skillCount = row["skill_count"] as? Int ?? skills.count
        let hooks = components["hooks"] as? [Any] ?? []
        let agents = components["agents"] as? [Any] ?? []
        let mcp = components["mcpServers"] as? [Any] ?? components["mcp_servers"] as? [Any] ?? []
        return PluginRecord(
            name: name,
            status: status == "disabled" ? "disabled" : status,
            enabled: status != "disabled" && status != "blocked",
            version: row["version"] as? String ?? "",
            marketplace: row["marketplace"] as? String ?? "",
            detail: String((row["description"] as? String ?? "").prefix(180)),
            path: row["path"] as? String ?? "",
            source: row["source"] as? String ?? row["repo_key"] as? String ?? "",
            skillCount: skillCount,
            hasHooks: (row["has_hooks"] as? Bool ?? false) || !hooks.isEmpty,
            hasAgents: (row["has_agents"] as? Bool ?? false) || !agents.isEmpty,
            hasMCP: (row["has_mcp"] as? Bool ?? false) || !mcp.isEmpty
        )
    }

    private static func parseInspectRow(_ row: [String: Any]) -> PluginRecord? {
        guard let name = row["name"] as? String, !name.isEmpty else { return nil }
        let enabled = row["enabled"] as? Bool ?? true
        let provides = row["provides"] as? [String: Any] ?? [:]
        let skillCount = provides["skills"] as? Int ?? 0
        let hooks = provides["hooks"]
        let hasHooks = (hooks as? Bool) ?? ((hooks as? Int ?? 0) > 0)
        let agents = provides["agents"] as? Int ?? 0
        let mcp = provides["mcpServers"] as? Int ?? provides["mcp_servers"] as? Int ?? 0
        return PluginRecord(
            name: name,
            status: enabled ? "installed" : "disabled",
            enabled: enabled,
            marketplace: row["marketplace"] as? String ?? "",
            detail: String((row["description"] as? String ?? "").prefix(180)),
            path: row["path"] as? String ?? "",
            skillCount: skillCount,
            hasHooks: hasHooks,
            hasAgents: agents > 0,
            hasMCP: mcp > 0
        )
    }
}
