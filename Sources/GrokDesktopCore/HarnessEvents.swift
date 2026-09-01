import Foundation

public struct HookDefinition: Identifiable, Hashable, Sendable {
    public var id: String { "\(event)|\(target)|\(pluginName ?? "")" }
    public var event: String
    public var hookType: String
    public var target: String
    public var sourceKind: String
    public var pluginName: String?
    public var matcher: String
    public var vendor: String
    public var enabled: Bool

    public init(
        event: String,
        hookType: String = "command",
        target: String = "",
        sourceKind: String = "user",
        pluginName: String? = nil,
        matcher: String = "",
        vendor: String = "",
        enabled: Bool = true
    ) {
        self.event = event
        self.hookType = hookType
        self.target = target
        self.sourceKind = sourceKind
        self.pluginName = pluginName
        self.matcher = matcher
        self.vendor = vendor
        self.enabled = enabled
    }

    public var title: String {
        if !event.isEmpty, event != "(plugin)" { return event }
        if let pluginName, !pluginName.isEmpty { return pluginName }
        return URL(fileURLWithPath: target).lastPathComponent
    }
}

public struct HookEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var event: String
    public var command: String
    public var blocked: Bool
    public var durationMs: Int
    public var output: String
    public var timestamp: Date?

    public init(
        id: String,
        event: String,
        command: String = "",
        blocked: Bool = false,
        durationMs: Int = 0,
        output: String = "",
        timestamp: Date? = nil
    ) {
        self.id = id
        self.event = event
        self.command = command
        self.blocked = blocked
        self.durationMs = durationMs
        self.output = output
        self.timestamp = timestamp
    }

    public var elapsed: TimeInterval? {
        durationMs > 0 ? Double(durationMs) / 1000 : nil
    }
}

public struct CompactionCheckpoint: Identifiable, Hashable, Sendable {
    public var id: String
    public var tokensBefore: Int
    public var tokensAfter: Int
    public var recap: String
    public var path: String
    public var createdAt: Date?

    public init(
        id: String,
        tokensBefore: Int = 0,
        tokensAfter: Int = 0,
        recap: String = "",
        path: String = "",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.recap = recap
        self.path = path
        self.createdAt = createdAt
    }
}

public struct ScheduledTask: Identifiable, Hashable, Sendable {
    public var id: String
    public var prompt: String
    public var schedule: String
    public var timestamp: Date?

    public init(id: String, prompt: String, schedule: String = "", timestamp: Date? = nil) {
        self.id = id
        self.prompt = prompt
        self.schedule = schedule
        self.timestamp = timestamp
    }

    public var title: String {
        schedule.isEmpty ? prompt : "\(schedule): \(prompt)"
    }
}

public enum HarnessEvents {
    public static func parseHooks(_ object: [String: Any]) -> [HookDefinition] {
        let rows = object["hooks"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            let target = row["target"] as? String ?? row["command"] as? String ?? ""
            let event = row["event"] as? String ?? ""
            guard !target.isEmpty || !event.isEmpty else { return nil }
            let source = row["source"] as? [String: Any] ?? [:]
            let status = (row["compatibilityStatus"] as? String ?? "").lowercased()
            return HookDefinition(
                event: event,
                hookType: row["hookType"] as? String ?? row["type"] as? String ?? "command",
                target: target,
                sourceKind: (source["type"] as? String ?? "user").lowercased(),
                pluginName: source["plugin_name"] as? String,
                matcher: row["matcher"] as? String ?? "",
                vendor: row["vendor"] as? String ?? "",
                enabled: status != "disabled" && status != "blocked"
            )
        }
    }

    public static func hookEvent(from update: SessionUpdate) -> HookEvent {
        let raw = update.raw
        let event = raw["event"] as? String
            ?? raw["hook_event_name"] as? String
            ?? raw["hookEvent"] as? String
            ?? update.title
        let command = raw["command"] as? String ?? raw["target"] as? String ?? update.text
        let blocked = (raw["blocked"] as? Bool)
            ?? (raw["deny"] as? Bool)
            ?? ((raw["decision"] as? String)?.lowercased() == "deny")
        let duration = raw["duration_ms"] as? Int
            ?? raw["durationMs"] as? Int
            ?? 0
        return HookEvent(
            id: raw["id"] as? String ?? UUID().uuidString,
            event: event.isEmpty ? "hook" : event,
            command: command,
            blocked: blocked,
            durationMs: duration,
            output: String((raw["output"] as? String ?? update.text).prefix(240)),
            timestamp: update.timestamp
        )
    }

    public static func checkpoint(from update: SessionUpdate) -> CompactionCheckpoint {
        let raw = update.raw
        let before = raw["tokens_before"] as? Int
            ?? raw["tokensBefore"] as? Int
            ?? raw["before"] as? Int
            ?? 0
        let after = raw["tokens_after"] as? Int
            ?? raw["tokensAfter"] as? Int
            ?? raw["after"] as? Int
            ?? 0
        return CompactionCheckpoint(
            id: raw["id"] as? String ?? raw["checkpoint_id"] as? String ?? UUID().uuidString,
            tokensBefore: before,
            tokensAfter: after,
            recap: raw["summary"] as? String ?? raw["recap"] as? String ?? update.text,
            path: raw["path"] as? String ?? "",
            createdAt: update.timestamp
        )
    }

    public static func scheduledTask(from update: SessionUpdate) -> ScheduledTask {
        let raw = update.raw
        let id = raw["task_id"] as? String
            ?? raw["id"] as? String
            ?? UUID().uuidString
        let prompt = raw["prompt"] as? String ?? update.text
        let schedule = raw["human_schedule"] as? String
            ?? raw["interval"] as? String
            ?? raw["schedule"] as? String
            ?? ""
        return ScheduledTask(id: id, prompt: prompt, schedule: schedule, timestamp: update.timestamp)
    }

    public static func scheduledTaskID(from update: SessionUpdate) -> String {
        update.raw["task_id"] as? String
            ?? update.raw["id"] as? String
            ?? update.text
    }

    public static func loadCheckpoints(sessionDirectory: URL?) -> [CompactionCheckpoint] {
        guard let root = sessionDirectory?.appendingPathComponent("compaction_checkpoints", isDirectory: true) else {
            return []
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url -> CompactionCheckpoint? in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let recap = String(text.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
            if url.pathExtension.lowercased() == "json",
               let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return CompactionCheckpoint(
                    id: object["id"] as? String ?? url.lastPathComponent,
                    tokensBefore: object["tokens_before"] as? Int ?? object["tokensBefore"] as? Int ?? 0,
                    tokensAfter: object["tokens_after"] as? Int ?? object["tokensAfter"] as? Int ?? 0,
                    recap: object["summary"] as? String ?? object["recap"] as? String ?? recap,
                    path: url.path,
                    createdAt: modified
                )
            }
            return CompactionCheckpoint(
                id: url.lastPathComponent,
                recap: recap,
                path: url.path,
                createdAt: modified
            )
        }
        .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
