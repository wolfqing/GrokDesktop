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

    public static func stamp(
        onto stored: inout [String: TimeInterval],
        items: [ConversationItem],
        dates: [String: Date],
        startedAt: Date?,
        endedAt: Date
    ) {
        guard let assistant = items.last(where: {
            if case .assistant = $0 { return true }
            return false
        }) else { return }
        guard stored[assistant.id] == nil else { return }
        let userDate = items.last(where: {
            if case .user = $0 { return true }
            return false
        }).flatMap { dates[$0.id] }
        guard let start = startedAt ?? userDate else { return }
        let span = endedAt.timeIntervalSince(start)
        if span >= 0.5 {
            stored[assistant.id] = span
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
}
