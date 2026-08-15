import Foundation

public enum ChatBlock: Equatable, Sendable {
    case prose(String)
    case code(language: String, text: String)
}

public enum ChatMarkdown {
    public static func blocks(in text: String) -> [ChatBlock] {
        var result: [ChatBlock] = []
        var remainder = text[...]
        while let start = remainder.range(of: "```") {
            let before = String(remainder[..<start.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.prose(before))
            }
            remainder = remainder[start.upperBound...]
            let languageLine = remainder.prefix(while: { $0 != "\n" })
            let language = String(languageLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if let newline = remainder.firstIndex(of: "\n") {
                remainder = remainder[remainder.index(after: newline)...]
            } else {
                remainder = remainder[languageLine.endIndex...]
            }
            if let end = remainder.range(of: "```") {
                result.append(.code(language: language, text: String(remainder[..<end.lowerBound]).trimmingCharacters(in: .newlines)))
                remainder = remainder[end.upperBound...]
                if remainder.first == "\n" {
                    remainder = remainder.dropFirst()
                }
            } else {
                result.append(.code(language: language, text: String(remainder).trimmingCharacters(in: .newlines)))
                remainder = ""
            }
        }
        let tail = String(remainder)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.prose(tail))
        }
        if result.isEmpty, !text.isEmpty {
            result.append(.prose(text))
        }
        return result
    }
}

public enum ToolKind: String, Sendable {
    case read
    case list
    case search
    case edit
    case run
    case todo
    case other
}

public struct ToolLine: Equatable, Sendable {
    public var kind: ToolKind
    public var verb: String
    public var target: String
    public var location: String?

    public init(kind: ToolKind, verb: String, target: String, location: String? = nil) {
        self.kind = kind
        self.verb = verb
        self.target = target
        self.location = location
    }

    public var headline: String {
        target.isEmpty ? verb : "\(verb) \(target)"
    }
}

public enum ToolVoice {
    public static func kind(_ title: String) -> ToolKind {
        line(title, chinese: false).kind
    }

    public static func headline(_ title: String, chinese: Bool, cwd: URL? = nil) -> String {
        line(title, chinese: chinese, cwd: cwd).headline
    }

    public static func line(_ title: String, chinese: Bool, cwd: URL? = nil) -> ToolLine {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolLine(kind: .other, verb: chinese ? "工具" : "Tool", target: "")
        }

        let lower = trimmed.lowercased()
        if lower == "todo" || lower.hasPrefix("todo ") || matches(lower, ["todo_write", "updating plan"]) {
            return ToolLine(kind: .todo, verb: chinese ? "更新任务" : "Updated tasks", target: "")
        }

        if let parsed = parseCLITitle(trimmed) {
            return decorate(parsed, chinese: chinese, cwd: cwd)
        }

        if let named = parseNamedTool(trimmed, lower: lower) {
            return decorate(named, chinese: chinese, cwd: cwd)
        }

        if looksLikeSearchPattern(trimmed) {
            return ToolLine(
                kind: .search,
                verb: verb(.search, chinese: chinese),
                target: shortenCommand(trimmed)
            )
        }

