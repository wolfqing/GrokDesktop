import Foundation

public struct AgentTodo: Identifiable, Hashable, Sendable {
    public var id: String
    public var content: String
    public var status: String
    public var priority: String

    public init(id: String, content: String, status: String = "pending", priority: String = "medium") {
        self.id = id
        self.content = content
        self.status = status
        self.priority = priority
    }

    public var isCancelled: Bool { status == "cancelled" }
    public var isDone: Bool { status == "completed" }
    public var isActive: Bool { status == "in_progress" }
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
        guard let start = startedAt else { return nil }
        return (endedAt ?? Date()).timeIntervalSince(start)
    }
}

public enum PromptTimestamp {
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
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: text)
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

    public static func applyTodos(from update: SessionUpdate, into todos: inout [AgentTodo]) {
        if let output = update.raw["rawOutput"] as? [String: Any],
           let updated = output["TodosUpdated"] as? [String: Any] {
            if let state = updated["state"] as? [String: Any],
               let map = state["todos"] as? [String: Any] {
                let order = (updated["todos"] as? [[String: Any]])?.compactMap { $0["content"] as? String }
                todos = map.compactMap { key, value in
                    guard let dict = value as? [String: Any] else { return nil }
                    return AgentTodo(
                        id: key,
                        content: dict["content"] as? String ?? "",
                        status: dict["status"] as? String ?? "pending",
                        priority: dict["priority"] as? String ?? "medium"
                    )
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
                mergeTodos(rows, merge: false, into: &todos)
                return
            }
        }

        let input = update.raw["rawInput"] as? [String: Any]
        let tool = ((update.raw["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any])?["name"] as? String
        let isTodo = update.title == "todo_write"
            || tool == "todo_write"
            || input?["todos"] != nil
        guard isTodo, let rows = input?["todos"] as? [[String: Any]] else { return }
        mergeTodos(rows, merge: input?["merge"] as? Bool ?? false, into: &todos)
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

    public static func progress(for todos: [AgentTodo]) -> (done: Int, total: Int) {
        let visible = todos.filter { !$0.isCancelled }
        return (visible.filter(\.isDone).count, visible.count)
    }

    private static func mergeTodos(_ rows: [[String: Any]], merge: Bool, into todos: inout [AgentTodo]) {
        if !merge { todos = [] }
        for (index, row) in rows.enumerated() {
            let id = row["id"] as? String ?? row["content"] as? String ?? String(index + 1)
            let content = row["content"] as? String
            let status = row["status"] as? String ?? "pending"
            let priority = row["priority"] as? String ?? "medium"
            if let existing = todos.firstIndex(where: { $0.id == id }) {
                if let content, !content.isEmpty {
                    todos[existing].content = content
                }
                todos[existing].status = status
                if row["priority"] != nil {
                    todos[existing].priority = priority
                }
            } else {
                todos.append(AgentTodo(id: id, content: content ?? "", status: status, priority: priority))
            }
        }
    }

    private static func upsertTask(_ task: AgentTask, into tasks: inout [AgentTask]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            var next = tasks[index]
            if !task.title.isEmpty { next.title = task.title }
            if !task.command.isEmpty { next.command = task.command }
            next.status = task.status
            if task.startedAt != nil { next.startedAt = task.startedAt }
            if task.endedAt != nil { next.endedAt = task.endedAt }
            tasks[index] = next
        } else {
            tasks.append(task)
        }
        if tasks.count > 40 {
            tasks = Array(tasks.suffix(40))
        }
    }

    private static func fromEpoch(_ value: Double) -> Date {
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}
