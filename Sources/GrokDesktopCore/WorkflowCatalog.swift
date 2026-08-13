import Foundation

public struct WorkflowRecord: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var name: String
    public var detail: String
    public var scope: String
    public var url: URL

    public init(name: String, detail: String, scope: String, url: URL) {
        self.name = name
        self.detail = detail
        self.scope = scope
        self.url = url
    }
}

public enum WorkflowCatalogError: Error, LocalizedError {
    case invalidName
    case exists

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Workflow names use lowercase letters, digits, and hyphens."
        case .exists: return "A workflow with that name already exists."
        }
    }
}

public struct WorkflowCatalog: Sendable {
    public init() {}

    public func load(cwd: URL? = nil) -> [WorkflowRecord] {
        var records: [WorkflowRecord] = []
        let userRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/workflows")
        records.append(contentsOf: load(root: userRoot, scope: "user"))
        if let cwd {
            records.append(contentsOf: load(root: cwd.appendingPathComponent(".grok/workflows"), scope: "project"))
        }
        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func create(name: String, detail: String, scope: String, cwd: URL?) throws -> WorkflowRecord {
        let slug = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw WorkflowCatalogError.invalidName
        }
        let root: URL
        if scope == "project", let cwd {
            root = cwd.appendingPathComponent(".grok/workflows")
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/workflows")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(slug).rhai")
        if FileManager.default.fileExists(atPath: url.path) {
            throw WorkflowCatalogError.exists
        }
        let description = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = description.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let body = """
        let meta = #{
            name: "\(slug)",
            description: "\(escaped.isEmpty ? slug : escaped)",
        };

        phase("Run");
        let r = agent("Carry out this workflow: \(escaped.isEmpty ? slug : escaped). Use tools. Report what you did.",
            #{ label: "main", capability_mode: "all" });
        if r != () && r.success { complete(r.output); }
        complete(#{ summary: "Workflow finished." });
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        return WorkflowRecord(name: slug, detail: description, scope: scope, url: url)
    }

    public func delete(_ record: WorkflowRecord) throws {
        try FileManager.default.removeItem(at: record.url)
    }

    public static func parse(_ text: String, url: URL, scope: String) -> WorkflowRecord? {
        let name = firstQuoted(text, key: "name") ?? url.deletingPathExtension().lastPathComponent
        let detail = firstQuoted(text, key: "description") ?? firstQuoted(text, key: "when_to_use") ?? ""
        return WorkflowRecord(name: name, detail: detail, scope: scope, url: url)
    }

    private func load(root: URL, scope: String) -> [WorkflowRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.compactMap { url -> WorkflowRecord? in
            guard url.pathExtension == "rhai" else { return nil }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return Self.parse(text, url: url, scope: scope)
        }
    }

    private static func firstQuoted(_ text: String, key: String) -> String? {
        let pattern = "\(key):\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
