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
}
