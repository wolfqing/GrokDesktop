import Foundation
import Security

public enum SessionLane: String, Equatable, Sendable {
    case needsInput
    case working
    case done
}

public enum SessionBoard {
    public static let processCap = 3
    public static let idleRecycleSeconds = 30

    public static func lane(needsInput: Bool, working: Bool) -> SessionLane {
        if needsInput { return .needsInput }
        if working { return .working }
        return .done
    }

    /// Leaving a session focused does not stop the others.
    public static func keepStreaming(focusedID: String?, liveIDs: [String]) -> [String] {
        _ = focusedID
        return liveIDs
    }

    public static func recycle(idleSeconds: [String: Int], cap: Int, idleLimit: Int) -> [String] {
        var drop = Set(idleSeconds.filter { $0.value >= idleLimit }.map(\.key))
        var remaining = idleSeconds.count - drop.count
        for pair in idleSeconds.sorted(by: { $0.value > $1.value }) where remaining > cap {
            if drop.insert(pair.key).inserted {
                remaining -= 1
            }
        }
        return drop.sorted()
    }
}

public enum SessionLinks {
    public static let referenceLimit = 3

    public static func fork(sessionID: String, turnID: String) -> String {
        "\(sessionID)#\(turnID)"
    }

    public static func attach(references: [String], sessionID: String) -> [String] {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return references }
        if references.contains(trimmed) { return references }
        if references.count >= referenceLimit { return references }
        return references + [trimmed]
    }
}

public enum SessionArchive {
    public static func root(sessionsRoot: URL) -> URL {
        sessionsRoot.deletingLastPathComponent().appendingPathComponent("session-archive", isDirectory: true)
    }

    public static func move(sessionDirectory: URL, archiveRoot: URL) throws -> URL {
        let cwdName = sessionDirectory.deletingLastPathComponent().lastPathComponent
        let dest = archiveRoot
            .appendingPathComponent(cwdName, isDirectory: true)
            .appendingPathComponent(sessionDirectory.lastPathComponent, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: sessionDirectory, to: dest)
        return dest
    }
}

public enum CLISessionImport {
    public static func candidates(source: URL, destination: URL) -> [String] {
        let src = Set(SessionIndex(sessionsRoot: source).load(limit: 500).map(\.id))
        let dst = Set(SessionIndex(sessionsRoot: destination).load(limit: 500).map(\.id))
        return src.subtracting(dst).sorted()
    }

    public static func copy(id: String, source: URL, destination: URL) throws {
        guard let record = SessionIndex(sessionsRoot: source).load(limit: 500).first(where: { $0.id == id }) else { return }
        let cwdName = record.directory.deletingLastPathComponent().lastPathComponent
        let dest = destination.appendingPathComponent(cwdName, isDirectory: true)
            .appendingPathComponent(record.directory.lastPathComponent, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: record.directory, to: dest)
    }
}

public enum ProjectTrust {
    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public static func allowsWrite(path: String, trusted: Set<String>, enforce: Bool) -> Bool {
        if !enforce { return true }
        return trusted.contains(normalize(path))
    }

    public static func remove(projects: [NamedProject], id: String) -> [NamedProject] {
        projects.filter { $0.id != id }
    }
}

public enum SandboxMode {
    public static func allowsWrite(trusted: Bool, profile: String) -> Bool {
        guard trusted else { return false }
        switch profile {
        case "read-only", "strict": return false
        default: return true
        }
    }
}

public enum ProxyInject {
    public static func environment(base: [String: String], proxy: String) -> [String: String] {
        var env = base
        let trimmed = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return env }
        if trimmed.lowercased().hasPrefix("socks") {
            env["ALL_PROXY"] = trimmed
        } else {
            env["HTTP_PROXY"] = trimmed
            env["HTTPS_PROXY"] = trimmed
            env["http_proxy"] = trimmed
            env["https_proxy"] = trimmed
        }
        return env
    }
}

public enum DoctorKind: String, Equatable, Sendable {
    case cliMissing
    case auth
    case network
    case agentCrash
    case ok
}

