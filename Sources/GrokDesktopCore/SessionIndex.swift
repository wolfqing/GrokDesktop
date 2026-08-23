import Foundation

public struct SessionRecord: Identifiable, Hashable, Sendable {
    public var id: String
    public var cwd: String
    public var title: String
    public var updatedAt: Date
    public var model: String?
    public var directory: URL
    public var messageCount: Int
    public var preview: String

    public init(
        id: String,
        cwd: String,
        title: String,
        updatedAt: Date,
        model: String?,
        directory: URL,
        messageCount: Int = 0,
        preview: String = ""
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self.model = model
        self.directory = directory
        self.messageCount = messageCount
        self.preview = preview
    }

    public var cwdName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public struct SessionIndex {
    public var sessionsRoot: URL
    public var fileManager: FileManager

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/sessions"),
        fileManager: FileManager = .default
    ) {
        self.sessionsRoot = sessionsRoot
        self.fileManager = fileManager
    }

    public func load(limit: Int = 80) -> [SessionRecord] {
        guard let cwdDirs = try? fileManager.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [SessionRecord] = []
        records.reserveCapacity(min(limit, 80))
        for cwdDir in cwdDirs {
            guard isDirectory(cwdDir) else {
                if cwdDir.lastPathComponent == "summary.json", let record = decode(summaryURL: cwdDir) {
                    records.append(record)
                }
                continue
            }
            guard let sessionDirs = try? fileManager.contentsOfDirectory(
                at: cwdDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for sessionDir in sessionDirs {
                let summary = isDirectory(sessionDir)
                    ? sessionDir.appendingPathComponent("summary.json")
                    : sessionDir
                guard summary.lastPathComponent == "summary.json" else { continue }
                if let record = decode(summaryURL: summary) {
                    records.append(record)
                }
            }
        }

        return records
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func directory(cwd: String, id: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
        return sessionsRoot.appendingPathComponent(encoded, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    public func rename(_ record: SessionRecord, title: String) {
        let url = record.directory.appendingPathComponent("summary.json")
        guard let data = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        object["generated_title"] = title
        object["session_summary"] = title
        if let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    public func delete(_ record: SessionRecord) throws {
        try fileManager.removeItem(at: record.directory)
    }

    public func decode(summaryURL: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: summaryURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return nil
        }

        let info = dict["info"] as? [String: Any] ?? [:]
        let id = (info["id"] as? String)
            ?? summaryURL.deletingLastPathComponent().lastPathComponent
        let cwd = (info["cwd"] as? String) ?? ""
        let rawTitle = (dict["generated_title"] as? String)
            ?? (dict["session_summary"] as? String)
            ?? ""
        let title = Self.displayTitle(rawTitle, cwd: cwd)
        let messages = dict["num_messages"] as? Int
            ?? dict["num_chat_messages"] as? Int
            ?? 0
        if title.isEmpty && messages == 0 {
            return nil
        }
        let updated = PromptTimestamp.parse(dict["updated_at"] as? String)
            ?? PromptTimestamp.parse(dict["last_active_at"] as? String)
            ?? .distantPast
        return SessionRecord(
            id: id,
            cwd: cwd,
            title: title.isEmpty ? Self.fallbackTitle(cwd: cwd) : title,
            updatedAt: updated,
            model: dict["current_model_id"] as? String,
            directory: summaryURL.deletingLastPathComponent(),
            messageCount: messages,
            preview: Self.displayTitle(
                dict["last_turn_summary"] as? String ?? "",
                cwd: cwd
            )
        )
    }

    private static func displayTitle(_ raw: String, cwd: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed
    }

    private static func fallbackTitle(cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Untitled" : name
    }

}

public enum SessionSearch {
    public static func matches(
        _ session: SessionRecord,
        query: String,
        now: Date = Date(),
        chinese: Bool = false
    ) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return haystack(session, now: now, chinese: chinese).contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }

    public static func haystack(
        _ session: SessionRecord,
        now: Date = Date(),
        chinese: Bool = false
    ) -> [String] {
        var tokens = [
            session.title,
            session.preview,
            session.cwd,
            session.cwdName,
            session.model ?? "",
            RelativeTime.format(session.updatedAt, now: now, chinese: true),
            RelativeTime.format(session.updatedAt, now: now, chinese: false),
            RelativeTime.meta(session, now: now, chinese: chinese),
            PromptTimestamp.format(session.updatedAt)
        ]
        tokens.append(contentsOf: dayTokens(session.updatedAt, now: now))
        return tokens.filter { !$0.isEmpty }
    }

    public static func dayTokens(_ date: Date, now: Date = Date()) -> [String] {
        let calendar = Calendar.current
        var tokens: [String] = []
        if calendar.isDate(date, inSameDayAs: now) {
            tokens.append(contentsOf: ["today", "今天"])
        }
        if calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            tokens.append(contentsOf: ["yesterday", "昨天"])
        }
        let posix = DateFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.dateFormat = "yyyy-MM-dd"
        tokens.append(posix.string(from: date))
        let english = DateFormatter()
        english.locale = Locale(identifier: "en_US")
        english.dateFormat = "MMM d"
        tokens.append(english.string(from: date))
        let chinese = DateFormatter()
        chinese.locale = Locale(identifier: "zh_CN")
        chinese.dateFormat = "M月d日"
        tokens.append(chinese.string(from: date))
        return tokens
    }
}
