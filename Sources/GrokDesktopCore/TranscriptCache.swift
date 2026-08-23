import Foundation

enum TranscriptCache {
    static let version = 1
    static let fileNameSuffix = ".json"

    static func load(sessionDirectory: URL, limit: Int) -> Transcript? {
        let url = cacheURL(for: sessionDirectory)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              int(object["version"]) == version
        else { return nil }
        let fingerprint = Fingerprint.capture(sessionDirectory: sessionDirectory, limit: limit)
        guard int(object["updatesSize"]) == fingerprint.updatesSize,
              int(object["updatesMTime"]) == fingerprint.updatesMTime,
              int(object["chatSize"]) == fingerprint.chatSize,
              int(object["limit"]) == fingerprint.limit
        else { return nil }

        let items = (object["items"] as? [[String: Any]] ?? []).compactMap(decodeItem)
        guard !items.isEmpty else { return nil }
        return Transcript(
            items: items,
            planEntries: decodePlan(object["planEntries"]),
            itemDates: decodeDates(object["itemDates"]),
            itemImages: decodeImages(object["itemImages"]),
            todos: decodeTodos(object["todos"]),
            tasks: decodeTasks(object["tasks"]),
            recap: object["recap"] as? String ?? "",
            compacted: bool(object["compacted"]),
            subagents: decodeSubagents(object["subagents"])
        )
    }

