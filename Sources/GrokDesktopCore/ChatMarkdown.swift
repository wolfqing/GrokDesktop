import Foundation

public enum ChatTableAlignment: String, Equatable, Sendable {
    case leading
    case center
    case trailing
}

public struct ChatTable: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]
    public var alignments: [ChatTableAlignment]

    public init(headers: [String], rows: [[String]], alignments: [ChatTableAlignment] = []) {
        self.headers = headers
        self.rows = rows
        if alignments.count == headers.count {
            self.alignments = alignments
        } else {
            self.alignments = Array(repeating: .leading, count: headers.count)
        }
    }

    public var columnCount: Int { headers.count }
}

public enum ChatBlock: Equatable, Sendable {
    case prose(String)
    case heading(level: Int, text: String)
    case table(ChatTable)
    case code(language: String, text: String)
}

public enum ChatMarkdown {
    public static func blocks(in text: String) -> [ChatBlock] {
        var result: [ChatBlock] = []
        var remainder = text[...]
        while let start = remainder.range(of: "```") {
            let before = String(remainder[..<start.lowerBound])
            result.append(contentsOf: splitProse(before))
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
        result.append(contentsOf: splitProse(String(remainder)))
        if result.isEmpty, !text.isEmpty {
            result.append(.prose(text))
        }
        return result
    }

    public static func splitProse(_ text: String) -> [ChatBlock] {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var blocks: [ChatBlock] = []
        var paragraph: [String] = []
        var tableLines: [String] = []
        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.prose(joined))
            }
            paragraph = []
        }
        func flushTable() {
            if let table = parseTable(tableLines) {
                flushParagraph()
                blocks.append(.table(table))
            } else {
                paragraph.append(contentsOf: tableLines)
            }
            tableLines = []
        }
        for raw in trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if isTableLine(line) {
                tableLines.append(line)
                continue
            }
            if !tableLines.isEmpty { flushTable() }
            if let heading = heading(in: line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        if !tableLines.isEmpty { flushTable() }
        flushParagraph()
        return blocks
    }

    public static func parseTable(_ lines: [String]) -> ChatTable? {
        let rows = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rows.count >= 2, isSeparatorRow(rows[1]) else { return nil }
        let headers = cells(in: rows[0])
        let alignments = alignments(in: rows[1])
        guard headers.count >= 2, alignments.count >= 2 else { return nil }
        let width = headers.count
        var body: [[String]] = []
        for line in rows.dropFirst(2) {
            guard isTableRow(line), !isSeparatorRow(line) else { return nil }
            body.append(padded(cells(in: line), to: width))
        }
        return ChatTable(headers: padded(headers, to: width), rows: body, alignments: padded(alignments, to: width, fill: .leading))
    }

    public static func isTableLine(_ line: String) -> Bool {
        isTableRow(line) || isSeparatorRow(line)
    }

    public static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        if heading(in: trimmed) != nil { return false }
        return cells(in: trimmed).count >= 2
    }

    public static func isSeparatorRow(_ line: String) -> Bool {
        let parts = cells(in: line)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { cell in
            let token = cell.replacingOccurrences(of: " ", with: "")
            guard token.count >= 3 else { return false }
            let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
        }
    }

    public static func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...3).contains(level), trimmed.count > level else { return nil }
        let mark = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard trimmed[mark].isWhitespace else { return nil }
        let title = trimmed[trimmed.index(after: mark)...].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (level, title)
    }

    public static func cells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    public static func alignments(in line: String) -> [ChatTableAlignment] {
        cells(in: line).map { cell in
            let token = cell.replacingOccurrences(of: " ", with: "")
            let left = token.hasPrefix(":")
            let right = token.hasSuffix(":")
            if left && right { return .center }
            if right { return .trailing }
            return .leading
        }
    }

    private static func padded(_ cells: [String], to count: Int) -> [String] {
        if cells.count >= count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func padded(_ alignments: [ChatTableAlignment], to count: Int, fill: ChatTableAlignment) -> [ChatTableAlignment] {
        if alignments.count >= count { return Array(alignments.prefix(count)) }
        return alignments + Array(repeating: fill, count: count - alignments.count)
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
