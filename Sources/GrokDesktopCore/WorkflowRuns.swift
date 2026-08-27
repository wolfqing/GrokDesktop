import Foundation

public struct WorkflowRun: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var status: String
    public var startedAt: Date
    public var note: String

    public init(id: String = UUID().uuidString, name: String, status: String = "running", startedAt: Date = Date(), note: String = "") {
        self.id = id
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.note = note
    }

    public var isActive: Bool { status == "running" || status == "paused" }
}

public struct WorkflowRunStore: Sendable {
    public var url: URL

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/desktop/workflow-runs.json")
    ) {
        self.url = url
    }

    public func load() -> [WorkflowRun] {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([WorkflowRun].self, from: data)
        else { return [] }
        return rows.sorted { $0.startedAt > $1.startedAt }
    }

    public func save(_ runs: [WorkflowRun]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let trimmed = Array(runs.sorted { $0.startedAt > $1.startedAt }.prefix(40))
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func scan(sessionsRoot: URL, currentSession: URL? = nil) -> [WorkflowRun] {
        var runs: [WorkflowRun] = []
        var seen = Set<String>()
        func add(_ run: WorkflowRun) {
            let key = run.name.lowercased()
            guard seen.insert(key).inserted else { return }
            runs.append(run)
        }
        if let currentSession {
            for run in scanFolder(currentSession.appendingPathComponent("workflows")) {
                add(run)
            }
        }
        guard let cwdDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return runs.sorted { $0.startedAt > $1.startedAt }
        }
        for cwd in cwdDirs.prefix(40) {
            guard (try? cwd.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let sessions = try? FileManager.default.contentsOfDirectory(
                at: cwd,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for session in sessions.prefix(20) {
                if session == currentSession { continue }
                guard (try? session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                for run in scanFolder(session.appendingPathComponent("workflows")) {
                    add(run)
                }
            }
        }
        return runs.sorted { $0.startedAt > $1.startedAt }
    }

    public static func scanFolder(_ folder: URL) -> [WorkflowRun] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var runs: [WorkflowRun] = []
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if let run = parseRunDirectory(child) { runs.append(run) }
            } else if ["json", "jsonl"].contains(child.pathExtension.lowercased()) {
                if let run = parseRunFile(child) { runs.append(run) }
            } else if child.pathExtension.lowercased() == "rhai" {
                let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                runs.append(WorkflowRun(name: child.deletingPathExtension().lastPathComponent, status: "completed", startedAt: date))
            }
        }
        return runs
    }

    public static func reconcile(
        overlay: [WorkflowRun],
        disk: [WorkflowRun],
        liveTitles: [String],
        turnRunning: Bool,
        now: Date = Date()
    ) -> [WorkflowRun] {
        let live = liveTitles.map { $0.lowercased() }
        func isLive(_ name: String) -> Bool {
            let needle = name.lowercased()
            return live.contains { $0.contains(needle) || $0.contains("workflow") }
        }
        var byName: [String: WorkflowRun] = [:]
        for run in overlay {
            byName[run.name.lowercased()] = run
        }
        for run in disk {
            byName[run.name.lowercased()] = run
        }
        let merged = byName.values.map { run -> WorkflowRun in
            var next = run
            if run.status == "paused" || run.status == "stopped" {
                return next
            }
            if isLive(run.name) {
                next.status = "running"
                return next
            }
            if run.status == "running", !turnRunning, now.timeIntervalSince(run.startedAt) > 8 {
                next.status = "completed"
            }
            return next
        }
        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    public static func normalizedStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "running", "in_progress", "active", "live":
            return "running"
        case "paused", "pause", "waiting":
            return "paused"
        case "stopped", "stop", "cancelled", "canceled", "interrupted":
            return "stopped"
        case "completed", "complete", "success", "done", "failed", "error":
            return "completed"
        default:
            return raw.lowercased()
        }
    }

    private static func parseRunDirectory(_ folder: URL) -> WorkflowRun? {
        let candidates = ["status.json", "meta.json", "run.json", "state.json"]
        for name in candidates {
            let file = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path), let run = parseRunFile(file, fallbackName: folder.lastPathComponent) {
                return run
            }
        }
        let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return WorkflowRun(name: folder.lastPathComponent, status: "completed", startedAt: date)
    }

    private static func parseRunFile(_ file: URL, fallbackName: String? = nil) -> WorkflowRun? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let object: [String: Any]
        if file.pathExtension.lowercased() == "jsonl" {
            guard let last = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .reversed()
                .compactMap({ line -> [String: Any]? in
                    guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                    return row
                })
                .first
            else { return nil }
            object = last
        } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = dict
        } else {
            return nil
        }
        let name = (object["display_name"] as? String)
            ?? (object["name"] as? String)
            ?? fallbackName
            ?? file.deletingPathExtension().lastPathComponent
        let status = normalizedStatus(
            (object["status"] as? String) ?? (object["state"] as? String) ?? "completed"
        )
        let startedAt = parseDate(object["started_at"] ?? object["startedAt"] ?? object["created_at"]) 
            ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        let note = (object["note"] as? String) ?? (object["phase"] as? String) ?? ""
        return WorkflowRun(id: name, name: name, status: status, startedAt: startedAt, note: note)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: text)
        }
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        if let number = value as? Int {
            let value = Double(number)
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        return nil
    }
}
