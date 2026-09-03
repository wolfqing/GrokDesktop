import Foundation

public struct AgentTodo: Identifiable, Hashable, Sendable {
    public var id: String
    public var content: String
    public var status: String
    public var priority: String
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        id: String,
        content: String,
        status: String = "pending",
        priority: String = "medium",
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.priority = priority
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var isCancelled: Bool { status == "cancelled" }
    public var isDone: Bool { status == "completed" }
    public var isActive: Bool { status == "in_progress" }

    public var elapsed: TimeInterval? {
        PromptTimestamp.elapsed(from: startedAt, to: endedAt)
    }
}

public struct AgentTask: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var command: String
    public var status: String
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        id: String,
        title: String,
        command: String = "",
        status: String = "running",
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var isRunning: Bool { status == "running" || status == "in_progress" }

    public var elapsed: TimeInterval? {
        PromptTimestamp.elapsed(from: startedAt, to: endedAt)
    }
}

public struct AgentSubagent: Identifiable, Hashable, Sendable {
    public var id: String
    public var childSessionId: String
    public var type: String
    public var detail: String
    public var status: String
    public var toolCalls: Int
    public var turns: Int
    public var durationMs: Int
    public var output: String
    public var startedAt: Date?
    public var isolation: String

    public init(
        id: String,
        childSessionId: String = "",
        type: String = "",
        detail: String = "",
        status: String = "running",
        toolCalls: Int = 0,
        turns: Int = 0,
        durationMs: Int = 0,
        output: String = "",
        startedAt: Date? = nil,
        isolation: String = ""
    ) {
        self.id = id
        self.childSessionId = childSessionId
        self.type = type
        self.detail = detail
        self.status = status
        self.toolCalls = toolCalls
        self.turns = turns
        self.durationMs = durationMs
        self.output = output
        self.startedAt = startedAt
        self.isolation = isolation
    }

    public var isRunning: Bool { status == "running" || status == "in_progress" }

    public var elapsed: TimeInterval? {
        if durationMs > 0 { return Double(durationMs) / 1000 }
        return PromptTimestamp.elapsed(from: startedAt, to: nil)
    }
}