public enum Doctor {
    public static func classify(cliFound: Bool, signedIn: Bool, probe: RelayProbeResult?, agentCrashed: Bool) -> DoctorKind {
        if !cliFound { return .cliMissing }
        if !signedIn { return .auth }
        if let probe {
            switch probe {
            case .auth: return .auth
            case .timeout, .dns, .other: return .network
            case .ok: break
            }
        }
        if agentCrashed { return .agentCrash }
        return .ok
    }

    public static func report(kind: DoctorKind, detail: String) -> String {
        DiagnosticExport.redact("doctor \(kind.rawValue)\n\(detail)")
    }

    public static func logDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        home.appendingPathComponent("logs", isDirectory: true)
    }
}

public struct UsageCell: Equatable, Sendable {
    public var day: String
    public var count: Int

    public init(day: String, count: Int) {
        self.day = day
        self.count = count
    }
}

public enum UsageHeatmap {
    public static func quota(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, used / limit))
    }

    public static func cells(timestamps: [Date], now: Date, days: Int, calendar: Calendar = .current) -> [UsageCell] {
        let count = max(1, days)
        var buckets: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for stamp in timestamps {
            buckets[formatter.string(from: stamp), default: 0] += 1
        }
        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) ?? now
            let key = formatter.string(from: day)
            return UsageCell(day: key, count: buckets[key] ?? 0)
        }
    }
}

public enum UsageLedger {
    public static func fileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokDesktop", isDirectory: true)
        return root.appendingPathComponent("usage-ledger.json")
    }

    public static func record(provider: String, at: Date = Date(), url: URL = UsageLedger.fileURL()) {
        var rows = load(url: url)
        rows.append(["provider": provider, "at": ISO8601DateFormatter().string(from: at)])
        let root = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: rows) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func timestamps(url: URL = UsageLedger.fileURL()) -> [Date] {
        let formatter = ISO8601DateFormatter()
        return load(url: url).compactMap { row in
            guard let text = row["at"] as? String else { return nil }
            return formatter.date(from: text)
        }
    }

    private static func load(url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return rows
    }
}

public enum AutomationDraft {
    public static func parse(_ text: String) -> AutomationRecord {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let schedule: String
        if lower.contains("every hour") || lower.contains("每小时") {
            schedule = "1h"
        } else if lower.contains("every week") || lower.contains("每周") {
            schedule = "1w"
        } else {
            schedule = "1d"
        }
        let title = trimmed.split(separator: " ").prefix(6).joined(separator: " ")
        return AutomationRecord(
            title: title.isEmpty ? "Automation" : String(title),
            detail: trimmed,
            prompt: "/loop \(schedule) \(trimmed)"
        )
    }
}

public struct AutomationRun: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var status: String
    public var at: Date

    public init(id: String = UUID().uuidString, title: String, status: String, at: Date = Date()) {
        self.id = id
        self.title = title
        self.status = status
        self.at = at
    }
}

public enum AutomationRuns {
    public static func append(log: [AutomationRun], title: String, status: String, at: Date = Date()) -> [AutomationRun] {
        log + [AutomationRun(title: title, status: status, at: at)]
    }
}

public struct ExtensionToggle: Equatable, Sendable, Codable {
    public var kind: String
    public var name: String
    public var enabled: Bool

    public init(kind: String, name: String, enabled: Bool) {
        self.kind = kind
        self.name = name
        self.enabled = enabled
    }
}

public enum ExtensionToggles {
    public static func set(_ items: [ExtensionToggle], kind: String, name: String, enabled: Bool) -> [ExtensionToggle] {
        var next = items.filter { !($0.kind == kind && $0.name == name) }
        next.append(ExtensionToggle(kind: kind, name: name, enabled: enabled))
        return next.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

    public static func isEnabled(_ items: [ExtensionToggle], kind: String, name: String) -> Bool {
        items.first { $0.kind == kind && $0.name == name }?.enabled ?? true
    }
}

public struct AccountSlot: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public enum AccountSwitch {
    public static func select(slots: [AccountSlot], id: String, active: String) -> String {
        slots.contains(where: { $0.id == id }) ? id : active
    }
}

public enum AccountKeychain {
    public static let service = "com.wolfqing.GrokDesktop.secrets"

    public static func save(account: String, secret: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8)
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func logLine(account: String, secret: String) -> String {
        _ = secret
        return "saved secret for \(account)"
    }
}
