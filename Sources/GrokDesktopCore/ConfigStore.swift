import Foundation

public struct GrokConfig: Equatable, Sendable {
    public var defaultModel: String
    public var defaultEffort: String
    public var permissionMode: String
    public var rememberApprovals: Bool
    public var showThinking: Bool
    public var autoCompactPercent: Int
    public var memoryEnabled: Bool
    public var respectGitignore: Bool
    public var codebaseIndexing: Bool
    public var sandboxProfile: String
    public var fastModel: String
    public var fastEffort: String
    public var expertModel: String
    public var expertEffort: String
    public var heavyModel: String
    public var heavyEffort: String
    public var mcpHint: String
    public var mcpNames: [String]
    public var disabledSkills: [String]
    public var raw: String

    public init(
        defaultModel: String = "grok-4.5",
        defaultEffort: String = "medium",
        permissionMode: String = "ask",
        rememberApprovals: Bool = false,
        showThinking: Bool = true,
        autoCompactPercent: Int = 85,
        memoryEnabled: Bool = false,
        respectGitignore: Bool = false,
        codebaseIndexing: Bool = true,
        sandboxProfile: String = "off",
        fastModel: String = "grok-4.6",
        fastEffort: String = "low",
        expertModel: String = "grok-build",
        expertEffort: String = "high",
        heavyModel: String = "grok-build",
        heavyEffort: String = "xhigh",
        mcpHint: String = "",
        mcpNames: [String] = [],
        disabledSkills: [String] = [],
        raw: String = ""
    ) {
        self.defaultModel = defaultModel
        self.defaultEffort = defaultEffort
        self.permissionMode = permissionMode
        self.rememberApprovals = rememberApprovals
        self.showThinking = showThinking
        self.autoCompactPercent = autoCompactPercent
        self.memoryEnabled = memoryEnabled
        self.respectGitignore = respectGitignore
        self.codebaseIndexing = codebaseIndexing
        self.sandboxProfile = sandboxProfile
        self.fastModel = fastModel
        self.fastEffort = fastEffort
        self.expertModel = expertModel
        self.expertEffort = expertEffort
        self.heavyModel = heavyModel
        self.heavyEffort = heavyEffort
        self.mcpHint = mcpHint
        self.mcpNames = mcpNames
        self.disabledSkills = disabledSkills
        self.raw = raw
    }

    public var defaultBuildModel: BuildModel {
        BuildModel(rawValue: defaultModel) ?? .grok45
    }

