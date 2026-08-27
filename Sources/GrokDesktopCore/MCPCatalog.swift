import Foundation

public struct MCPServerRecord: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public var name: String
    public var transport: String
    public var commandOrURL: String
    public var args: [String]
    public var enabled: Bool
    public var scope: String
    public var managed: Bool
    public var sourceLabel: String

    public init(
        name: String,
        transport: String = "stdio",
        commandOrURL: String = "",
        args: [String] = [],
        enabled: Bool = true,
        scope: String = "user",
        managed: Bool = true,
        sourceLabel: String = ""
    ) {
        self.name = name
        self.transport = transport
        self.commandOrURL = commandOrURL
        self.args = args
        self.enabled = enabled
        self.scope = scope
        self.managed = managed
        self.sourceLabel = sourceLabel
    }

    public var detail: String {
        let tail = args.isEmpty ? "" : " " + args.joined(separator: " ")
        var line = "\(transport) · \(commandOrURL)\(tail)"
        if !sourceLabel.isEmpty {
            line += " · \(sourceLabel)"
        }
        return line
    }
}

public enum MCPCatalogError: Error, LocalizedError {
    case grokMissing
    case invalidName
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .grokMissing: return "Could not find the grok CLI."
        case .invalidName: return "MCP names may only use letters, numbers, hyphens, and underscores."
        case .commandFailed(let detail): return detail
        }
    }
}

public struct MCPCatalog: Sendable {
    public var configURL: URL

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/config.toml")
    ) {
        self.configURL = configURL
    }

    public func load(locator: GrokBinaryLocator = GrokBinaryLocator(), cwd: URL? = nil) -> [MCPServerRecord] {
        if let fromCLI = loadFromCLI(locator: locator, cwd: cwd), !fromCLI.isEmpty {
            return fromCLI
        }
        return Self.parseTOML((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
    }

    public static func merge(inspect: [MCPServerRecord], listed: [MCPServerRecord]) -> [MCPServerRecord] {
        let listedNames = Set(listed.map(\.name))
        var byName: [String: MCPServerRecord] = [:]
        for item in inspect {
            var rec = item
            rec.managed = listedNames.contains(item.name)
            byName[rec.name] = rec
        }
        for item in listed where byName[item.name] == nil {
            var rec = item
            rec.managed = true
            byName[rec.name] = rec
        }
        return byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func add(
        name: String,
        transport: String,
        commandOrURL: String,
        args: [String],
        locator: GrokBinaryLocator = GrokBinaryLocator()
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw MCPCatalogError.invalidName
        }
        var argv = ["mcp", "add", "--scope", "user", "--transport", transport, trimmed]
        if transport == "stdio" {
            argv.append("--")
            argv.append(commandOrURL)
            argv.append(contentsOf: args)
        } else {
            argv.append(commandOrURL)
        }
        _ = try runGrok(argv, locator: locator)
    }

    public func remove(name: String, locator: GrokBinaryLocator = GrokBinaryLocator()) throws {
        _ = try runGrok(["mcp", "remove", name], locator: locator)
    }

    public func setEnabled(_ name: String, enabled: Bool, locator: GrokBinaryLocator = GrokBinaryLocator()) throws {
        _ = try runGrok(["mcp", enabled ? "enable" : "disable", name], locator: locator)
    }

    public static func parseTOML(_ raw: String) -> [MCPServerRecord] {
        var records: [MCPServerRecord] = []
        var current: MCPServerRecord?
        func flush() {
            if let current { records.append(current) }
        }
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[mcp_servers."), trimmed.hasSuffix("]") {
                flush()
                let inner = trimmed.dropFirst("[mcp_servers.".count).dropLast()
                current = MCPServerRecord(name: String(inner))
                continue
            }
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                flush()
                current = nil
                continue
            }
            guard var item = current else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#"), !value.hasPrefix("[") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "command":
                item.commandOrURL = value
                item.transport = "stdio"
            case "url":
                item.commandOrURL = value
                if item.transport == "stdio" { item.transport = "http" }
            case "enabled":
                item.enabled = value != "false"
            case "args":
                item.args = value
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\""))) }
                    .filter { !$0.isEmpty }
            default:
                break
            }
            current = item
        }
        flush()
        return records
    }

    private func loadFromCLI(locator: GrokBinaryLocator, cwd: URL?) -> [MCPServerRecord]? {
        guard let text = try? runGrok(["mcp", "list", "--json"], locator: locator, cwd: cwd),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        let rows: [[String: Any]]
        if let list = object as? [[String: Any]] {
            rows = list
        } else if let dict = object as? [String: Any], let list = dict["servers"] as? [[String: Any]] {
            rows = list
        } else {
            return []
        }
        return rows.compactMap { row in
            guard let name = row["name"] as? String ?? row["id"] as? String else { return nil }
            let command = row["command"] as? String ?? row["url"] as? String ?? ""
            let args = row["args"] as? [String] ?? []
            let enabled = (row["enabled"] as? Bool) ?? true
            let transport = row["transport"] as? String ?? (row["url"] != nil ? "http" : "stdio")
            let scope = row["scope"] as? String ?? "user"
            return MCPServerRecord(
                name: name,
                transport: transport,
                commandOrURL: command,
                args: args,
                enabled: enabled,
                scope: scope
            )
        }
    }

    @discardableResult
    private func runGrok(_ arguments: [String], locator: GrokBinaryLocator, cwd: URL? = nil) throws -> String {
        guard let grok = locator.locate() else { throw MCPCatalogError.grokMissing }
        let process = Process()
        process.executableURL = grok
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw MCPCatalogError.commandFailed(err.isEmpty ? out : err)
        }
        return out
    }
}
