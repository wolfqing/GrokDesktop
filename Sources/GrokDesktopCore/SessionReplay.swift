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
        var updates: [SessionUpdate] = []
        var unknown: [String] = []
        var seenUnknown = Set<String>()
        streamLines(url) { line in
            guard let parsed = parseReplayLine(line) else { return }
            if parsed.update.kind == .unknown, !parsed.rawKind.isEmpty, seenUnknown.insert(parsed.rawKind).inserted {
                unknown.append(parsed.rawKind)
            }
            updates.append(parsed.update)
        }
        return (updates, unknown)
    }

    public static func replay(updates: [SessionUpdate], unknown: [String] = []) -> (snapshot: SessionSnapshot, report: Report) {
        let snapshot = SessionFold.apply(updates)
        return (snapshot, report(from: snapshot, updateCount: updates.count, unknown: unknown))
    }

    public static func replay(jsonl url: URL) -> (snapshot: SessionSnapshot, report: Report) {
        var snapshot = SessionSnapshot()
        var unknown: [String] = []
        var seenUnknown = Set<String>()
        var updateCount = 0
        streamLines(url) { line in
            guard let parsed = parseReplayLine(line) else { return }
            if parsed.update.kind == .unknown, !parsed.rawKind.isEmpty, seenUnknown.insert(parsed.rawKind).inserted {
                unknown.append(parsed.rawKind)
            }
            SessionFold.apply(parsed.update, onto: &snapshot)
            updateCount += 1
        }
        return (snapshot, report(from: snapshot, updateCount: updateCount, unknown: unknown))
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

    static let bulkyToolBytes = 8_192
    static let bulkyHeaderBytes = 8_192

    static func streamLines(_ url: URL, handle line: (Data) -> Void) {
        guard let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        var buffer = Data()
        while true {
            let chunk = (try? file.read(upToCount: 256 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let row = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if !row.isEmpty {
                    line(row)
                }
            }
        }
        if !buffer.isEmpty {
            line(buffer)
        }
    }

    static func parseReplayLine(_ line: Data) -> (update: SessionUpdate, rawKind: String)? {
        let header = String(decoding: line.prefix(min(line.count, bulkyHeaderBytes)), as: UTF8.self)
        if let compact = parseCompactHeader(header) {
            let needsTodoPayload = compact.update.kind == .toolCall
                && (header.contains("todo_write") || header.contains("\"todos\""))
            if !needsTodoPayload || line.count > 64_000 {
                return compact
            }
        } else if line.count > 64_000 {
            return nil
        }
        guard let payload = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        let params = payload["params"] as? [String: Any] ?? payload
        let rawKind = ((params["update"] as? [String: Any])?["sessionUpdate"] as? String)
            ?? ((params["update"] as? [String: Any])?["session_update"] as? String)
            ?? (params["sessionUpdate"] as? String)
            ?? ""
        let update = SessionUpdate.parse(
            params: params,
            envelopeTimestamp: payload["timestamp"],
            compactTools: true
        )
        return (update, rawKind)
    }

    static func parseCompactHeader(_ header: String) -> (update: SessionUpdate, rawKind: String)? {
        let kind = jsonString(header, key: "sessionUpdate")
            ?? jsonString(header, key: "session_update")
            ?? ""
        switch kind {
        case "tool_call_update":
            let id = jsonString(header, key: "toolCallId") ?? jsonString(header, key: "tool_call_id")
            guard let id, !id.isEmpty else { return nil }
            return (
                SessionUpdate(
                    kind: .toolCallUpdate,
                    title: jsonString(header, key: "title") ?? "",
                    toolCallId: id,
                    status: SessionUpdate.normalizedStatus(jsonString(header, key: "status"))
                ),
                kind
            )
        case "tool_call":
            let id = jsonString(header, key: "toolCallId") ?? jsonString(header, key: "tool_call_id")
            return (
                SessionUpdate(
                    kind: .toolCall,
                    title: jsonString(header, key: "title") ?? "Tool",
                    toolCallId: id,
                    status: SessionUpdate.normalizedStatus(jsonString(header, key: "status")) ?? "running"
                ),
                kind
            )
        case "user_message_chunk":
            if jsonString(header, key: "type") == "image" {
                let uri = jsonString(header, key: "uri").flatMap(Self.fileURL)
                return (
                    SessionUpdate(
                        kind: .userMessageChunk,
                        imageURLs: uri.map { [$0] } ?? []
                    ),
                    kind
                )
            }
            return (
                SessionUpdate(
                    kind: .userMessageChunk,
                    text: jsonString(header, key: "text") ?? ""
                ),
                kind
            )
        case "agent_message_chunk":
            return (
                SessionUpdate(kind: .agentMessageChunk, text: jsonString(header, key: "text") ?? ""),
                kind
            )
        case "agent_thought_chunk":
            return (
                SessionUpdate(kind: .agentThoughtChunk, text: jsonString(header, key: "text") ?? ""),
                kind
            )
        default:
            return nil
        }
    }

    static func fileURL(_ raw: String) -> URL? {
        if raw.hasPrefix("file://"), let url = URL(string: raw) { return url }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        return URL(string: raw)
    }

    static func jsonString(_ text: String, key: String) -> String? {
        let needle = "\"\(key)\""
        var searchFrom = text.startIndex
        while let keyRange = text.range(of: needle, range: searchFrom..<text.endIndex) {
            var index = keyRange.upperBound
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            if index < text.endIndex, text[index] == ":" {
                index = text.index(after: index)
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                guard index < text.endIndex, text[index] == "\"" else { return nil }
                index = text.index(after: index)
                var value = ""
                value.reserveCapacity(24)
                var escaped = false
                while index < text.endIndex {
                    let character = text[index]
                    if escaped {
                        value.append(character)
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        return value
                    } else {
                        value.append(character)
                    }
                    index = text.index(after: index)
                }
                return nil
            }
            searchFrom = keyRange.upperBound
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
