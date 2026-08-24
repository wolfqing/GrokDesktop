import Foundation

public struct QueuedPrompt: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var kind: Kind

    public enum Kind: String, Sendable {
        case followUp
        case aside
    }

    public init(id: String = UUID().uuidString, text: String, kind: Kind) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var items: [ConversationItem] = []
    public var planEntries: [PlanEntry] = []
    public var itemDates: [String: Date] = [:]
    public var itemImages: [String: [URL]] = [:]
    public var todos: [AgentTodo] = []
    public var tasks: [AgentTask] = []
    public var assistantID: String?
    public var thoughtID: String?
    public var recap: String = ""
    public var compacted: Bool = false
    public var subagents: [AgentSubagent] = []
    public var itemDurations: [String: TimeInterval] = [:]

    public init(
        items: [ConversationItem] = [],
        planEntries: [PlanEntry] = [],
        itemDates: [String: Date] = [:],
        itemImages: [String: [URL]] = [:],
        todos: [AgentTodo] = [],
        tasks: [AgentTask] = [],
        assistantID: String? = nil,
        thoughtID: String? = nil,
        recap: String = "",
        compacted: Bool = false,
        subagents: [AgentSubagent] = [],
        itemDurations: [String: TimeInterval] = [:]
    ) {
        self.items = items
        self.planEntries = planEntries
        self.itemDates = itemDates
        self.itemImages = itemImages
        self.todos = todos
        self.tasks = tasks
        self.assistantID = assistantID
        self.thoughtID = thoughtID
        self.recap = recap
        self.compacted = compacted
        self.subagents = subagents
        self.itemDurations = itemDurations
    }

    public var lastUserPreview: String {
        items.reversed().compactMap { item -> String? in
            guard case .user(_, let text) = item else { return nil }
            let shown = TranscriptLoader.displayUserText(text)
            return shown.isEmpty ? nil : shown
        }.first ?? ""
    }

    public var liveTasks: [AgentTask] { tasks.filter(\.isRunning) }
    public var finishedTasks: [AgentTask] { tasks.filter { !$0.isRunning } }
    public var liveSubagents: [AgentSubagent] { subagents.filter(\.isRunning) }
}

public enum SessionFold {
    public static func userTurn(_ text: String, at date: Date = Date()) -> SessionUpdate {
        SessionUpdate(
            kind: .userMessageChunk,
            text: text,
            timestamp: date,
            imageURLs: PromptMedia.imageURLs(in: text)
        )
    }

    public static func notice(_ text: String, at date: Date = Date()) -> SessionUpdate {
        SessionUpdate(kind: .notice, text: text, timestamp: date)
    }

    public static func apply(_ update: SessionUpdate, onto snapshot: inout SessionSnapshot) {
        TranscriptLoader.apply(
            update: update,
            items: &snapshot.items,
            planEntries: &snapshot.planEntries,
            assistantID: &snapshot.assistantID,
            thoughtID: &snapshot.thoughtID,
            itemDates: &snapshot.itemDates,
            itemImages: &snapshot.itemImages,
            todos: &snapshot.todos,
            tasks: &snapshot.tasks
        )
        switch update.kind {
        case .sessionRecap:
            let summary = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty { snapshot.recap = summary }
        case .turnCompleted:
            TurnTiming.stamp(
                onto: &snapshot.itemDurations,
                items: snapshot.items,
                dates: snapshot.itemDates,
                startedAt: nil,
                endedAt: update.timestamp ?? Date()
            )
        case .autoCompactCompleted:
            snapshot.compacted = true
        case .subagentSpawned, .subagentFinished:
            PromptTimestamp.applySubagent(from: update, into: &snapshot.subagents)
        case .retryState:
            appendNotice(retryText(update), onto: &snapshot, at: update.timestamp)
        case .scheduledTaskCreated:
            let prompt = update.raw["prompt"] as? String ?? update.text
            let schedule = update.raw["human_schedule"] as? String ?? ""
            let label = schedule.isEmpty ? prompt : "\(schedule): \(prompt)"
            appendNotice(String(label.prefix(180)), onto: &snapshot, at: update.timestamp)
        default:
            break
        }
    }