        return ToolLine(kind: .other, verb: trimmed, target: "")
    }

    public static func groupHeadline(kind: ToolKind, count: Int, chinese: Bool) -> String {
        switch kind {
        case .read:
            return chinese ? "读 \(count) 个文件" : "Read \(count) files"
        case .list:
            return chinese ? "列 \(count) 个目录" : "List \(count) folders"
        case .search:
            return chinese ? "搜 \(count) 次" : "Search \(count) times"
        case .edit:
            return chinese ? "改 \(count) 个文件" : "Edited \(count) files"
        case .run:
            return chinese ? "跑 \(count) 条命令" : "Ran \(count) commands"
        case .todo:
            return chinese ? "更新任务" : "Updated tasks"
        case .other:
            return chinese ? "\(count) 个步骤" : "\(count) steps"
        }
    }

    public static func statusLabel(_ status: String, chinese: Bool) -> String {
        switch status {
        case "completed":
            return chinese ? "完成" : "Done"
        case "failed":
            return chinese ? "失败" : "Failed"
        case "cancelled":
            return chinese ? "已停止" : "Stopped"
        case "running", "in_progress", "pending":
            return chinese ? "进行中" : "Working"
        default:
            return chinese ? "待办" : status
        }
    }

    public static func isActive(_ status: String) -> Bool {
        status == "running" || status == "in_progress" || status == "pending"
    }

    private static func decorate(_ line: ToolLine, chinese: Bool, cwd: URL?) -> ToolLine {
        let location = line.location.flatMap { $0.isEmpty ? nil : $0 }
        let target: String
        if let location {
            target = displayPath(location, cwd: cwd)
        } else if line.kind == .run {
            target = shortenCommand(line.target)
        } else if line.kind == .search {
            target = shortenCommand(line.target)
        } else if looksLikePath(line.target) {
            target = displayPath(line.target, cwd: cwd)
        } else {
            target = line.target
        }
        return ToolLine(
            kind: line.kind,
            verb: verb(line.kind, chinese: chinese),
            target: target,
            location: location ?? (looksLikePath(line.target) ? line.target : nil)
        )
    }

    private static func verb(_ kind: ToolKind, chinese: Bool) -> String {
        switch kind {
        case .read: return chinese ? "读" : "Read"
        case .list: return chinese ? "列" : "List"
        case .search: return chinese ? "搜" : "Search"
        case .edit: return chinese ? "改" : "Edited"
        case .run: return chinese ? "跑" : "Ran"
        case .todo: return chinese ? "更新任务" : "Updated tasks"
        case .other: return chinese ? "工具" : "Tool"
        }
    }

    private static func parseCLITitle(_ title: String) -> ToolLine? {
        guard let space = title.firstIndex(of: " ") else { return nil }
        let head = String(title[..<space])
        let body = String(title[title.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard let kind = kind(fromVerb: head), !body.isEmpty else { return nil }
        if let tick = backtickBody(body) {
            return ToolLine(kind: kind, verb: head, target: tick, location: kind == .run ? nil : tick)
        }
        return ToolLine(kind: kind, verb: head, target: body, location: looksLikePath(body) ? body : nil)
    }

    private static func parseNamedTool(_ title: String, lower: String) -> ToolLine? {
        let mappings: [(needles: [String], kind: ToolKind)] = [
            (["read_file", "read file"], .read),
            (["list_dir", "list files", "list_file"], .list),
            (["search_replace", "apply_patch", "str_replace", "write_file", "edit_file"], .edit),
            (["run_terminal", "run command"], .run),
            (["grep", "rg "], .search)
        ]
        for mapping in mappings {
            if let needle = mapping.needles.first(where: { lower.contains($0) }) {
                let rest = strip(needle, from: title)
                return ToolLine(
                    kind: mapping.kind,
                    verb: mapping.kind.rawValue,
                    target: rest,
                    location: looksLikePath(rest) ? rest : nil
                )
            }
        }
        if matches(lower, ["write", "edit", "patch"]) {
            let rest = leftover(from: title)
            return ToolLine(kind: .edit, verb: "edit", target: rest, location: looksLikePath(rest) ? rest : nil)
        }
        return nil
    }

    private static func strip(_ needle: String, from title: String) -> String {
        let lower = title.lowercased()
        guard let range = lower.range(of: needle) else { return leftover(from: title) }
        let start = title.index(title.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
        let end = title.index(start, offsetBy: needle.count)
        var rest = title
        rest.removeSubrange(start..<end)
        return rest.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")))
    }

    private static func kind(fromVerb raw: String) -> ToolKind? {
        switch raw.lowercased() {
        case "read", "cat", "open": return .read
        case "list", "ls": return .list
        case "search", "searched", "grep", "find": return .search
        case "edit", "edited", "write", "wrote": return .edit
        case "execute", "ran", "run": return .run
        default: return nil
        }
    }

    private static func leftover(from title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 { return String(parts[1]) }
        return ""
    }

    private static func backtickBody(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "`") else { return nil }
        let after = text.index(after: start)
        guard let end = text[after...].firstIndex(of: "`") else {
            return String(text[after...]).trimmingCharacters(in: .whitespaces)
        }
        return String(text[after..<end])
    }

    private static func displayPath(_ raw: String, cwd: URL?) -> String {
        let path = raw.trimmingCharacters(in: CharacterSet(charactersIn: "`\"' "))
        guard !path.isEmpty else { return raw }
        if let cwd {
            let cwdPath = cwd.path
            if path == cwdPath { return cwd.lastPathComponent }
            if path.hasPrefix(cwdPath + "/") {
                return String(path.dropFirst(cwdPath.count + 1))
            }
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" { return path }
        if path.contains("/"), url.pathComponents.count > 2 {
            let parent = url.deletingLastPathComponent().lastPathComponent
            if !parent.isEmpty, parent != "/", parent != "." {
                return "\(parent)/\(name)"
            }
        }
        return name
    }

    private static func shortenCommand(_ command: String) -> String {
        let oneLine = command
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 64 { return oneLine }
        return String(oneLine.prefix(63)) + "…"
    }

    private static func looksLikePath(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") { return true }
        if value.contains("://") { return false }
        return value.contains("/") || value.contains(".")
    }

    private static func looksLikeSearchPattern(_ text: String) -> Bool {
        text.contains("|") || text.contains(".*") || text.contains("\\b")
    }

    private static func matches(_ lower: String, _ needles: [String]) -> Bool {
        needles.contains { lower.contains($0) }
    }
}
