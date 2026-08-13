import Foundation

public struct SessionRecord: Identifiable, Hashable, Sendable {
    public var id: String
    public var cwd: String
    public var title: String
    public var updatedAt: Date
    public var model: String?
    public var directory: URL

    public init(id: String, cwd: String, title: String, updatedAt: Date, model: String?, directory: URL) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self.model = model
        self.directory = directory
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
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [SessionRecord] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "summary.json" else { continue }
            if let record = decode(summaryURL: url) {
                records.append(record)
            }
        }

        return records
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
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
        let title = (dict["generated_title"] as? String)
            ?? (dict["session_summary"] as? String)
            ?? "Untitled"
        let updated = parseDate(dict["updated_at"] as? String)
            ?? parseDate(dict["last_active_at"] as? String)
            ?? .distantPast
        return SessionRecord(
            id: id,
            cwd: cwd,
            title: title,
            updatedAt: updated,
            model: dict["current_model_id"] as? String,
            directory: summaryURL.deletingLastPathComponent()
        )
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }
}