    public static func cancelActiveWork(onto snapshot: inout SessionSnapshot, at date: Date = Date()) {
        for index in snapshot.items.indices {
            if case .tool(let id, let title, let status, let detail) = snapshot.items[index],
               status == "running" || status == "pending" || status == "in_progress" {
                snapshot.items[index] = .tool(id: id, title: title, status: "cancelled", detail: detail)
            }
        }
        for index in snapshot.todos.indices where snapshot.todos[index].isActive {
            snapshot.todos[index].status = "cancelled"
        }
        for index in snapshot.tasks.indices where snapshot.tasks[index].isRunning {
            snapshot.tasks[index].status = "cancelled"
            snapshot.tasks[index].endedAt = date
        }
        for index in snapshot.subagents.indices where snapshot.subagents[index].isRunning {
            snapshot.subagents[index].status = "cancelled"
        }
    }

    public static func isAside(_ text: String) -> Bool {
        SlashBuiltins.name(in: text) == "/btw"
    }

    public static func applyGoal(_ text: String, enabled: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("/") { return trimmed }
        return "/goal \(trimmed)"
    }

    public static func apply(_ updates: [SessionUpdate]) -> SessionSnapshot {
        var snapshot = SessionSnapshot()
        for update in updates {
            apply(update, onto: &snapshot)
        }
        return snapshot
    }

    private static func appendNotice(_ text: String, onto snapshot: inout SessionSnapshot, at date: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if snapshot.items.last.map({
            if case .notice(_, let existing) = $0 { return existing == trimmed }
            return false
        }) == true {
            return
        }
        let id = UUID().uuidString
        snapshot.items.append(.notice(id: id, text: trimmed))
        if let date { snapshot.itemDates[id] = date }
    }

    private static func retryText(_ update: SessionUpdate) -> String {
        let type = update.raw["type"] as? String ?? ""
        guard type == "retrying" || type.isEmpty else { return "" }
        let attempt = update.raw["attempt"] as? Int ?? 0
        let max = update.raw["max_retries"] as? Int ?? 0
        let reason = update.raw["reason"] as? String ?? update.text
        if attempt > 0, max > 0 {
            return "Retrying (\(attempt)/\(max)): \(reason)"
        }
        return reason.isEmpty ? "" : "Retrying: \(reason)"
    }
}

public extension SessionWorkspace {
    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            items: items,
            planEntries: planEntries,
            itemDates: itemDates,
            itemImages: itemImages,
            todos: todos,
            tasks: tasks,
            assistantID: assistantBufferID,
            thoughtID: thoughtBufferID,
            recap: recap,
            compacted: compacted,
            subagents: subagents,
            itemDurations: itemDurations
        )
    }

    func adopt(_ snapshot: SessionSnapshot) {
        items = snapshot.items
        planEntries = snapshot.planEntries
        itemDates = snapshot.itemDates
        itemImages = snapshot.itemImages
        todos = snapshot.todos
        tasks = snapshot.tasks
        assistantBufferID = snapshot.assistantID
        thoughtBufferID = snapshot.thoughtID
        recap = snapshot.recap
        compacted = snapshot.compacted
        subagents = snapshot.subagents
        itemDurations = snapshot.itemDurations
    }

    func adopt(_ transcript: Transcript) {
        adopt(transcript.snapshot)
        if !transcript.planMarkdown.isEmpty {
            planMarkdown = transcript.planMarkdown
        }
        if !transcript.hunks.isEmpty {
            hunks = transcript.hunks
        }
    }

    func fold(_ update: SessionUpdate) {
        var next = snapshot()
        SessionFold.apply(update, onto: &next)
        adopt(next)
    }
}
