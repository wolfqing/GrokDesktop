import Foundation

public struct AsideTurn: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var question: String
    public var answer: String
    public var pending: Bool
    public var queued: Bool

    public init(id: String, question: String, answer: String, pending: Bool, queued: Bool) {
        self.id = id
        self.question = question
        self.answer = answer
        self.pending = pending
        self.queued = queued
    }
}

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
    public var hookEvents: [HookEvent] = []
    public var checkpoints: [CompactionCheckpoint] = []
    public var scheduledTasks: [ScheduledTask] = []

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
        itemDurations: [String: TimeInterval] = [:],
        hookEvents: [HookEvent] = [],
        checkpoints: [CompactionCheckpoint] = [],
        scheduledTasks: [ScheduledTask] = []
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
        self.hookEvents = hookEvents
        self.checkpoints = checkpoints
        self.scheduledTasks = scheduledTasks
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
        let previousThought = snapshot.thoughtID
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
        if let previousThought, snapshot.thoughtID != previousThought {
            TurnTiming.stampThought(
                id: previousThought,
                onto: &snapshot.itemDurations,
                dates: snapshot.itemDates,
                endedAt: update.timestamp ?? Date()
            )
        }
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
            let task = HarnessEvents.scheduledTask(from: update)
            if !snapshot.scheduledTasks.contains(where: { $0.id == task.id }) {
                snapshot.scheduledTasks.insert(task, at: 0)
                if snapshot.scheduledTasks.count > 20 {
                    snapshot.scheduledTasks = Array(snapshot.scheduledTasks.prefix(20))
                }
            }
            appendNotice(String(task.title.prefix(180)), onto: &snapshot, at: update.timestamp)
        case .scheduledTaskDeleted:
            let id = HarnessEvents.scheduledTaskID(from: update)
            snapshot.scheduledTasks.removeAll { $0.id == id }
        case .hookExecution:
            snapshot.hookEvents.insert(HarnessEvents.hookEvent(from: update), at: 0)
            if snapshot.hookEvents.count > 40 {
                snapshot.hookEvents = Array(snapshot.hookEvents.prefix(40))
            }
        case .compactionCheckpoint:
            let point = HarnessEvents.checkpoint(from: update)
            if !snapshot.checkpoints.contains(where: { $0.id == point.id }) {
                snapshot.checkpoints.insert(point, at: 0)
            }
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

    public static func asidePrompt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if isAside(trimmed) { return trimmed }
        return "/btw \(trimmed)"
    }

    public static func asideDisplay(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAside(trimmed) else { return trimmed }
        let rest = trimmed.drop(while: { !$0.isWhitespace }).drop(while: { $0.isWhitespace })
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func belongsToAside(_ item: ConversationItem, items: [ConversationItem]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        for candidate in items[...index].reversed() {
            if case .user(_, let text) = candidate {
                return isAside(text)
            }
        }
        return false
    }

    public static func asideTurns(
        items: [ConversationItem],
        queued: [QueuedPrompt] = []
    ) -> [AsideTurn] {
        var turns: [AsideTurn] = []
        var current: AsideTurn?
        for item in items {
            if case .user(let id, let text) = item, isAside(text) {
                if let current { turns.append(current) }
                current = AsideTurn(
                    id: id,
                    question: asideDisplay(text),
                    answer: "",
                    pending: true,
                    queued: false
                )
                continue
            }
            guard var open = current else { continue }
            switch item {
            case .assistant(_, let text, let done):
                if !text.isEmpty {
                    open.answer = open.answer.isEmpty ? text : open.answer + text
                }
                open.pending = !done
                current = open
            case .user:
                turns.append(open)
                current = nil
            default:
                break
            }
        }
        if let current { turns.append(current) }
        for prompt in queued where prompt.kind == .aside {
            turns.append(AsideTurn(
                id: prompt.id,
                question: asideDisplay(prompt.text),
                answer: "",
                pending: true,
                queued: true
            ))
        }
        return turns
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
            itemDurations: itemDurations,
            hookEvents: hookEvents,
            checkpoints: checkpoints,
            scheduledTasks: scheduledTasks
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
        hookEvents = snapshot.hookEvents
        checkpoints = snapshot.checkpoints
        scheduledTasks = snapshot.scheduledTasks
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
