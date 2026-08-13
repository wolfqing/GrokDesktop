import Foundation

public struct PlanEntry: Hashable, Identifiable, Sendable {
    public var id: String { content }
    public var content: String
    public var status: String
    public var priority: String

    public init(content: String, status: String = "pending", priority: String = "medium") {
        self.content = content
        self.status = status
        self.priority = priority
    }
}

public struct FileHunk: Hashable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var added: Int
    public var removed: Int

    public init(id: String, path: String, added: Int, removed: Int) {
        self.id = id
        self.path = path
        self.added = added
        self.removed = removed
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct Transcript: Sendable {
    public var items: [ConversationItem]
    public var planEntries: [PlanEntry]
    public var planMarkdown: String
    public var hunks: [FileHunk]
    public var itemDates: [String: Date]
    public var todos: [AgentTodo]
    public var tasks: [AgentTask]

    public init(
        items: [ConversationItem] = [],
        planEntries: [PlanEntry] = [],
        planMarkdown: String = "",
        hunks: [FileHunk] = [],
        itemDates: [String: Date] = [:],
        todos: [AgentTodo] = [],
        tasks: [AgentTask] = []
    ) {
        self.items = items
        self.planEntries = planEntries
        self.planMarkdown = planMarkdown
        self.hunks = hunks
        self.itemDates = itemDates
        self.todos = todos
        self.tasks = tasks
    }
}

public enum TranscriptLoader {
    public static func load(sessionDirectory: URL, limit: Int = 400) -> Transcript {
        let updates = sessionDirectory.appendingPathComponent("updates.jsonl")
        var items: [ConversationItem] = []
        var planEntries: [PlanEntry] = []
        var itemDates: [String: Date] = [:]
        var todos: [AgentTodo] = []
        var tasks: [AgentTask] = []
        var assistantID: String?
        var thoughtID: String?

        if let handle = try? FileHandle(forReadingFrom: updates) {
            defer { try? handle.close() }
            let data = handle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    continue
                }
                let params = payload["params"] as? [String: Any] ?? payload
                let update = SessionUpdate.parse(params: params, envelopeTimestamp: payload["timestamp"])
                apply(
                    update: update,
                    items: &items,
                    planEntries: &planEntries,
                    assistantID: &assistantID,
                    thoughtID: &thoughtID,
                    itemDates: &itemDates,
                    todos: &todos,
                    tasks: &tasks
                )
            }
        }

        if items.count > limit {
            items = Array(items.suffix(limit))
        }

        let planURL = sessionDirectory.appendingPathComponent("plan.md")
        let planMarkdown = (try? String(contentsOf: planURL, encoding: .utf8)) ?? ""
        return Transcript(
            items: items,
            planEntries: planEntries,
            planMarkdown: planMarkdown,
            hunks: loadHunks(sessionDirectory: sessionDirectory),
            itemDates: itemDates,
            todos: todos,
            tasks: tasks
        )
    }

    public static func loadHunks(sessionDirectory: URL) -> [FileHunk] {
        let url = sessionDirectory.appendingPathComponent("hunk_records.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var merged: [String: FileHunk] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            let path = object["filePath"] as? String ?? ""
            guard !path.isEmpty else { continue }
            let added = object["linesAdded"] as? Int ?? 0
            let removed = object["linesRemoved"] as? Int ?? 0
            if var existing = merged[path] {
                existing.added += added
                existing.removed += removed
                merged[path] = existing
            } else {
                merged[path] = FileHunk(id: path, path: path, added: added, removed: removed)
            }
        }
        return merged.values.sorted { $0.path < $1.path }
    }

    public static func apply(
        update: SessionUpdate,
        items: inout [ConversationItem],
        planEntries: inout [PlanEntry],
        assistantID: inout String?,
        thoughtID: inout String?,
        itemDates: inout [String: Date],
        todos: inout [AgentTodo],
        tasks: inout [AgentTask]
    ) {
        let previous = Set(items.map(\.id))
        switch update.kind {
        case .userMessageChunk:
            assistantID = nil
            thoughtID = nil
            if let last = items.indices.last, case .user(let id, let text) = items[last] {
                items[last] = .user(id: id, text: text + update.text)
                if itemDates[id] == nil, let timestamp = update.timestamp {
                    itemDates[id] = timestamp
                }
            } else {
                items.append(.user(id: UUID().uuidString, text: update.text))
            }
        case .agentMessageChunk:
            thoughtID = nil
            append(kind: .assistant, text: update.text, items: &items, bufferID: &assistantID)
        case .agentThoughtChunk:
            append(kind: .thought, text: update.text, items: &items, bufferID: &thoughtID)
        case .toolCall, .toolCallUpdate:
            let id = update.toolCallId ?? UUID().uuidString
            if let index = items.firstIndex(where: { $0.id == id }) {
                if case .tool(_, let title, _, let detail) = items[index] {
                    items[index] = .tool(
                        id: id,
                        title: update.title.isEmpty ? title : update.title,
                        status: update.status ?? "running",
                        detail: update.text.isEmpty ? detail : update.text
                    )
                }
            } else {
                items.append(.tool(
                    id: id,
                    title: update.title.isEmpty ? "Tool" : update.title,
                    status: update.status ?? "running",
                    detail: update.text
                ))
            }
            assistantID = nil
            PromptTimestamp.applyTodos(from: update, into: &todos)
        case .plan:
            if !update.planEntries.isEmpty {
                planEntries = update.planEntries
            }
        case .taskBackgrounded, .taskCompleted:
            PromptTimestamp.applyTask(from: update, into: &tasks)
        case .turnCompleted, .unknown:
            assistantID = nil
            thoughtID = nil
        }
        if let timestamp = update.timestamp {
            for item in items where previous.contains(item.id) == false {
                itemDates[item.id] = timestamp
            }
        }
    }

    public static func markdown(from items: [ConversationItem], title: String) -> String {
        var lines = ["# \(title)", ""]
        for item in items {
            switch item {
            case .user(_, let text):
                lines.append("## User")
                lines.append(text)
                lines.append("")
            case .assistant(_, let text, _):
                lines.append("## Grok")
                lines.append(text)
                lines.append("")
            case .thought(_, let text):
                lines.append("<details><summary>Thinking</summary>")
                lines.append("")
                lines.append(text)
                lines.append("</details>")
                lines.append("")
            case .tool(_, let title, let status, let detail):
                lines.append("- **\(title)** (\(status))")
                if !detail.isEmpty {
                    lines.append("```")
                    lines.append(detail)
                    lines.append("```")
                }
            case .notice(_, let text):
                lines.append("_\(text)_")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private enum BufferKind { case assistant, thought }

    private static func append(
        kind: BufferKind,
        text: String,
        items: inout [ConversationItem],
        bufferID: inout String?
    ) {
        if let id = bufferID, let index = items.firstIndex(where: { $0.id == id }) {
            switch kind {
            case .assistant:
                if case .assistant(_, let existing, _) = items[index] {
                    items[index] = .assistant(id: id, text: existing + text, done: false)
                }
            case .thought:
                if case .thought(_, let existing) = items[index] {
                    items[index] = .thought(id: id, text: existing + text)
                }
            }
            return
        }
        let id = UUID().uuidString
        bufferID = id
        switch kind {
        case .assistant:
            items.append(.assistant(id: id, text: text, done: false))
        case .thought:
            items.append(.thought(id: id, text: text))
        }
    }
}
