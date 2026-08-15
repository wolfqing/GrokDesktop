import Foundation

public enum SessionReplay {
    public struct Report: Equatable, Sendable {
        public var updateCount: Int
        public var userCount: Int
        public var assistantCount: Int
        public var toolCount: Int
        public var noticeCount: Int
        public var todoCount: Int
        public var taskCount: Int
        public var planCount: Int
        public var imageCount: Int
        public var recap: String
        public var compacted: Bool
        public var subagentCount: Int
        public var unknownKinds: [String]

        public init(
            updateCount: Int = 0,
            userCount: Int = 0,
            assistantCount: Int = 0,
            toolCount: Int = 0,
            noticeCount: Int = 0,
            todoCount: Int = 0,
            taskCount: Int = 0,
            planCount: Int = 0,
            imageCount: Int = 0,
            recap: String = "",
            compacted: Bool = false,
            subagentCount: Int = 0,
            unknownKinds: [String] = []
        ) {
            self.updateCount = updateCount
            self.userCount = userCount
            self.assistantCount = assistantCount
            self.toolCount = toolCount
            self.noticeCount = noticeCount
            self.todoCount = todoCount
            self.taskCount = taskCount
            self.planCount = planCount
            self.imageCount = imageCount
            self.recap = recap
            self.compacted = compacted
            self.subagentCount = subagentCount
            self.unknownKinds = unknownKinds
        }
    }

    public static func updates(fromJSONL url: URL) -> (updates: [SessionUpdate], unknown: [String]) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ([], [])
        }
        var updates: [SessionUpdate] = []
        var unknown: [String] = []
        var seenUnknown = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            let params = payload["params"] as? [String: Any] ?? payload
            let update = SessionUpdate.parse(params: params, envelopeTimestamp: payload["timestamp"])
            let rawKind = ((params["update"] as? [String: Any])?["sessionUpdate"] as? String)
                ?? ((params["update"] as? [String: Any])?["session_update"] as? String)
                ?? (params["sessionUpdate"] as? String)
                ?? ""
            if update.kind == .unknown, !rawKind.isEmpty, seenUnknown.insert(rawKind).inserted {
                unknown.append(rawKind)
            }
            updates.append(update)
        }
        return (updates, unknown)
    }

    public static func replay(updates: [SessionUpdate], unknown: [String] = []) -> (snapshot: SessionSnapshot, report: Report) {
        let snapshot = SessionFold.apply(updates)
        return (snapshot, report(from: snapshot, updateCount: updates.count, unknown: unknown))
    }

    public static func replay(jsonl url: URL) -> (snapshot: SessionSnapshot, report: Report) {
        let parsed = updates(fromJSONL: url)
        return replay(updates: parsed.updates, unknown: parsed.unknown)
    }

    public static func replay(sessionDirectory: URL) -> (snapshot: SessionSnapshot, report: Report) {
        let jsonl = sessionDirectory.appendingPathComponent("updates.jsonl")
        var result = replay(jsonl: jsonl)
        let hasUser = result.snapshot.items.contains {
            if case .user = $0 { return true }
            return false
        }
        if !hasUser {
            let fallback = TranscriptLoader.loadChatHistory(sessionDirectory.appendingPathComponent("chat_history.jsonl"))
            if !fallback.items.isEmpty {
                result.snapshot.items = fallback.items
                result.snapshot.itemDates.merge(fallback.itemDates) { current, _ in current }
            }
        }
        TranscriptLoader.attachDiskImages(
            sessionDirectory: sessionDirectory,
            items: result.snapshot.items,
            itemImages: &result.snapshot.itemImages
        )
        result.report = report(
            from: result.snapshot,
            updateCount: result.report.updateCount,
            unknown: result.report.unknownKinds
        )
        return result
    }

    public static func firstJSONL(under root: URL, limit: Int = 40) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var seen = 0
        for case let url as URL in enumerator {
            if url.lastPathComponent == "updates.jsonl" {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 40 {
                    return url
                }
                seen += 1
                if seen >= limit { return url }
            }
        }
        return nil
    }

    public static func report(from snapshot: SessionSnapshot, updateCount: Int, unknown: [String]) -> Report {
        var users = 0
        var assistants = 0
        var tools = 0
        var notices = 0
        for item in snapshot.items {
            switch item {
            case .user: users += 1
            case .assistant: assistants += 1
            case .tool: tools += 1
            case .notice: notices += 1
            case .thought: break
            }
        }
        return Report(
            updateCount: updateCount,
            userCount: users,
            assistantCount: assistants,
            toolCount: tools,
            noticeCount: notices,
            todoCount: snapshot.todos.count,
            taskCount: snapshot.tasks.count,
            planCount: snapshot.planEntries.count,
            imageCount: snapshot.itemImages.values.reduce(0) { $0 + $1.count },
            recap: snapshot.recap,
            compacted: snapshot.compacted,
            subagentCount: snapshot.subagents.count,
            unknownKinds: unknown
        )
    }
}