    static func save(_ transcript: Transcript, sessionDirectory: URL, limit: Int) {
        let fingerprint = Fingerprint.capture(sessionDirectory: sessionDirectory, limit: limit)
        let payload: [String: Any] = [
            "version": version,
            "updatesSize": fingerprint.updatesSize,
            "updatesMTime": fingerprint.updatesMTime,
            "chatSize": fingerprint.chatSize,
            "limit": fingerprint.limit,
            "items": transcript.items.map(encodeItem),
            "planEntries": transcript.planEntries.map {
                ["content": $0.content, "status": $0.status, "priority": $0.priority]
            },
            "itemDates": transcript.itemDates.mapValues { $0.timeIntervalSince1970 },
            "itemImages": transcript.itemImages.mapValues { $0.map(\.path) },
            "todos": transcript.todos.map(encodeTodo),
            "tasks": transcript.tasks.map(encodeTask),
            "recap": transcript.recap,
            "compacted": transcript.compacted,
            "subagents": transcript.subagents.map(encodeSubagent)
        ]
        let folder = cacheRoot()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: cacheURL(for: sessionDirectory), options: .atomic)
        }
    }

    static func cacheURL(for sessionDirectory: URL) -> URL {
        cacheRoot().appendingPathComponent(sessionDirectory.lastPathComponent + fileNameSuffix)
    }

    private static func cacheRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/desktop-cache", isDirectory: true)
    }

    struct Fingerprint: Equatable {
        var updatesSize: Int
        var updatesMTime: Int
        var chatSize: Int
        var limit: Int

        static func capture(sessionDirectory: URL, limit: Int) -> Fingerprint {
            let updates = sessionDirectory.appendingPathComponent("updates.jsonl")
            let chat = sessionDirectory.appendingPathComponent("chat_history.jsonl")
            return Fingerprint(
                updatesSize: fileSize(updates),
                updatesMTime: mtime(updates),
                chatSize: fileSize(chat),
                limit: limit
            )
        }

        private static func fileSize(_ url: URL) -> Int {
            (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }

        private static func mtime(_ url: URL) -> Int {
            Int((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
    }

    private static func encodeItem(_ item: ConversationItem) -> [String: Any] {
        switch item {
        case .user(let id, let text):
            return ["k": "user", "id": id, "text": text]
        case .assistant(let id, let text, let done):
            return ["k": "assistant", "id": id, "text": text, "done": done]
        case .thought(let id, let text):
            return ["k": "thought", "id": id, "text": text]
        case .tool(let id, let title, let status, let detail):
            return ["k": "tool", "id": id, "title": title, "status": status, "detail": detail]
        case .notice(let id, let text):
            return ["k": "notice", "id": id, "text": text]
        }
    }

    private static func decodeItem(_ object: [String: Any]) -> ConversationItem? {
        let id = object["id"] as? String ?? UUID().uuidString
        let text = object["text"] as? String ?? ""
        switch object["k"] as? String {
        case "user":
            return .user(id: id, text: text)
        case "assistant":
            return .assistant(id: id, text: text, done: bool(object["done"], default: true))
        case "thought":
            return .thought(id: id, text: text)
        case "tool":
            return .tool(
                id: id,
                title: object["title"] as? String ?? "Tool",
                status: object["status"] as? String ?? "completed",
                detail: object["detail"] as? String ?? ""
            )
        case "notice":
            return .notice(id: id, text: text)
        default:
            return nil
        }
    }

    private static func decodePlan(_ raw: Any?) -> [PlanEntry] {
        (raw as? [[String: Any]] ?? []).compactMap { row in
            let content = row["content"] as? String ?? ""
            guard !content.isEmpty else { return nil }
            return PlanEntry(
                content: content,
                status: row["status"] as? String ?? "pending",
                priority: row["priority"] as? String ?? "medium"
            )
        }
    }

    private static func decodeDates(_ raw: Any?) -> [String: Date] {
        var dates: [String: Date] = [:]
        guard let map = raw as? [String: Any] else { return dates }
        for (id, value) in map {
            if let interval = double(value) {
                dates[id] = Date(timeIntervalSince1970: interval)
            }
        }
        return dates
    }

    private static func decodeImages(_ raw: Any?) -> [String: [URL]] {
        var images: [String: [URL]] = [:]
        if let map = raw as? [String: [String]] {
            for (id, paths) in map {
                images[id] = paths.map { URL(fileURLWithPath: $0) }
            }
        }
        return images
    }

    private static func encodeTodo(_ todo: AgentTodo) -> [String: Any] {
        var row: [String: Any] = [
            "id": todo.id,
            "content": todo.content,
            "status": todo.status,
            "priority": todo.priority
        ]
        if let startedAt = todo.startedAt { row["startedAt"] = startedAt.timeIntervalSince1970 }
        if let endedAt = todo.endedAt { row["endedAt"] = endedAt.timeIntervalSince1970 }
        return row
    }

    private static func decodeTodos(_ raw: Any?) -> [AgentTodo] {
        (raw as? [[String: Any]] ?? []).compactMap { row in
            let id = row["id"] as? String ?? ""
            guard !id.isEmpty else { return nil }
            return AgentTodo(
                id: id,
                content: row["content"] as? String ?? "",
                status: row["status"] as? String ?? "pending",
                priority: row["priority"] as? String ?? "medium",
                startedAt: date(row["startedAt"]),
                endedAt: date(row["endedAt"])
            )
        }
    }

    private static func encodeTask(_ task: AgentTask) -> [String: Any] {
        var row: [String: Any] = [
            "id": task.id,
            "title": task.title,
            "command": task.command,
            "status": task.status
        ]
        if let startedAt = task.startedAt { row["startedAt"] = startedAt.timeIntervalSince1970 }
        if let endedAt = task.endedAt { row["endedAt"] = endedAt.timeIntervalSince1970 }
        return row
    }

    private static func decodeTasks(_ raw: Any?) -> [AgentTask] {
        (raw as? [[String: Any]] ?? []).compactMap { row in
            let id = row["id"] as? String ?? ""
            guard !id.isEmpty else { return nil }
            return AgentTask(
                id: id,
                title: row["title"] as? String ?? "",
                command: row["command"] as? String ?? "",
                status: row["status"] as? String ?? "completed",
                startedAt: date(row["startedAt"]),
                endedAt: date(row["endedAt"])
            )
        }
    }

    private static func encodeSubagent(_ item: AgentSubagent) -> [String: Any] {
        var row: [String: Any] = [
            "id": item.id,
            "childSessionId": item.childSessionId,
            "type": item.type,
            "detail": item.detail,
            "status": item.status,
            "toolCalls": item.toolCalls,
            "turns": item.turns,
            "durationMs": item.durationMs,
            "output": item.output
        ]
        if let startedAt = item.startedAt { row["startedAt"] = startedAt.timeIntervalSince1970 }
        return row
    }

    private static func decodeSubagents(_ raw: Any?) -> [AgentSubagent] {
        (raw as? [[String: Any]] ?? []).compactMap { row in
            let id = row["id"] as? String ?? ""
            guard !id.isEmpty else { return nil }
            return AgentSubagent(
                id: id,
                childSessionId: row["childSessionId"] as? String ?? "",
                type: row["type"] as? String ?? "",
                detail: row["detail"] as? String ?? "",
                status: row["status"] as? String ?? "completed",
                toolCalls: int(row["toolCalls"]),
                turns: int(row["turns"]),
                durationMs: int(row["durationMs"]),
                output: row["output"] as? String ?? "",
                startedAt: date(row["startedAt"])
            )
        }
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let interval = double(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private static func bool(_ raw: Any?, default defaultValue: Bool = false) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return defaultValue
    }

    private static func int(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return 0
    }

    private static func double(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }
}
