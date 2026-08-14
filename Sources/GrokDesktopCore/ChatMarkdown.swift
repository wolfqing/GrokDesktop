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

public enum ToolVoice {
    public static func headline(_ title: String, chinese: Bool) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return chinese ? "工具" : "Tool" }
        let lower = trimmed.lowercased()
        let rest = leftover(from: trimmed)
        if matches(lower, ["read_file", "read file", "read ", "cat ", "open "]) {
            return chinese ? "读了 \(rest)" : "Read \(rest)"
        }
        if matches(lower, ["search_replace", "write", "edit", "apply_patch", "str_replace"]) {
            return chinese ? "改了 \(rest)" : "Edited \(rest)"
        }
        if matches(lower, ["grep", "search", "find ", "rg "]) {
            return chinese ? "搜了 \(rest)" : "Searched \(rest)"
        }
        if matches(lower, ["run_terminal", "run ", "bash", "shell", "command"]) {
            return chinese ? "跑了 \(rest)" : "Ran \(rest)"
        }
        if matches(lower, ["todo", "plan"]) {
            return chinese ? "更新了任务" : "Updated tasks"
        }
        return trimmed
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

    private static func leftover(from title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 { return String(parts[1]) }
        return cleaned
    }

    private static func matches(_ lower: String, _ needles: [String]) -> Bool {
        needles.contains { lower.contains($0) }
    }
}
