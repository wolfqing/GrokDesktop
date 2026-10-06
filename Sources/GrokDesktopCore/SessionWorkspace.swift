import Foundation

public final class SessionWorkspace: Identifiable {
    public let id: String
    public var cwd: URL
    public var directory: URL?
    public var title: String
    public var items: [ConversationItem] = []
    public var isTurnRunning = false
    public var permission: PermissionRequest?
    public var userQuestion: UserQuestionRequest?
    public var promptQueue: [QueuedPrompt] = []
    public var armedQueueID: String?
    /// The interrupted turn should end without auto-sending whatever is left in the queue.
    public var holdQueue = false
    public var planEntries: [PlanEntry] = []
    public var planMarkdown = ""
    public var hunks: [FileHunk] = []
    public var assistantBufferID: String?
    public var thoughtBufferID: String?
    public var sessionAllowTitles: Set<String> = []
    public var lastError: String?
    public var mode: AgentMode = .normal
    public var loadedOnAgent = false
    public var hydratedFromDisk = false
    public var allowEditsThisSession = false
    public var itemDates: [String: Date] = [:]
    public var itemDurations: [String: TimeInterval] = [:]
    public var itemImages: [String: [URL]] = [:]
    public var turnStartedAt: Date?
    public var todos: [AgentTodo] = []
    public var tasks: [AgentTask] = []
    public var recap = ""
    public var compacted = false
    public var subagents: [AgentSubagent] = []
    public var hookEvents: [HookEvent] = []
    public var checkpoints: [CompactionCheckpoint] = []
    public var scheduledTasks: [ScheduledTask] = []
    public var stopRequested = false
    /// This dispatch started in a git worktree because the repo already had live work.
    public var isolatedCopy = false

    public init(id: String, cwd: URL, directory: URL? = nil, title: String = "") {
        self.id = id
        self.cwd = cwd
        self.directory = directory
        self.title = title
    }

    public var isLive: Bool {
        !stopRequested && (
            isTurnRunning
                || permission != nil
                || userQuestion != nil
                || !promptQueue.isEmpty
                || tasks.contains(where: \.isRunning)
                || subagents.contains(where: \.isRunning)
        )
    }

    public func markWorkStopped() {
        stopRequested = true
        promptQueue.removeAll()
        armedQueueID = nil
        holdQueue = false
        var next = snapshot()
        SessionFold.cancelActiveWork(onto: &next)
        adopt(next)
        finishTurn()
    }

    public func beginTurn(at date: Date = Date()) {
        turnStartedAt = date
        isTurnRunning = true
        stopRequested = false
    }

    public func finishTurn(at date: Date = Date()) {
        isTurnRunning = false
        for index in items.indices {
            if case .assistant(let id, let text, false) = items[index] {
                items[index] = .assistant(id: id, text: text, done: true)
            }
        }
        TurnTiming.stamp(
            onto: &itemDurations,
            items: items,
            dates: itemDates,
            startedAt: turnStartedAt,
            endedAt: date
        )
        turnStartedAt = nil
    }

    public var latestUserPrompt: String {
        for item in items.reversed() {
            if case .user(_, let text) = item {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    public var runningTools: Int {
        items.reduce(0) { count, item in
            if case .tool(_, _, let status, _) = item, status == "running" || status == "pending" {
                return count + 1
            }
            return count
        }
    }

    public var finishedTools: Int {
        items.reduce(0) { count, item in
            if case .tool = item { return count + 1 }
            return count
        }
    }

    public struct ArtifactSnapshot: Sendable {
        public var planMarkdown: String?
        public var hunks: [FileHunk]
        public var checkpoints: [CompactionCheckpoint]

        public init(
            planMarkdown: String? = nil,
            hunks: [FileHunk] = [],
            checkpoints: [CompactionCheckpoint] = []
        ) {
            self.planMarkdown = planMarkdown
            self.hunks = hunks
            self.checkpoints = checkpoints
        }
    }

    public static func readArtifacts(directory: URL) -> ArtifactSnapshot {
        let plan = directory.appendingPathComponent("plan.md")
        let planMarkdown = FileManager.default.fileExists(atPath: plan.path)
            ? (try? String(contentsOf: plan, encoding: .utf8))
            : nil
        return ArtifactSnapshot(
            planMarkdown: planMarkdown,
            hunks: TranscriptLoader.loadHunks(sessionDirectory: directory),
            checkpoints: HarnessEvents.loadCheckpoints(sessionDirectory: directory)
        )
    }

    public func applyArtifacts(_ artifacts: ArtifactSnapshot) {
        if let planMarkdown = artifacts.planMarkdown {
            self.planMarkdown = planMarkdown
        }
        hunks = artifacts.hunks
        guard !artifacts.checkpoints.isEmpty else { return }
        var merged = artifacts.checkpoints
        for live in checkpoints where !merged.contains(where: { $0.id == live.id }) {
            merged.insert(live, at: 0)
        }
        checkpoints = merged
    }

    public func refreshArtifacts() {
        guard let directory else { return }
        applyArtifacts(Self.readArtifacts(directory: directory))
    }
}

public enum AuthPresence: Equatable, Sendable {
    case signedIn
    case apiKey
    case signedOut

    public var isReady: Bool {
        self != .signedOut
    }

    public static func probe(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AuthPresence {
        if let key = environment["XAI_API_KEY"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .apiKey
        }
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .signedOut
        }
        for value in object.values {
            guard let dict = value as? [String: Any] else { continue }
            let email = dict["email"] as? String
            let token = dict["key"] as? String ?? dict["refresh_token"] as? String
            if email?.isEmpty == false || token?.isEmpty == false {
                return .signedIn
            }
        }
        return .signedOut
    }
}

public struct AuthChallenge: Equatable, Sendable {
    public var url: URL?
    public var userCode: String?
    public var message: String?

    public init(url: URL? = nil, userCode: String? = nil, message: String? = nil) {
        self.url = url
        self.userCode = userCode
        self.message = message
    }

    public static func parse(_ value: Any?) -> AuthChallenge {
        guard let dict = value as? [String: Any] else { return AuthChallenge() }
        let rawURL = dict["url"] as? String
            ?? dict["verificationUri"] as? String
            ?? dict["verification_uri"] as? String
            ?? dict["verificationUriComplete"] as? String
        return AuthChallenge(
            url: rawURL.flatMap(URL.init(string:)),
            userCode: dict["userCode"] as? String ?? dict["user_code"] as? String,
            message: dict["message"] as? String
        )
    }
}
