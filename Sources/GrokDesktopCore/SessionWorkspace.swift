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
    public var planEntries: [PlanEntry] = []
    public var planMarkdown = ""
    public var hunks: [FileHunk] = []
    public var assistantBufferID: String?
    public var thoughtBufferID: String?
    public var sessionAllowTitles: Set<String> = []
    public var lastError: String?
    public var mode: AgentMode = .normal
    public var loadedOnAgent = false
    public var allowEditsThisSession = false
    public var itemDates: [String: Date] = [:]
    public var itemImages: [String: [URL]] = [:]
    public var todos: [AgentTodo] = []
    public var tasks: [AgentTask] = []
    public var stopRequested = false

    public init(id: String, cwd: URL, directory: URL? = nil, title: String = "") {
        self.id = id
        self.cwd = cwd
        self.directory = directory
        self.title = title
    }

    public var isLive: Bool {
        !stopRequested && (isTurnRunning || permission != nil || userQuestion != nil || !promptQueue.isEmpty)
    }

    public func markWorkStopped() {
        stopRequested = true
        isTurnRunning = false
        promptQueue.removeAll()
        for index in todos.indices where todos[index].isActive {
            todos[index].status = "cancelled"
        }
        for index in tasks.indices where tasks[index].isRunning {
            tasks[index].status = "cancelled"
            tasks[index].endedAt = Date()
        }
        for index in items.indices {
            if case .tool(let id, let title, let status, let detail) = items[index],
               status == "running" || status == "pending" || status == "in_progress" {
                items[index] = .tool(id: id, title: title, status: "cancelled", detail: detail)
            }
        }
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

    public func refreshArtifacts() {
        guard let directory else { return }
        let plan = directory.appendingPathComponent("plan.md")
        if FileManager.default.fileExists(atPath: plan.path) {
            planMarkdown = (try? String(contentsOf: plan, encoding: .utf8)) ?? planMarkdown
        }
        hunks = TranscriptLoader.loadHunks(sessionDirectory: directory)
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
