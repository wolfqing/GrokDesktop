import Foundation

public enum TurnTiming {
    public static func seconds(
        forAssistant id: String,
        items: [ConversationItem],
        dates: [String: Date],
        stored: [String: TimeInterval]
    ) -> TimeInterval? {
        guard isTurnAnswer(id, in: items) else { return nil }
        if let stored = stored[id], stored >= 0.5 {
            return stored
        }
        return derived(forAssistant: id, items: items, dates: dates)
    }

    public static func isTurnAnswer(_ id: String, in items: [ConversationItem]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard case .assistant = items[index] else { return false }
        for item in items.suffix(from: index + 1) {
            if case .user = item { break }
            if case .assistant = item { return false }
        }
        return true
    }

    public static func seconds(
        forThought id: String,
        items: [ConversationItem],
        dates: [String: Date],
        stored: [String: TimeInterval],
        now: Date = Date(),
        running: Bool = false
    ) -> TimeInterval? {
        if let stored = stored[id], stored >= 0.05 {
            return stored
        }
        return derivedThought(id: id, items: items, dates: dates, now: now, running: running)
    }

    public static func stamp(
        onto stored: inout [String: TimeInterval],
        items: [ConversationItem],
        dates: [String: Date],
        startedAt: Date?,
        endedAt: Date
    ) {
        if let assistant = items.last(where: {
            if case .assistant = $0 { return true }
            return false
        }), stored[assistant.id] == nil {
            let userDate = items.last(where: {
                if case .user = $0 { return true }
                return false
            }).flatMap { dates[$0.id] }
            if let start = startedAt ?? userDate {
                let span = endedAt.timeIntervalSince(start)
                if span >= 0.5 {
                    stored[assistant.id] = span
                }
            }
        }
        stampThoughts(onto: &stored, items: items, dates: dates, endedAt: endedAt)
    }

    public static func stampThought(
        id: String,
        onto stored: inout [String: TimeInterval],
        dates: [String: Date],
        endedAt: Date
    ) {
        guard stored[id] == nil, let start = dates[id] else { return }
        let span = endedAt.timeIntervalSince(start)
        if span >= 0.05 {
            stored[id] = span
        }
    }

    public static func stampThoughts(
        onto stored: inout [String: TimeInterval],
        items: [ConversationItem],
        dates: [String: Date],
        endedAt: Date
    ) {
        for (index, item) in items.enumerated() {
            guard case .thought(let id, _) = item else { continue }
            guard stored[id] == nil, let start = dates[id] else { continue }
            var end = endedAt
            var cursor = index + 1
            while cursor < items.count {
                if case .thought = items[cursor] {
                    cursor += 1
                    continue
                }
                if let date = dates[items[cursor].id] {
                    end = date
                }
                break
            }
            let span = end.timeIntervalSince(start)
            if span >= 0.05 {
                stored[id] = span
            }
        }
    }

    private static func derived(
        forAssistant id: String,
        items: [ConversationItem],
        dates: [String: Date]
    ) -> TimeInterval? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        var userIndex: Int?
        for cursor in stride(from: index, through: 0, by: -1) {
            if case .user = items[cursor] {
                userIndex = cursor
                break
            }
        }
        guard let userIndex, let start = dates[items[userIndex].id] else { return nil }
        var end = dates[id] ?? start
        var cursor = userIndex + 1
        while cursor < items.count {
            if case .user = items[cursor] { break }
            if let date = dates[items[cursor].id], date > end {
                end = date
            }
            cursor += 1
        }
        let span = end.timeIntervalSince(start)
        return span >= 0.5 ? span : nil
    }

    private static func derivedThought(
        id: String,
        items: [ConversationItem],
        dates: [String: Date],
        now: Date,
        running: Bool
    ) -> TimeInterval? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard case .thought = items[index] else { return nil }
        guard let start = dates[id] else { return nil }
        var cursor = index + 1
        while cursor < items.count {
            if case .thought = items[cursor] {
                cursor += 1
                continue
            }
            if let date = dates[items[cursor].id] {
                let span = date.timeIntervalSince(start)
                return span >= 0.05 ? span : nil
            }
            break
        }
        guard running else { return nil }
        let span = now.timeIntervalSince(start)
        return span >= 0.05 ? span : nil
    }
}

public enum ThoughtVoice {
    public static func header(elapsed: TimeInterval?, running: Bool, chinese: Bool) -> String {
        if running {
            return chinese ? "思考中…" : "Thinking…"
        }
        if let elapsed, elapsed >= 0.05 {
            let clock = PromptTimestamp.formatCompactElapsed(elapsed)
            return chinese ? "思考了 \(clock)" : "Thought for \(clock)"
        }
        return chinese ? "思考" : "Thought"
    }

    public static func tail(_ text: String, maxLines: Int = 4) -> (ellipsis: Bool, lines: [String]) {
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count <= maxLines {
            return (false, Array(lines))
        }
        return (true, Array(lines.suffix(maxLines)))
    }
}
