import Darwin
import Foundation

public enum ShellString: String, Sendable {
    case navChat
    case navBuild
    case navSettings
    case settingsTitle
    case settingsAccount
    case settingsAppearance
    case errorGeneric
    case errorCLI
    case firstRunTitle
    case firstRunBody
}

public enum ShellLocale {
    /// Product names stay Chat and Build. Every other shell string follows the catalog.
    public static func chrome(_ key: ShellString, preference: String?, preferredLanguages: [String]) -> String {
        switch key {
        case .navChat: return "Chat"
        case .navBuild: return "Build"
        default:
            guard let catalog = LocaleKey(rawValue: key.rawValue) else { return "" }
            return LocaleCatalog.string(catalog, preference: preference, preferredLanguages: preferredLanguages)
        }
    }
}

public enum IMDelivery {
    /// Starts or continues an ACP turn for a route the router already accepted. Rejected routes do nothing.
    @MainActor
    @discardableResult
    public static func deliver(route: IMRoute, client: ACPClient) async -> Bool {
        switch route {
        case .rejectedIncomplete, .rejectedUntrusted:
            return false
        case .start(let project, let prompt):
            client.remoteHost = ""
            do {
                try await client.newSession(cwd: URL(fileURLWithPath: project))
                if !prompt.isEmpty {
                    try await client.send(text: prompt, sessionID: client.sessionID)
                }
                return client.sessionID != nil
            } catch {
                return false
            }
        case .resume(let sessionID, let prompt):
            guard client.hasWorkspace(sessionID) else { return false }
            do {
                try await client.send(text: prompt, sessionID: sessionID)
                return true
            } catch {
                return false
            }
        case .turn(_, let prompt):
            do {
                if client.sessionID == nil || client.hasWorkspace(client.sessionID ?? "") == false {
                    try await client.newSession()
                }
                try await client.send(text: prompt, sessionID: client.sessionID)
                return true
            } catch {
                return false
            }
        }
    }
}

