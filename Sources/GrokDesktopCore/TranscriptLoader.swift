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

public enum PlanSurface {
    /// The plan stays beside the session after approve until a later plan replaces it.
    public static func keepsBody(entryCount: Int, markdown: String) -> Bool {
        entryCount > 0 || !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Approve, revise, and quit stay only while the session is still in plan mode.
    public static func showsApprove(modeIsPlan: Bool) -> Bool {
        modeIsPlan
    }

    /// Todos occupy the checklist. The plan is listed again so it does not disappear.
    public static func listsPlanBesideTodos(todoCount: Int, entryCount: Int) -> Bool {
        todoCount > 0 && entryCount > 0
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
    public var itemImages: [String: [URL]]
    public var todos: [AgentTodo]
    public var tasks: [AgentTask]
    public var recap: String
    public var compacted: Bool
    public var subagents: [AgentSubagent]
    public var itemDurations: [String: TimeInterval]

    public init(
        items: [ConversationItem] = [],
        planEntries: [PlanEntry] = [],
        planMarkdown: String = "",
        hunks: [FileHunk] = [],
        itemDates: [String: Date] = [:],
        itemImages: [String: [URL]] = [:],
        todos: [AgentTodo] = [],
        tasks: [AgentTask] = [],
        recap: String = "",
        compacted: Bool = false,
        subagents: [AgentSubagent] = [],
        itemDurations: [String: TimeInterval] = [:]
    ) {
        self.items = items
        self.planEntries = planEntries
        self.planMarkdown = planMarkdown
        self.hunks = hunks
        self.itemDates = itemDates
        self.itemImages = itemImages
        self.todos = todos
        self.tasks = tasks
        self.recap = recap
        self.compacted = compacted
        self.subagents = subagents
        self.itemDurations = itemDurations
    }

    public var snapshot: SessionSnapshot {
        SessionSnapshot(
            items: items,
            planEntries: planEntries,
            itemDates: itemDates,
            itemImages: itemImages,
            todos: todos,
            tasks: tasks,
            recap: recap,
            compacted: compacted,
            subagents: subagents,
            itemDurations: itemDurations
        )
    }
}

public enum TranscriptLoader {
    /// Files larger than this are opened from the tail. The chat already keeps only the latest rows.
    public static let defaultTailBytes = 8 * 1024 * 1024

    public static func load(
        sessionDirectory: URL,
        limit: Int = 400,
        includeHunks: Bool = true,
        tailByteCap: Int = defaultTailBytes
    ) -> Transcript {
        let updatesURL = sessionDirectory.appendingPathComponent("updates.jsonl")
        let updatesSize = (try? updatesURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if let cached = TranscriptCache.resume(sessionDirectory: sessionDirectory, limit: limit) {
            if cached.updatesSize == updatesSize,
               cached.updatesMTime == updatesMTime(updatesURL) {
                return decorate(cached.transcript, sessionDirectory: sessionDirectory, includeHunks: includeHunks)
            }
            if cached.updatesSize > 0, cached.updatesSize < updatesSize {
                var snapshot = cached.transcript.snapshot
                snapshot.assistantID = cached.assistantID
                snapshot.thoughtID = cached.thoughtID
                SessionReplay.fold(
                    jsonl: updatesURL,
                    from: UInt64(cached.updatesSize),
                    skipPartialFirstLine: false,
                    onto: &snapshot
                )
                return finish(
                    snapshot,
                    sessionDirectory: sessionDirectory,
                    limit: limit,
                    includeHunks: includeHunks
                )
            }
        }

        let cap = max(tailByteCap, 1024)
        let snapshot: SessionSnapshot
        if updatesSize > cap {
            let offset = UInt64(updatesSize - cap)
            let tailed = SessionReplay.replay(
                jsonl: updatesURL,
                from: offset,
                skipPartialFirstLine: true
            ).snapshot
            if tailed.items.contains(where: { if case .user = $0 { return true }; return false }) {
                snapshot = tailed
            } else {
                snapshot = SessionReplay.replay(sessionDirectory: sessionDirectory).snapshot
            }
        } else {
            snapshot = SessionReplay.replay(sessionDirectory: sessionDirectory).snapshot
        }
        return finish(
            snapshot,
            sessionDirectory: sessionDirectory,
            limit: limit,
            includeHunks: includeHunks
        )
    }

    private static func updatesMTime(_ url: URL) -> Int {
        Int((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0)
    }

    private static func decorate(
        _ transcript: Transcript,
        sessionDirectory: URL,
        includeHunks: Bool
    ) -> Transcript {
        var cached = transcript
        cached.planMarkdown = (try? String(
            contentsOf: sessionDirectory.appendingPathComponent("plan.md"),
            encoding: .utf8
        )) ?? ""
        if includeHunks {
            cached.hunks = loadHunks(sessionDirectory: sessionDirectory)
        }
        return cached
    }

    private static func finish(
        _ snapshot: SessionSnapshot,
        sessionDirectory: URL,
        limit: Int,
        includeHunks: Bool
    ) -> Transcript {
        var snapshot = snapshot
        attachDiskImages(sessionDirectory: sessionDirectory, items: snapshot.items, itemImages: &snapshot.itemImages)
        if snapshot.items.count > limit {
            snapshot.items = Array(snapshot.items.suffix(limit))
        }
        let transcript = Transcript(
            items: snapshot.items,
            planEntries: snapshot.planEntries,
            planMarkdown: (try? String(
                contentsOf: sessionDirectory.appendingPathComponent("plan.md"),
                encoding: .utf8
            )) ?? "",
            hunks: includeHunks ? loadHunks(sessionDirectory: sessionDirectory) : [],
            itemDates: snapshot.itemDates,
            itemImages: snapshot.itemImages,
            todos: snapshot.todos,
            tasks: snapshot.tasks,
            recap: snapshot.recap,
            compacted: snapshot.compacted,
            subagents: snapshot.subagents,
            itemDurations: snapshot.itemDurations
        )
        TranscriptCache.save(
            transcript,
            sessionDirectory: sessionDirectory,
            limit: limit,
            assistantID: snapshot.assistantID,
            thoughtID: snapshot.thoughtID
        )
        return transcript
    }

    public static func loadChatHistory(_ url: URL) -> Transcript {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Transcript() }
        var items: [ConversationItem] = []
        let itemDates: [String: Date] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }
            switch type {
            case "user":
                let raw = contentText(object["content"])
                let shown = displayUserText(raw)
                guard !shown.isEmpty else { continue }
                let id = UUID().uuidString
                items.append(.user(id: id, text: shown))
            case "assistant":
                let raw = contentText(object["content"])
                guard !raw.isEmpty else { continue }
                let id = UUID().uuidString
                items.append(.assistant(id: id, text: raw, done: true))
            case "reasoning":
                let summary = object["summary"] as? String ?? contentText(object["content"])
                guard !summary.isEmpty else { continue }
                items.append(.thought(id: UUID().uuidString, text: summary))
            default:
                continue
            }
        }
        return Transcript(items: items, itemDates: itemDates)
    }

    public static func displayUserText(_ raw: String) -> String {
        if let query = slice(raw, start: "<user_query>", end: "</user_query>") {
            return query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var text = raw
        let blocks = [#"<system-reminder>[\s\S]*?</system-reminder>"#, #"<user_info>[\s\S]*?</user_info>"#, #"<git_status>[\s\S]*?</git_status>"#]
        for pattern in blocks {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func attachDiskImages(
        sessionDirectory: URL,
        items: [ConversationItem],
        itemImages: inout [String: [URL]]
    ) {
        let files = diskImages(in: sessionDirectory)
        guard !files.isEmpty else { return }
        var cursor = 0
        for item in items {
            guard case .user(let id, let text) = item else { continue }
            if let existing = itemImages[id], !existing.isEmpty { continue }
            let count = max(PromptMedia.imageURLs(in: text).count, imageTokenCount(in: text))
            guard count > 0, cursor < files.count else { continue }
            let end = min(cursor + count, files.count)
            itemImages[id] = Array(files[cursor..<end])
            cursor = end
        }
    }

    public static func diskImages(in sessionDirectory: URL) -> [URL] {
        let folders = ["images", "assets"].map { sessionDirectory.appendingPathComponent($0) }
        var urls: [URL] = []
        for folder in folders {
            guard let found = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            urls.append(contentsOf: found.filter { PromptMedia.isImageURL($0) })
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func parseDiffFiles(_ text: String) -> [String] {
        var names: [String] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("diff --git ") {
                let parts = line.split(separator: " ")
                if let last = parts.last {
                    var path = String(last)
                    if path.hasPrefix("b/") { path = String(path.dropFirst(2)) }
                    if !path.isEmpty { names.append(path) }
                }
            }
        }
        return names
    }

    private static func contentText(_ raw: Any?) -> String {
        if let text = raw as? String { return text }
        if let items = raw as? [Any] {
            return items.compactMap { item -> String? in
                if let text = item as? String { return text }
                if let dict = item as? [String: Any] {
                    return dict["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }

    private static func slice(_ text: String, start: String, end: String) -> String? {
        guard let lower = text.range(of: start), let upper = text.range(of: end, range: lower.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[lower.upperBound..<upper.lowerBound])
    }

    private static func imageTokenCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"\[Image #\d+\]"#) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
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
        itemImages: inout [String: [URL]],
        todos: inout [AgentTodo],
        tasks: inout [AgentTask]
    ) {
        let countBefore = items.count
        switch update.kind {
        case .userMessageChunk:
            assistantID = nil
            thoughtID = nil
            let incomingImages = update.imageURLs + PromptMedia.imageURLs(in: update.text)
            if let last = items.indices.last, case .user(let id, let text) = items[last] {
                PromptMedia.merge(
                    incomingImages,
                    displayNumber: update.imageDisplayNumber,
                    onto: id,
                    itemImages: &itemImages
                )
                if itemDates[id] == nil, let timestamp = update.timestamp {
                    itemDates[id] = timestamp
                }
                if !update.text.isEmpty,
                   text != update.text,
                   !text.hasSuffix(update.text),
                   !PromptMedia.samePrompt(text, update.text) {
                    items[last] = .user(id: id, text: text + update.text)
                }
            } else if !update.text.isEmpty || !incomingImages.isEmpty {
                let id = UUID().uuidString
                items.append(.user(id: id, text: update.text))
                PromptMedia.merge(
                    incomingImages,
                    displayNumber: update.imageDisplayNumber,
                    onto: id,
                    itemImages: &itemImages
                )
            }
        case .agentMessageChunk:
            thoughtID = nil
            append(kind: .assistant, text: update.text, items: &items, bufferID: &assistantID)
        case .agentThoughtChunk:
            append(kind: .thought, text: update.text, items: &items, bufferID: &thoughtID)
        case .toolCall, .toolCallUpdate:
            let id = update.toolCallId ?? UUID().uuidString
            if let index = items.lastIndex(where: { $0.id == id }) {
                if case .tool(_, let title, let status, let detail) = items[index] {
                    items[index] = .tool(
                        id: id,
                        title: update.title.isEmpty ? title : update.title,
                        status: update.status ?? status,
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
        case .sessionRecap:
            assistantID = nil
            thoughtID = nil
            let summary = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                items.append(.notice(id: UUID().uuidString, text: summary))
            }
        case .autoCompactCompleted:
            assistantID = nil
            thoughtID = nil
            items.append(.notice(id: UUID().uuidString, text: "Context compacted"))
        case .imageCompressed:
            if let last = items.indices.last, case .user(let id, _) = items[last] {
                PromptMedia.merge(
                    update.imageURLs,
                    displayNumber: update.imageDisplayNumber,
                    onto: id,
                    itemImages: &itemImages
                )
            }
        case .notice:
            assistantID = nil
            thoughtID = nil
            let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(.notice(id: UUID().uuidString, text: text))
            }
        case .autoCompactStarted, .turnCompleted, .unknown,
                .hookExecution, .compactionCheckpoint, .retryState,
                .hooksChanged, .pluginsChanged, .scheduledTaskCreated,
                .scheduledTaskDeleted, .subagentSpawned, .subagentFinished:
            assistantID = nil
            thoughtID = nil
        }
        if let timestamp = update.timestamp, items.count > countBefore {
            for item in items.suffix(items.count - countBefore) {
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
        if let id = bufferID, let index = items.lastIndex(where: { $0.id == id }) {
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
