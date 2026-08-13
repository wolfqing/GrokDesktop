import Foundation

public enum SubscriptionPlan: String, CaseIterable, Sendable {
    case grok
    case superGrok
    case superGrokHeavy

    public var wordmark: String {
        switch self {
        case .grok: return "Grok"
        case .superGrok: return "SuperGrok"
        case .superGrokHeavy: return "SuperGrok Heavy"
        }
    }
}

public struct AccountProfile: Sendable, Equatable {
    public var email: String?
    public var name: String?
    public var userID: String?
    public var teamID: String?
    public var plan: SubscriptionPlan

    public init(
        email: String? = nil,
        name: String? = nil,
        userID: String? = nil,
        teamID: String? = nil,
        plan: SubscriptionPlan = .grok
    ) {
        self.email = email
        self.name = name
        self.userID = userID
        self.teamID = teamID
        self.plan = plan
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let email, let user = email.split(separator: "@").first { return String(user) }
        return ""
    }

    public var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    public static func load(from authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")) -> AccountProfile {
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            return AccountProfile()
        }
        for value in root.values {
            guard let dict = value as? [String: Any] else { continue }
            let email = dict["email"] as? String
            let first = dict["first_name"] as? String ?? ""
            let last = dict["last_name"] as? String ?? ""
            let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if email != nil || !combined.isEmpty {
                let teamID = dict["team_id"] as? String
                let plan = inferredPlan(from: dict)
                return AccountProfile(
                    email: email,
                    name: combined.isEmpty ? nil : combined,
                    userID: dict["user_id"] as? String,
                    teamID: teamID,
                    plan: plan
                )
            }
        }
        return AccountProfile()
    }

    private static func inferredPlan(from dict: [String: Any]) -> SubscriptionPlan {
        let blobs = [
            dict["plan"] as? String,
            dict["subscription"] as? String,
            dict["product"] as? String,
            dict["tier"] as? String,
            dict["principal_type"] as? String
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        if blobs.contains("heavy") { return .superGrokHeavy }
        if blobs.contains("super") { return .superGrok }
        if let team = dict["team_id"] as? String, !team.isEmpty {
            return .superGrok
        }
        return .grok
    }
}

public struct SkillRecord: Identifiable, Hashable, Sendable {
    public var id: String { slug }
    public var slug: String
    public var title: String
    public var detail: String
    public var icon: String
    public var directory: URL?

    public init(slug: String, title: String, detail: String, icon: String, directory: URL? = nil) {
        self.slug = slug
        self.title = title
        self.detail = detail
        self.icon = icon
        self.directory = directory
    }
}

public struct SkillCatalog: Sendable {
    public init() {}

    public func load() -> [SkillRecord] {
        var records: [SkillRecord] = []
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/skills"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bundled/skills")
        ]
        let preferred = ["docx", "pdf", "pptx", "xlsx", "create-skill"]
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for folder in names where folder.hasDirectoryPath {
                let skillFile = folder.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
                records.append(parse(skillFile: skillFile, folder: folder))
            }
        }
        records.sort { lhs, rhs in
            let li = preferred.firstIndex(of: lhs.slug) ?? 1000
            let ri = preferred.firstIndex(of: rhs.slug) ?? 1000
            if li != ri { return li < ri }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return records
    }

    private func parse(skillFile: URL, folder: URL) -> SkillRecord {
        let slug = folder.lastPathComponent
        let text = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
        var name = prettyTitle(slug)
        var detail = ""
        if text.hasPrefix("---") {
            let parts = text.components(separatedBy: "---")
            if parts.count >= 3 {
                let front = parts[1]
                if let line = front.split(separator: "\n").first(where: { $0.hasPrefix("name:") }) {
                    name = prettyTitle(line.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces))
                }
                if let range = front.range(of: "description:") {
                    var desc = String(front[range.upperBound...])
                    desc = desc.replacingOccurrences(of: ">-", with: "")
                    desc = desc.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("name:") && !$0.isEmpty }.joined(separator: " ")
                    detail = String(desc.prefix(140))
                }
            }
        }
        return SkillRecord(slug: slug, title: name, detail: detail, icon: icon(for: slug), directory: folder)
    }

    private func prettyTitle(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func icon(for slug: String) -> String {
        switch slug {
        case "docx": return "doc.text"
        case "pdf": return "doc.richtext"
        case "pptx": return "rectangle.on.rectangle"
        case "xlsx": return "tablecells"
        case "create-skill": return "sparkle"
        default: return "puzzlepiece.extension"
        }
    }
}

public struct AutomationRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var prompt: String
    public var suggested: Bool

    public init(id: String = UUID().uuidString, title: String, detail: String, prompt: String, suggested: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.prompt = prompt
        self.suggested = suggested
    }
}

public struct AutomationStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GrokDesktop", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.fileURL = root.appendingPathComponent("automations.json")
        }
    }

    public func load() -> [AutomationRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([AutomationRecord].self, from: data)
        else {
            return []
        }
        return records
    }

    public func save(_ records: [AutomationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func suggested(language: String) -> [AutomationRecord] {
        let zh = language == "zh"
        return [
            AutomationRecord(
                id: "suggest-email",
                title: zh ? "邮件自动回复" : "Email Auto-Responder",
                detail: zh ? "为重要邮件线程起草简洁回复。" : "Draft concise replies for important email threads.",
                prompt: "/loop 1d draft concise replies for important unread email threads",
                suggested: true
            ),
            AutomationRecord(
                id: "suggest-stock",
                title: zh ? "每日股市追踪" : "Daily Stock Tracker",
                detail: zh ? "追踪行情、价格、情绪与新闻。" : "Track market updates, prices, sentiment, and news.",
                prompt: "/loop 1d summarize today's market moves, prices and sentiment",
                suggested: true
            ),
            AutomationRecord(
                id: "suggest-tasks",
                title: zh ? "任务提取" : "Task Extractor",
                detail: zh ? "从最近消息里抽出待办。" : "Extract action items from recent messages and notes.",
                prompt: "/loop 1d extract action items from today's conversation and notes",
                suggested: true
            )
        ]
    }
}

public struct NamedProject: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var path: String

    public init(id: String = UUID().uuidString, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct ProjectStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GrokDesktop", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.fileURL = root.appendingPathComponent("projects.json")
        }
    }

    public func load() -> [NamedProject] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([NamedProject].self, from: data)
        else {
            return []
        }
        return records
    }

    public func save(_ records: [NamedProject]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
