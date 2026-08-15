import Foundation

public struct AgentDefinition: Identifiable, Hashable, Sendable {
    public var id: String { slug + ":" + scope }
    public var slug: String
    public var title: String
    public var detail: String
    public var permissionMode: String
    public var scope: String
    public var url: URL

    public init(slug: String, title: String, detail: String, permissionMode: String, scope: String, url: URL) {
        self.slug = slug
        self.title = title
        self.detail = detail
        self.permissionMode = permissionMode
        self.scope = scope
        self.url = url
    }

    public var isBundled: Bool { scope == "bundled" }
}

public struct PersonaDefinition: Identifiable, Hashable, Sendable {
    public var id: String { slug + ":" + scope }
    public var slug: String
    public var title: String
    public var detail: String
    public var instructions: String
    public var model: String
    public var effort: String
    public var scope: String
    public var url: URL

    public init(
        slug: String,
        title: String,
        detail: String,
        instructions: String,
        model: String = "",
        effort: String = "",
        scope: String,
        url: URL
    ) {
        self.slug = slug
        self.title = title
        self.detail = detail
        self.instructions = instructions
        self.model = model
        self.effort = effort
        self.scope = scope
        self.url = url
    }

    public var isBundled: Bool { scope == "bundled" }
}

public enum AgentCatalogError: Error, LocalizedError {
    case invalidName
    case exists
    case readOnly

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Names use lowercase letters, digits, and hyphens."
        case .exists: return "That name already exists."
        case .readOnly: return "Bundled definitions are read-only."
        }
    }
}

public struct AgentCatalog: Sendable {
    public init() {}

    public func loadAgents(cwd: URL? = nil) -> [AgentDefinition] {
        var rows: [AgentDefinition] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        rows.append(contentsOf: loadAgents(root: home.appendingPathComponent(".grok/bundled/agents"), scope: "bundled"))
        rows.append(contentsOf: loadAgents(root: home.appendingPathComponent(".grok/agents"), scope: "user"))
        if let cwd {
            rows.append(contentsOf: loadAgents(root: cwd.appendingPathComponent(".grok/agents"), scope: "project"))
        }
        return rows.sorted { $0.slug.localizedStandardCompare($1.slug) == .orderedAscending }
    }

    public func loadPersonas(cwd: URL? = nil) -> [PersonaDefinition] {
        var rows: [PersonaDefinition] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        rows.append(contentsOf: loadPersonas(root: home.appendingPathComponent(".grok/bundled/personas"), scope: "bundled"))
        rows.append(contentsOf: loadPersonas(root: home.appendingPathComponent(".grok/personas"), scope: "user"))
        if let cwd {
            rows.append(contentsOf: loadPersonas(root: cwd.appendingPathComponent(".grok/personas"), scope: "project"))
        }
        return rows.sorted { $0.slug.localizedStandardCompare($1.slug) == .orderedAscending }
    }

    public func createPersona(name: String, detail: String, instructions: String) throws -> PersonaDefinition {
        let slug = sanitize(name)
        guard !slug.isEmpty else { throw AgentCatalogError.invalidName }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/personas")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(slug).toml")
        if FileManager.default.fileExists(atPath: url.path) { throw AgentCatalogError.exists }
        let desc = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = """
        description = "\(escapeTOML(desc.isEmpty ? slug : desc))"
        instructions = \"\"\"
        \(body.isEmpty ? "Behave as \(slug)." : body)
        \"\"\"
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        return PersonaDefinition(slug: slug, title: slug, detail: desc, instructions: body, scope: "user", url: url)
    }

    public func createAgent(name: String, detail: String) throws -> AgentDefinition {
        let slug = sanitize(name)
        guard !slug.isEmpty else { throw AgentCatalogError.invalidName }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/agents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(slug).md")
        if FileManager.default.fileExists(atPath: url.path) { throw AgentCatalogError.exists }
        let desc = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = """
        ---
        name: \(slug)
        description: >
          \(desc.isEmpty ? slug : desc)
        prompt_mode: full
        permission_mode: default
        agents_md: true
        ---

        Complete the assigned task. Stay in scope and report what you did.
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        return AgentDefinition(slug: slug, title: slug, detail: desc, permissionMode: "default", scope: "user", url: url)
    }

    public func deletePersona(_ persona: PersonaDefinition) throws {
        if persona.isBundled { throw AgentCatalogError.readOnly }
        try FileManager.default.removeItem(at: persona.url)
    }

    public func deleteAgent(_ agent: AgentDefinition) throws {
        if agent.isBundled { throw AgentCatalogError.readOnly }
        try FileManager.default.removeItem(at: agent.url)
    }

    public static func parseAgent(_ text: String, url: URL, scope: String) -> AgentDefinition? {
        let slug = url.deletingPathExtension().lastPathComponent
        let name = frontmatter(text, key: "name") ?? slug
        let detail = frontmatterBlock(text, key: "description") ?? firstParagraph(text)
        let mode = frontmatter(text, key: "permission_mode") ?? "default"
        return AgentDefinition(slug: name, title: name, detail: detail, permissionMode: mode, scope: scope, url: url)
    }

    public static func parsePersona(_ text: String, url: URL, scope: String) -> PersonaDefinition? {
        let slug = url.deletingPathExtension().lastPathComponent
        let detail = tomlString(text, key: "description") ?? ""
        let instructions = tomlMultiline(text, key: "instructions") ?? ""
        return PersonaDefinition(
            slug: slug,
            title: slug,
            detail: detail,
            instructions: instructions,
            model: tomlString(text, key: "model") ?? "",
            effort: tomlString(text, key: "reasoning_effort") ?? "",
            scope: scope,
            url: url
        )
    }

    private func loadAgents(root: URL, scope: String) -> [AgentDefinition] {
        files(in: root, ext: "md").compactMap { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return Self.parseAgent(text, url: url, scope: scope)
        }
    }

    private func loadPersonas(root: URL, scope: String) -> [PersonaDefinition] {
        files(in: root, ext: "toml").compactMap { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return Self.parsePersona(text, url: url, scope: scope)
        }
    }

    private func files(in root: URL, ext: String) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.filter { $0.pathExtension.lowercased() == ext }
    }

    private func sanitize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func escapeTOML(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func frontmatter(_ text: String, key: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\#(key):\s*(.+)$"#, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func frontmatterBlock(_ text: String, key: String) -> String? {
        if let line = frontmatter(text, key: key), line != ">" { return line }
        guard let regex = try? NSRegularExpression(pattern: #"\#(key):\s*>\s*\n((?:  .+\n?)+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[range]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    private static func firstParagraph(_ text: String) -> String {
        let body = text.components(separatedBy: "---").dropFirst(2).joined(separator: "---")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    private static func tomlString(_ text: String, key: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\#(key)\s*=\s*\"([^\"]*)\""#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func tomlMultiline(_ text: String, key: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\#(key)\s*=\s*\"\"\"([\s\S]*?)\"\"\""#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