public enum PromptTimestamp {
    private static let dateLock = NSLock()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? Double {
            return fromEpoch(number)
        }
        if let number = value as? Int {
            return fromEpoch(Double(number))
        }
        if let number = value as? NSNumber {
            return fromEpoch(number.doubleValue)
        }
        if let text = value as? String {
            if let number = Double(text) { return fromEpoch(number) }
            dateLock.lock()
            defer { dateLock.unlock() }
            if let date = isoFractional.date(from: text) { return date }
            return isoBasic.date(from: text)
        }
        if let dict = value as? [String: Any] {
            if let secs = dict["secs_since_epoch"] as? Double {
                let nanos = (dict["nanos_since_epoch"] as? Double) ?? 0
                return Date(timeIntervalSince1970: secs + nanos / 1_000_000_000)
            }
            if let secs = dict["secs_since_epoch"] as? Int {
                let nanos = (dict["nanos_since_epoch"] as? Int) ?? 0
                return Date(timeIntervalSince1970: Double(secs) + Double(nanos) / 1_000_000_000)
            }
        }
        return nil
    }

    public static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func elapsed(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start else { return nil }
        return max((end ?? Date()).timeIntervalSince(start), 0)
    }

    public static func formatElapsed(_ value: TimeInterval, chinese: Bool = false) -> String {
        let total = max(Int(value.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if chinese {
            if hours > 0 { return "\(hours)小时\(minutes)分" }
            if minutes > 0 {
                return seconds > 0 ? "\(minutes)分\(seconds)秒" : "\(minutes)分"
            }
            return "\(seconds)秒"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// CLI turn/phase timer: `2.5s`, `13m26s`, `1h2m`.
    public static func formatCompactElapsed(_ value: TimeInterval) -> String {
        if value < 60 {
            return posixFormat("%.1fs", max(value, 0))
        }
        let total = max(Int(value.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m\(seconds)s"
    }

    /// CLI token chip: `12`, `1.23k`, `10.1k`, `130k`, `1.23m`.
    public static func compactCount(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 10_000 {
            return posixFormat("%.2fk", Double(value) / 1000)
        }
        if value < 100_000 {
            return posixFormat("%.1fk", Double(value) / 1000)
        }
        if value < 1_000_000 {
            return "\(value / 1000)k"
        }
        if value < 10_000_000 {
            return posixFormat("%.2fm", Double(value) / 1_000_000)
        }
        return posixFormat("%.1fm", Double(value) / 1_000_000)
    }

    private static func posixFormat(_ format: String, _ value: Double) -> String {
        String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public static func applyTodos(from update: SessionUpdate, into todos: inout [AgentTodo]) {
        if let output = update.raw["rawOutput"] as? [String: Any],
           let updated = output["TodosUpdated"] as? [String: Any] {
            if let state = updated["state"] as? [String: Any],
               let map = state["todos"] as? [String: Any] {
                let order = (updated["todos"] as? [[String: Any]])?.compactMap { $0["content"] as? String }
                let previous = todos
                let stamp = update.timestamp ?? Date()
                todos = map.compactMap { key, value in
                    guard let dict = value as? [String: Any] else { return nil }
                    var todo = previous.first(where: { $0.id == key }) ?? AgentTodo(
                        id: key,
                        content: dict["content"] as? String ?? "",
                        status: dict["status"] as? String ?? "pending",
                        priority: dict["priority"] as? String ?? "medium"
                    )
                    todo.content = dict["content"] as? String ?? todo.content
                    todo.priority = dict["priority"] as? String ?? todo.priority
                    let status = dict["status"] as? String ?? "pending"
                    stampTodo(&todo, status: status, at: stamp)
                    todo.status = status
                    return todo
                }
                if let order {
                    todos.sort { lhs, rhs in
                        let li = order.firstIndex(of: lhs.content) ?? .max
                        let ri = order.firstIndex(of: rhs.content) ?? .max
                        if li != ri { return li < ri }
                        return lhs.id < rhs.id
                    }
                } else {
                    todos.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
                }
                return
            }
            if let rows = updated["todos"] as? [[String: Any]] {
                mergeTodos(rows, merge: false, at: update.timestamp ?? Date(), into: &todos)
                return
            }
        }

        let input = update.raw["rawInput"] as? [String: Any]
        let tool = ((update.raw["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any])?["name"] as? String
        let isTodo = update.title == "todo_write"
            || tool == "todo_write"
            || input?["todos"] != nil
        guard isTodo, let rows = input?["todos"] as? [[String: Any]] else { return }
        mergeTodos(rows, merge: input?["merge"] as? Bool ?? false, at: update.timestamp ?? Date(), into: &todos)
    }

    public static func applyTask(from update: SessionUpdate, into tasks: inout [AgentTask]) {
        switch update.kind {
        case .taskBackgrounded:
            let id = update.raw["task_id"] as? String ?? update.toolCallId ?? UUID().uuidString
            let command = update.raw["command"] as? String ?? ""
            let title = update.raw["description"] as? String ?? command
            upsertTask(
                AgentTask(id: id, title: title.isEmpty ? command : title, command: command, status: "running", startedAt: update.timestamp ?? Date()),
                into: &tasks
            )
        case .taskCompleted:
            let snapshot = update.raw["task_snapshot"] as? [String: Any] ?? [:]
            let id = snapshot["task_id"] as? String ?? update.toolCallId ?? UUID().uuidString
            let command = snapshot["command"] as? String ?? ""
            let title = snapshot["description"] as? String ?? command
            upsertTask(
                AgentTask(
                    id: id,
                    title: title.isEmpty ? command : title,
                    command: command,
                    status: "completed",
                    startedAt: parse(snapshot["start_time"]) ?? update.timestamp,
                    endedAt: parse(snapshot["end_time"]) ?? update.timestamp ?? Date()
                ),
                into: &tasks
            )
        default:
            break
        }
    }

    public static func applySubagent(from update: SessionUpdate, into subagents: inout [AgentSubagent]) {
        let raw = update.raw
        let id = raw["subagent_id"] as? String
            ?? raw["child_session_id"] as? String
            ?? update.toolCallId
            ?? UUID().uuidString
        let child = raw["child_session_id"] as? String ?? id
        let type = raw["subagent_type"] as? String ?? ""
        let detail = raw["description"] as? String ?? raw["output"] as? String ?? ""
        let isolation = raw["isolation"] as? String ?? raw["isolation_mode"] as? String ?? ""
        switch update.kind {
        case .subagentSpawned:
            upsertSubagent(
                AgentSubagent(
                    id: id,
                    childSessionId: child,
                    type: type,
                    detail: detail,
                    status: "running",
                    startedAt: update.timestamp ?? Date(),
                    isolation: isolation
                ),
                into: &subagents
            )
        case .subagentFinished:
            upsertSubagent(
                AgentSubagent(
                    id: id,
                    childSessionId: child,
                    type: type,
                    detail: detail,
                    status: raw["status"] as? String ?? "completed",
                    toolCalls: raw["tool_calls"] as? Int ?? 0,
                    turns: raw["turns"] as? Int ?? 0,
                    durationMs: raw["duration_ms"] as? Int ?? 0,
                    output: raw["output"] as? String ?? "",
                    startedAt: update.timestamp,
                    isolation: isolation
                ),
                into: &subagents
            )
        default:
            break
        }
    }

    public static func progress(for todos: [AgentTodo]) -> (done: Int, total: Int) {
        let visible = todos.filter { !$0.isCancelled }
        return (visible.filter(\.isDone).count, visible.count)
    }

    private static func mergeTodos(_ rows: [[String: Any]], merge: Bool, at date: Date, into todos: inout [AgentTodo]) {
        let previous = todos
        if !merge { todos = [] }
        for (index, row) in rows.enumerated() {
            let id = row["id"] as? String ?? row["content"] as? String ?? String(index + 1)
            let content = row["content"] as? String
            let status = row["status"] as? String ?? "pending"
            let priority = row["priority"] as? String ?? "medium"
            if let existing = todos.firstIndex(where: { $0.id == id }) {
                stampTodo(&todos[existing], status: status, at: date)
                if let content, !content.isEmpty {
                    todos[existing].content = content
                }
                todos[existing].status = status
                if row["priority"] != nil {
                    todos[existing].priority = priority
                }
            } else {
                var todo = previous.first(where: { $0.id == id }) ?? AgentTodo(id: id, content: content ?? "", status: status, priority: priority)
                if let content, !content.isEmpty { todo.content = content }
                stampTodo(&todo, status: status, at: date)
                todo.status = status
                todo.priority = priority
                todos.append(todo)
            }
        }
    }

    private static func stampTodo(_ todo: inout AgentTodo, status: String, at date: Date) {
        if status == "in_progress" || status == "running" {
            if todo.startedAt == nil { todo.startedAt = date }
            todo.endedAt = nil
        } else if status == "completed" || status == "cancelled" {
            if todo.startedAt == nil { todo.startedAt = date }
            if todo.endedAt == nil { todo.endedAt = date }
        }
    }

    private static func upsertTask(_ task: AgentTask, into tasks: inout [AgentTask]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            var next = tasks[index]
            if !task.title.isEmpty { next.title = task.title }
            if !task.command.isEmpty { next.command = task.command }
            next.status = task.status
            if next.startedAt == nil {
                next.startedAt = task.startedAt
            } else if let incoming = task.startedAt, incoming < next.startedAt! {
                next.startedAt = incoming
            }
            if task.endedAt != nil { next.endedAt = task.endedAt }
            tasks[index] = next
        } else {
            tasks.append(task)
        }
        if tasks.count > 40 {
            tasks = Array(tasks.suffix(40))
        }
    }

    private static func upsertSubagent(_ subagent: AgentSubagent, into subagents: inout [AgentSubagent]) {
        if let index = subagents.firstIndex(where: { $0.id == subagent.id || $0.childSessionId == subagent.childSessionId }) {
            var next = subagents[index]
            if !subagent.childSessionId.isEmpty { next.childSessionId = subagent.childSessionId }
            if !subagent.type.isEmpty { next.type = subagent.type }
            if !subagent.detail.isEmpty { next.detail = subagent.detail }
            next.status = subagent.status
            if subagent.toolCalls > 0 { next.toolCalls = subagent.toolCalls }
            if subagent.turns > 0 { next.turns = subagent.turns }
            if subagent.durationMs > 0 { next.durationMs = subagent.durationMs }
            if !subagent.output.isEmpty { next.output = subagent.output }
            if next.startedAt == nil { next.startedAt = subagent.startedAt }
            if !subagent.isolation.isEmpty { next.isolation = subagent.isolation }
            subagents[index] = next
        } else {
            subagents.append(subagent)
        }
        if subagents.count > 20 {
            subagents = Array(subagents.suffix(20))
        }
    }

    private static func fromEpoch(_ value: Double) -> Date {
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}
