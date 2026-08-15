import Foundation

public struct ChatSearchHit: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var snippet: String
    public var kind: String

    public init(id: String, title: String, snippet: String, kind: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.kind = kind
    }
}

public enum ChatSearch {
    public static func hits(in items: [ConversationItem], query: String, limit: Int = 40) -> [ChatSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return timeline(in: items) }
        var result: [ChatSearchHit] = []
        for item in items.reversed() {
            let blob = text(of: item)
            guard blob.localizedCaseInsensitiveContains(needle) else { continue }
            result.append(
                ChatSearchHit(
                    id: item.id,
                    title: label(of: item),
                    snippet: snippet(blob, around: needle),
                    kind: kind(of: item)
                )
            )
            if result.count >= limit { break }
        }
        return result
    }

    public static func timeline(in items: [ConversationItem], limit: Int = 80) -> [ChatSearchHit] {
        var result: [ChatSearchHit] = []
        var index = 0
        for item in items {
            guard case .user(_, let text) = item else { continue }
            index += 1
            let shown = TranscriptLoader.displayUserText(text)
            result.append(
                ChatSearchHit(
                    id: item.id,
                    title: "Turn \(index)",
                    snippet: String(shown.prefix(160)),
                    kind: "user"
                )
            )
        }
        if result.count > limit {
            result = Array(result.suffix(limit))
        }
        return result.reversed()
    }

    public static func rewindTurns(in items: [ConversationItem], dates: [String: Date] = [:]) -> [RewindTurn] {
        var turns: [RewindTurn] = []
        var index = 0
        for item in items {
            guard case .user(let id, let text) = item else { continue }
            let shown = TranscriptLoader.displayUserText(text)
            guard !shown.isEmpty else { continue }
            turns.append(
                RewindTurn(
                    promptIndex: index,
                    itemID: id,
                    text: shown,
                    date: dates[id]
                )
            )
            index += 1
        }
        return turns
    }

    private static func text(of item: ConversationItem) -> String {
        switch item {
        case .user(_, let text), .assistant(_, let text, _), .thought(_, let text), .notice(_, let text):
            return text
        case .tool(_, let title, _, let detail):
            return title + "\n" + detail
        }
    }

    private static func label(of item: ConversationItem) -> String {
        switch item {
        case .user: return "You"
        case .assistant: return "Grok"
        case .thought: return "Thinking"
        case .tool(_, let title, _, _): return title
        case .notice: return "Notice"
        }
    }

    private static func kind(of item: ConversationItem) -> String {
        switch item {
        case .user: return "user"
        case .assistant: return "assistant"
        case .thought: return "thought"
        case .tool: return "tool"
        case .notice: return "notice"
        }
    }

    private static func snippet(_ text: String, around needle: String) -> String {
        let folded = text as NSString
        let range = folded.range(of: needle, options: [.caseInsensitive])
        guard range.location != NSNotFound else { return String(text.prefix(160)) }
        let start = max(range.location - 40, 0)
        let end = min(range.location + range.length + 80, folded.length)
        var slice = folded.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\n", with: " ")
        if start > 0 { slice = "…" + slice }
        if end < folded.length { slice += "…" }
        return slice
    }
}

public struct RewindTurn: Identifiable, Hashable, Sendable {
    public var id: String { "\(promptIndex)-\(itemID)" }
    public var promptIndex: Int
    public var itemID: String
    public var text: String
    public var date: Date?

    public init(promptIndex: Int, itemID: String, text: String, date: Date? = nil) {
        self.promptIndex = promptIndex
        self.itemID = itemID
        self.text = text
        self.date = date
    }
}

public enum RewindPoints {
    public static func load(sessionDirectory: URL, limit: Int = 80) -> [Int] {
        let url = sessionDirectory.appendingPathComponent("rewind_points.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var indexes: [Int] = []
        if let size = try? handle.seekToEnd(), size > 512_000 {
            try? handle.seek(toOffset: size - 512_000)
        } else {
            try? handle.seek(toOffset: 0)
        }
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let head = line.prefix(180)
            guard let range = head.range(of: "\"prompt_index\"") else { continue }
            let after = head[range.upperBound...]
            let digits = after.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
            if let value = Int(digits) {
                indexes.append(value)
            }
        }
        if indexes.count > limit {
            indexes = Array(indexes.suffix(limit))
        }
        return indexes
    }
}
