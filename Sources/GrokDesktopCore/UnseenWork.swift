import Foundation

public struct UnseenTurn: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var cwd: String
    public var prompt: String
    public var failed: Bool
    public var finishedAt: Date
    public var changedFiles: Int
    public var isolated: Bool

    public init(
        id: String,
        cwd: String,
        prompt: String,
        failed: Bool,
        finishedAt: Date,
        changedFiles: Int = 0,
        isolated: Bool = false
    ) {
        self.id = id
        self.cwd = cwd
        self.prompt = prompt
        self.failed = failed
        self.finishedAt = finishedAt
        self.changedFiles = changedFiles
        self.isolated = isolated
    }

    private enum CodingKeys: String, CodingKey {
        case id, cwd, prompt, failed, finishedAt, changedFiles, isolated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decode(String.self, forKey: .cwd)
        prompt = try container.decode(String.self, forKey: .prompt)
        failed = try container.decode(Bool.self, forKey: .failed)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        changedFiles = try container.decodeIfPresent(Int.self, forKey: .changedFiles) ?? 0
        isolated = try container.decodeIfPresent(Bool.self, forKey: .isolated) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(failed, forKey: .failed)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(changedFiles, forKey: .changedFiles)
        try container.encode(isolated, forKey: .isolated)
    }

    public var cwdName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    public static func changedFileCount(_ hunks: [FileHunk]) -> Int {
        Set(hunks.map(\.path).filter { !$0.isEmpty }).count
    }

    public static func changePhrase(count: Int, chinese: Bool) -> String {
        if count <= 0 {
            return chinese ? "没有改文件" : "No file changes"
        }
        if chinese { return "\(count) 个文件" }
        return count == 1 ? "1 file" : "\(count) files"
    }

    public func resultLine(chinese: Bool) -> String {
        "\(cwdName) · \(Self.changePhrase(count: changedFiles, chinese: chinese))"
    }

    public func cardLine(chinese: Bool) -> String {
        let place: DispatchPlace = isolated ? .isolatedCopy : .currentDirectory
        return "\(cwdName) · \(place.phrase(chinese: chinese)) · \(Self.changePhrase(count: changedFiles, chinese: chinese))"
    }
}

public enum UnseenStore {
    public static let limit = 12

    public static func record(_ turns: [UnseenTurn], turn: UnseenTurn, limit: Int = UnseenStore.limit) -> [UnseenTurn] {
        var next = turns.filter { $0.id != turn.id }
        next.insert(turn, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }

    public static func clear(_ turns: [UnseenTurn], sessionID: String) -> [UnseenTurn] {
        turns.filter { $0.id != sessionID }
    }

    public static func load(from url: URL) -> [UnseenTurn] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UnseenTurn].self, from: data)) ?? []
    }

    public static func save(_ turns: [UnseenTurn], to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(turns) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func fileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".grok/desktop/unseen.json")
    }
}

public enum UnseenPolicy {
    /// A turn that ended on its own, with nobody watching that session, stays on the dashboard.
    public static func shouldRecord(stopRequested: Bool, isLive: Bool, watching: Bool) -> Bool {
        !stopRequested && !isLive && !watching
    }
}

public struct AttentionSignal: Hashable, Sendable {
    public var sessionID: String
    public var kind: String
    public var token: String

    public init(sessionID: String, kind: String, token: String) {
        self.sessionID = sessionID
        self.kind = kind
        self.token = token
    }
}

public enum RepoAttention {
    /// Question, approval, and unseen-result needs that belong to this project folder.
    public static func count(path: String, needs: [String]) -> Int {
        let key = HistoryFolder.standardizedPath(path)
        guard !key.isEmpty else { return 0 }
        return needs.reduce(into: 0) { total, cwd in
            if HistoryFolder.standardizedPath(cwd) == key {
                total += 1
            }
        }
    }
}

public enum AttentionLanding {
    /// Fresh questions, approvals, and unseen results pull the window to the dashboard.
    /// A draft, web chat, or a need the user already saw does not.
    public static func shouldSwitch(
        needs: Set<AttentionSignal>,
        surfaced: Set<AttentionSignal>,
        onWebChat: Bool,
        draftEmpty: Bool,
        alreadyThere: Bool
    ) -> Bool {
        guard !alreadyThere, !onWebChat, draftEmpty else { return false }
        return !needs.subtracting(surfaced).isEmpty
    }
}