    public var defaultEffortLevel: EffortLevel {
        EffortLevel(rawValue: defaultEffort) ?? .medium
    }
}

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/config.toml")
    ) {
        self.fileURL = fileURL
    }

    public func load() -> GrokConfig {
        let raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var config = GrokConfig(raw: raw)
        config.defaultModel = string(raw, section: "models", key: "default") ?? config.defaultModel
        config.defaultEffort = string(raw, section: "models", key: "default_reasoning_effort") ?? config.defaultEffort
        config.permissionMode = string(raw, section: "ui", key: "permission_mode") ?? config.permissionMode
        if let value = bool(raw, section: "ui", key: "remember_tool_approvals") {
            config.rememberApprovals = value
        }
        if let value = bool(raw, section: "ui", key: "show_thinking_blocks") {
            config.showThinking = value
        }
        if let value = int(raw, section: "session", key: "auto_compact_threshold_percent") {
            config.autoCompactPercent = value
        }
        if let value = bool(raw, section: "memory", key: "enabled") {
            config.memoryEnabled = value
        }
        if let value = bool(raw, section: "tools", key: "respect_gitignore") {
            config.respectGitignore = value
        }
        if let value = bool(raw, section: "features", key: "codebase_indexing") {
            config.codebaseIndexing = value
        }
        config.sandboxProfile = string(raw, section: "sandbox", key: "profile") ?? config.sandboxProfile
        config.fastModel = string(raw, section: "grok_desktop", key: "fast_model") ?? config.fastModel
        config.fastEffort = string(raw, section: "grok_desktop", key: "fast_effort") ?? config.fastEffort
        config.expertModel = string(raw, section: "grok_desktop", key: "expert_model") ?? config.expertModel
        config.expertEffort = string(raw, section: "grok_desktop", key: "expert_effort") ?? config.expertEffort
        config.heavyModel = string(raw, section: "grok_desktop", key: "heavy_model") ?? config.heavyModel
        config.heavyEffort = string(raw, section: "grok_desktop", key: "heavy_effort") ?? config.heavyEffort
        config.mcpNames = mcpNames(in: raw)
        config.disabledSkills = stringArray(raw, section: "skills", key: "disabled")
        if !config.mcpNames.isEmpty || raw.contains("[mcp") || raw.contains("[[mcp") {
            config.mcpHint = config.mcpNames.isEmpty
                ? "MCP servers are declared in ~/.grok/config.toml"
                : config.mcpNames.joined(separator: ", ")
        }
        return config
    }

    private func mcpNames(in raw: String) -> [String] {
        var names: [String] = []
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[") && trimmed.contains("mcp") && trimmed.hasSuffix("]]") {
                names.append(trimmed)
            } else if trimmed.hasPrefix("name"), trimmed.contains("="), raw.contains("[mcp") {
                if let value = trimmed.split(separator: "=", maxSplits: 1).last {
                    names.append(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: ""))
                }
            }
        }
        return names
    }

    public func set(section: String, key: String, value: String) throws {
        var raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        raw = upsert(raw, section: section, key: key, value: quoted(value))
        try write(raw)
    }

    public func set(section: String, key: String, bool value: Bool) throws {
        var raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        raw = upsert(raw, section: section, key: key, value: value ? "true" : "false")
        try write(raw)
    }

    public func set(section: String, key: String, int value: Int) throws {
        var raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        raw = upsert(raw, section: section, key: key, value: String(value))
        try write(raw)
    }

    public func set(section: String, key: String, array value: [String]) throws {
        var raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let rendered = "[" + value.map { quoted($0) }.joined(separator: ", ") + "]"
        raw = upsert(raw, section: section, key: key, value: rendered)
        try write(raw)
    }

    public func openInEditor() {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        #if os(macOS)
        NSWorkspaceShim.open(url)
        #endif
    }

    private func write(_ raw: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try raw.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func quoted(_ value: String) -> String {
        if value == "true" || value == "false" || Int(value) != nil { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func string(_ raw: String, section: String, key: String) -> String? {
        guard let body = sectionBody(raw, section: section) else { return nil }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix("\(key)") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(of: "#") {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    private func bool(_ raw: String, section: String, key: String) -> Bool? {
        guard let value = string(raw, section: key == "remember_tool_approvals" || key == "show_thinking_blocks" ? section : section, key: key) else {
            return nil
        }
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    private func int(_ raw: String, section: String, key: String) -> Int? {
        string(raw, section: section, key: key).flatMap(Int.init)
    }

    private func stringArray(_ raw: String, section: String, key: String) -> [String] {
        guard let body = sectionBody(raw, section: section) else { return [] }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix("\(key)") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(of: "#"), !value.hasPrefix("[") {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            guard value.hasPrefix("[") else { return [] }
            var names: [String] = []
            var current = ""
            var inQuote = false
            for character in value.dropFirst().dropLast() {
                if character == "\"" {
                    if inQuote {
                        names.append(current)
                        current = ""
                    }
                    inQuote.toggle()
                } else if inQuote {
                    current.append(character)
                }
            }
            return names
        }
        return []
    }

    private func sectionBody(_ raw: String, section: String) -> String? {
        let header = "[\(section)]"
        guard let start = raw.range(of: header) else { return nil }
        let rest = raw[start.upperBound...]
        if let next = rest.range(of: "\n[", options: []) {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    private func upsert(_ raw: String, section: String, key: String, value: String) -> String {
        let header = "[\(section)]"
        if raw.range(of: header) == nil {
            let prefix = raw.hasSuffix("\n") || raw.isEmpty ? raw : raw + "\n"
            return prefix + "\n\(header)\n\(key) = \(value)\n"
        }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inSection = false
        var replaced = false
        var insertAt: Int?
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == header {
                inSection = true
                insertAt = index + 1
                continue
            }
            if inSection, trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                inSection = false
                continue
            }
            if inSection {
                let keyPart = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces)
                if keyPart == key {
                    let indent = String(lines[index].prefix { $0 == " " || $0 == "\t" })
                    lines[index] = "\(indent)\(key) = \(value)"
                    replaced = true
                    break
                }
                if !trimmed.isEmpty { insertAt = index + 1 }
            }
        }
        if !replaced, let insertAt {
            lines.insert("\(key) = \(value)", at: insertAt)
        }
        return lines.joined(separator: "\n")
    }
}

#if os(macOS)
import AppKit

private enum NSWorkspaceShim {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
#endif