/// Long-lived ssh processes. Nothing here kills the child on a timer.
public final class SSHKeep: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    public private(set) var launchedPID: Int32 = 0
    public private(set) var launchedArguments: [String] = []

    public init() {}

    public func launch(executable: String, arguments: [String]) throws {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        lock.lock()
        self.process = process
        launchedPID = process.processIdentifier
        launchedArguments = arguments
        lock.unlock()
    }

    public func isAlive() -> Bool {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return false }
        return kill(process.processIdentifier, 0) == 0
    }

    public func stop() {
        lock.lock()
        let process = self.process
        self.process = nil
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

public final class MirrorTunnel: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    public private(set) var launchedPID: Int32 = 0
    public private(set) var launchedArguments: [String] = []

    public init() {}

    public func launch(port: UInt16) throws {
        try launch(executable: "/usr/bin/env", arguments: MirrorBind.tunnelCommand(port: port))
    }

    public func launch(executable: String, arguments: [String]) throws {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        lock.lock()
        self.process = process
        launchedPID = process.processIdentifier
        launchedArguments = arguments
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let process = self.process
        self.process = nil
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

public enum ExtensionGate {
    public static func snake(_ event: String) -> String {
        var out = ""
        for (index, character) in event.enumerated() {
            if character.isUppercase, index > 0 {
                out.append("_")
            }
            out.append(String(character).lowercased())
        }
        return out
    }

    public static func specNames(hooksDirectory: URL, event: String, command: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: hooksDirectory, includingPropertiesForKeys: nil)) ?? []
        let wantedEvent = snake(event)
        let wantedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var names: [String] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            let stem = file.deletingPathExtension().lastPathComponent
            for (groupIndex, group) in hookGroups(json).enumerated() {
                let eventName = snake(group.event)
                if !wantedEvent.isEmpty, eventName != wantedEvent { continue }
                for (hookIndex, hookCommand) in group.commands.enumerated() {
                    if !wantedCommand.isEmpty, hookCommand != wantedCommand { continue }
                    names.append("global/\(stem):\(eventName)[\(groupIndex)].hooks[\(hookIndex)]")
                }
            }
        }
        return names
    }

    public static func save(_ toggles: [ExtensionToggle], url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(toggles) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func load(url: URL) -> [ExtensionToggle] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ExtensionToggle].self, from: data)
        else { return [] }
        return items
    }

    /// Writes `$GROK_HOME/disabled-hooks` and the disable keys in config.toml. A bad config is left untouched.
    public static func apply(home: URL, toggles: [ExtensionToggle]) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try writeDisabledHooks(home: home, toggles: toggles)
        let configURL = home.appendingPathComponent("config.toml")
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let mcp = disabledNames(toggles, kind: "mcp")
        let plugins = disabledNames(toggles, kind: "plugin")
        let agents = disabledNames(toggles, kind: "agent")
        guard let merged = mergeConfig(
            existing: existing,
            mcpDisabled: mcp,
            mcpManaged: managedNames(toggles, kind: "mcp"),
            pluginsDisabled: plugins,
            pluginsManaged: managedNames(toggles, kind: "plugin"),
            agentsDisabled: agents,
            agentsManaged: managedNames(toggles, kind: "agent")
        ) else { return }
        if merged != existing {
            try merged.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    public static func mergeConfig(
        existing: String,
        mcpDisabled: [String],
        mcpManaged: Set<String>,
        pluginsDisabled: [String],
        pluginsManaged: Set<String>,
        agentsDisabled: [String],
        agentsManaged: Set<String>
    ) -> String? {
        guard parseable(existing) else { return nil }
        var text = mergeTopLevelArray(
            existing,
            key: "disabled_mcp_servers",
            disabled: mcpDisabled,
            managed: mcpManaged
        )
        text = mergeTableArray(text, table: "plugins", key: "disabled", disabled: pluginsDisabled, managed: pluginsManaged)
        text = mergeAgentToggles(text, disabled: agentsDisabled, managed: agentsManaged)
        return text
    }

    private struct HookGroup {
        var event: String
        var commands: [String]
    }

    private static func hookGroups(_ json: Any) -> [HookGroup] {
        if let rows = json as? [[String: Any]] {
            return rows.map(group(from:))
        }
        guard let dict = json as? [String: Any] else { return [] }
        if let hooks = dict["hooks"] as? [[String: Any]] {
            return hooks.map(group(from:))
        }
        var groups: [HookGroup] = []
        for key in dict.keys.sorted() where key != "hooks" {
            guard let rows = dict[key] as? [[String: Any]] else { continue }
            for row in rows {
                let nested = row["hooks"] as? [[String: Any]] ?? []
                let commands = nested.compactMap { $0["command"] as? String }
                if !commands.isEmpty {
                    groups.append(HookGroup(event: key, commands: commands))
                }
            }
        }
        return groups
    }

    private static func group(from row: [String: Any]) -> HookGroup {
        let event = row["event"] as? String ?? "SessionStart"
        if let nested = row["hooks"] as? [[String: Any]] {
            return HookGroup(event: event, commands: nested.compactMap { $0["command"] as? String })
        }
        let command = (row["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HookGroup(event: event, commands: command.isEmpty ? [] : [command])
    }

    private static func writeDisabledHooks(home: URL, toggles: [ExtensionToggle]) throws {
        let url = home.appendingPathComponent("disabled-hooks")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hookToggles = toggles.filter { $0.kind == "hook" }
        var managed: Set<String> = []
        var disabled: [String] = []
        for toggle in hookToggles {
            let specs = hookSpecs(toggle, home: home)
            managed.formUnion(specs)
            if !toggle.enabled {
                disabled.append(contentsOf: specs)
            }
        }
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && managed.contains(trimmed)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        for name in disabled where !lines.contains(name) {
            lines.append(name)
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func hookSpecs(_ toggle: ExtensionToggle, home: URL) -> [String] {
        if toggle.name.contains(":") { return [toggle.name] }
        return specNames(hooksDirectory: home.appendingPathComponent("hooks"), event: toggle.name, command: "")
    }

    private static func disabledNames(_ toggles: [ExtensionToggle], kind: String) -> [String] {
        toggles.filter { $0.kind == kind && !$0.enabled }.map(\.name).sorted()
    }

    private static func managedNames(_ toggles: [ExtensionToggle], kind: String) -> Set<String> {
        Set(toggles.filter { $0.kind == kind }.map(\.name))
    }

    private static func parseable(_ text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.filter({ $0 == "\"" }).count % 2 != 0 { return false }
        }
        return true
    }

    private static func tomlString(_ name: String) -> String {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func tomlArray(_ names: [String]) -> String {
        "[\(names.map(tomlString).joined(separator: ", "))]"
    }

    private static func splitTable(_ names: String) -> [String] {
        var values: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in names {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" && quoted {
                escaped = true
                current.append(character)
                continue
            }
            if character == "\"" {
                quoted.toggle()
                current.append(character)
                continue
            }
            if character == "," && !quoted {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { values.append(unquote(trimmed)) }
                current = ""
                continue
            }
            current.append(character)
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { values.append(unquote(trimmed)) }
        return values
    }

    private static func unquote(_ token: String) -> String {
        guard token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 else { return token }
        let inner = token.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func firstTableIndex(_ lines: [String]) -> Int {
        lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
    }

    private static func mergeTopLevelArray(_ text: String, key: String, disabled: [String], managed: Set<String>) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = firstTableIndex(lines)
        let assignment = "\(key) = \(tomlArray(reconcile(existing: [], disabled: disabled, managed: managed)))"
        if let index = lines.prefix(header).firstIndex(where: { isAssignment($0, key: key) }) {
            let current = arrayBody(lines[index])
            lines[index] = "\(key) = \(tomlArray(reconcile(existing: current, disabled: disabled, managed: managed)))"
            return lines.joined(separator: "\n")
        }
        if disabled.isEmpty { return text }
        lines.insert(assignment, at: 0)
        return lines.joined(separator: "\n")
    }

    private static func mergeTableArray(_ text: String, table: String, key: String, disabled: [String], managed: Set<String>) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = "[\(table)]"
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            let end = nextTable(lines, after: start)
            if let index = lines[start + 1..<end].firstIndex(where: { isAssignment($0, key: key) }) {
                let current = arrayBody(lines[index])
                lines[index] = "\(key) = \(tomlArray(reconcile(existing: current, disabled: disabled, managed: managed)))"
            } else if !disabled.isEmpty {
                lines.insert("\(key) = \(tomlArray(disabled))", at: start + 1)
            }
            return lines.joined(separator: "\n")
        }
        if disabled.isEmpty { return lines.joined(separator: "\n") }
        if lines.last?.isEmpty == false, !lines.isEmpty { lines.append("") }
        lines.append(header)
        lines.append("\(key) = \(tomlArray(disabled))")
        return lines.joined(separator: "\n")
    }

    private static func mergeAgentToggles(_ text: String, disabled: [String], managed: Set<String>) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = "[subagents.toggle]"
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            let end = nextTable(lines, after: start)
            var section = Array(lines[start + 1..<end])
            section.removeAll { line in
                guard let name = agentName(line) else { return false }
                return managed.contains(name)
            }
            for name in disabled.sorted() {
                section.append("\(tomlString(name)) = false")
            }
            lines.replaceSubrange(start + 1..<end, with: section)
            return lines.joined(separator: "\n")
        }
        if disabled.isEmpty { return lines.joined(separator: "\n") }
        if lines.last?.isEmpty == false, !lines.isEmpty { lines.append("") }
        lines.append(header)
        for name in disabled.sorted() {
            lines.append("\(tomlString(name)) = false")
        }
        return lines.joined(separator: "\n")
    }

    private static func nextTable(_ lines: [String], after start: Int) -> Int {
        for index in (start + 1)..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") { return index }
        }
        return lines.count
    }

    private static func isAssignment(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("\(key) ") || trimmed.hasPrefix("\(key)=")
    }

    private static func arrayBody(_ line: String) -> [String] {
        guard let equals = line.firstIndex(of: "=") else { return [] }
        let rhs = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard rhs.hasPrefix("["), rhs.hasSuffix("]") else { return [] }
        let inner = rhs.dropFirst().dropLast()
        return splitTable(String(inner))
    }

    private static func reconcile(existing: [String], disabled: [String], managed: Set<String>) -> [String] {
        var kept = existing.filter { !managed.contains($0) }
        for name in disabled where !kept.contains(name) {
            kept.append(name)
        }
        return kept
    }

    private static func agentName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("="), trimmed.hasSuffix("false") || trimmed.contains("false") else { return nil }
        guard let equals = trimmed.firstIndex(of: "=") else { return nil }
        let raw = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        let name = unquote(raw)
        return name.isEmpty ? nil : name
    }
}
