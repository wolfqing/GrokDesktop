import Foundation

public enum JSONRPCID: Hashable, Sendable {
    case int(Int)
    case string(String)

    public init?(json: Any) {
        if let value = json as? Int {
            self = .int(value)
        } else if let value = json as? NSNumber {
            self = .int(value.intValue)
        } else if let value = json as? String {
            self = .string(value)
        } else {
            return nil
        }
    }

    public var jsonValue: Any {
        switch self {
        case .int(let value): return value
        case .string(let value): return value
        }
    }
}

public struct JSONRPCEnvelope {
    public var id: JSONRPCID?
    public var method: String?
    public var params: [String: Any]
    public var result: Any?
    public var error: [String: Any]?
    public var timestamp: Any?

    public init(id: JSONRPCID? = nil, method: String? = nil, params: [String: Any] = [:], result: Any? = nil, error: [String: Any]? = nil, timestamp: Any? = nil) {
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
        self.timestamp = timestamp
    }

    public static func decode(_ data: Data) throws -> JSONRPCEnvelope {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw ACPError.invalidJSON("root is not an object")
        }
        return JSONRPCEnvelope(
            id: dict["id"].flatMap(JSONRPCID.init(json:)),
            method: dict["method"] as? String,
            params: dict["params"] as? [String: Any] ?? [:],
            result: dict["result"],
            error: dict["error"] as? [String: Any],
            timestamp: dict["timestamp"]
        )
    }

    public func encoded() throws -> Data {
        var body: [String: Any] = ["jsonrpc": "2.0"]
        if let id {
            body["id"] = id.jsonValue
        }
        if let method {
            body["method"] = method
        }
        if !params.isEmpty {
            body["params"] = params
        }
        if let result {
            body["result"] = result
        }
        if let error {
            body["error"] = error
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}

public enum ACPError: Error, Equatable, LocalizedError {
    case invalidJSON(String)
    case grokNotFound
    case processExited(Int32)
    case timeout(String)
    case rpc(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "Invalid ACP JSON: \(detail)"
        case .grokNotFound: return "Could not find the grok CLI."
        case .processExited(let code): return "grok agent exited (\(code))."
        case .timeout(let detail): return "Timed out: \(detail)"
        case .rpc(let detail): return detail
        }
    }
}

public enum SessionUpdateKind: String, Sendable {
    case userMessageChunk = "user_message_chunk"
    case agentMessageChunk = "agent_message_chunk"
    case agentThoughtChunk = "agent_thought_chunk"
    case toolCall = "tool_call"
    case toolCallUpdate = "tool_call_update"
    case plan = "plan"
    case turnCompleted = "turn_completed"
    case taskBackgrounded = "task_backgrounded"
    case taskCompleted = "task_completed"
    case unknown
}

public struct SessionUpdate: Equatable {
    public var kind: SessionUpdateKind
    public var sessionId: String?
    public var text: String
    public var title: String
    public var toolCallId: String?
    public var status: String?
    public var planEntries: [PlanEntry]
    public var timestamp: Date?
    public var imageURLs: [URL]
    public var imageDisplayNumber: Int?
    public var raw: [String: Any]

    public static func == (lhs: SessionUpdate, rhs: SessionUpdate) -> Bool {
        lhs.kind == rhs.kind
            && lhs.sessionId == rhs.sessionId
            && lhs.text == rhs.text
            && lhs.title == rhs.title
            && lhs.toolCallId == rhs.toolCallId
            && lhs.status == rhs.status
            && lhs.planEntries == rhs.planEntries
            && lhs.timestamp == rhs.timestamp
            && lhs.imageURLs == rhs.imageURLs
            && lhs.imageDisplayNumber == rhs.imageDisplayNumber
    }

    public init(
        kind: SessionUpdateKind,
        sessionId: String? = nil,
        text: String = "",
        title: String = "",
        toolCallId: String? = nil,
        status: String? = nil,
        planEntries: [PlanEntry] = [],
        timestamp: Date? = nil,
        imageURLs: [URL] = [],
        imageDisplayNumber: Int? = nil,
        raw: [String: Any] = [:]
    ) {
        self.kind = kind
        self.sessionId = sessionId
        self.text = text
        self.title = title
        self.toolCallId = toolCallId
        self.status = status
        self.planEntries = planEntries
        self.timestamp = timestamp
        self.imageURLs = imageURLs
        self.imageDisplayNumber = imageDisplayNumber
        self.raw = raw
    }

    public static func parse(params: [String: Any], envelopeTimestamp: Any? = nil) -> SessionUpdate {
        let update = params["update"] as? [String: Any] ?? params
        let kindRaw = (update["sessionUpdate"] as? String)
            ?? (update["session_update"] as? String)
            ?? ""
        let kind = SessionUpdateKind(rawValue: kindRaw) ?? .unknown
        let meta = params["_meta"] as? [String: Any] ?? [:]
        let updateMeta = update["_meta"] as? [String: Any] ?? [:]
        let images = PromptMedia.images(in: update)
        return SessionUpdate(
            kind: kind,
            sessionId: params["sessionId"] as? String ?? params["session_id"] as? String,
            text: extractText(update),
            title: update["title"] as? String ?? "",
            toolCallId: update["toolCallId"] as? String ?? update["tool_call_id"] as? String,
            status: update["status"] as? String,
            planEntries: parsePlanEntries(update["entries"]),
            timestamp: PromptTimestamp.parse(
                meta["agentTimestampMs"]
                    ?? updateMeta["agentTimestampMs"]
                    ?? params["timestamp"]
                    ?? envelopeTimestamp
            ),
            imageURLs: images.urls,
            imageDisplayNumber: images.displayNumber,
            raw: update
        )
    }

    public static func extractText(_ update: [String: Any]) -> String {
        if let content = update["content"] as? [String: Any], let text = content["text"] as? String {
            return text
        }
        if let text = update["text"] as? String { return text }
        if let rawOutput = update["rawOutput"] as? String { return rawOutput }
        if let items = update["content"] as? [Any] {
            return items.compactMap(extractContentText).joined(separator: "\n")
        }
        return ""
    }

    private static func extractContentText(_ value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return value as? String }
        if let text = dict["text"] as? String { return text }
        if let content = dict["content"] as? [String: Any], let text = content["text"] as? String {
            return text
        }
        if let content = dict["content"] as? String { return content }
        return nil
    }

    private static func parsePlanEntries(_ value: Any?) -> [PlanEntry] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let content = row["content"] as? String ?? row["title"] as? String ?? ""
            guard !content.isEmpty else { return nil }
            return PlanEntry(
                content: content,
                status: row["status"] as? String ?? "pending",
                priority: row["priority"] as? String ?? "medium"
            )
        }
    }
}

public struct PermissionRequest: Identifiable, Sendable, Equatable {
    public struct Option: Identifiable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var kind: String

        public init(id: String, name: String, kind: String) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    public var id: JSONRPCID
    public var sessionId: String?
    public var title: String
    public var options: [Option]

    public init(id: JSONRPCID, sessionId: String? = nil, title: String, options: [Option]) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.options = options
    }

    public static func parse(id: JSONRPCID, params: [String: Any]) -> PermissionRequest {
        let toolCall = params["toolCall"] as? [String: Any] ?? [:]
        let title = (toolCall["title"] as? String)
            ?? (params["title"] as? String)
            ?? "Approve tool"
        let rawOptions = params["options"] as? [[String: Any]] ?? []
        let options = rawOptions.compactMap { item -> Option? in
            guard let optionId = item["optionId"] as? String ?? item["option_id"] as? String else {
                return nil
            }
            return Option(
                id: optionId,
                name: item["name"] as? String ?? optionId,
                kind: item["kind"] as? String ?? ""
            )
        }
        return PermissionRequest(
            id: id,
            sessionId: params["sessionId"] as? String ?? params["session_id"] as? String,
            title: title,
            options: options
        )
    }
}

public enum ModelTier: String, CaseIterable, Identifiable, Sendable {
    case fast
    case auto
    case expert
    case heavy

    public var id: String { rawValue }

    public var menuTitle: String {
        switch self {
        case .fast: return "Fast"
        case .auto: return "Auto"
        case .expert: return "Expert"
        case .heavy: return "Heavy"
        }
    }

    public var menuSubtitle: String {
        switch self {
        case .fast: return "Quick responses"
        case .auto: return "Uses your default model"
        case .expert: return "Thinks hard · grok-build"
        case .heavy: return "Team of experts · xhigh"
        }
    }

    public var modelID: String? {
        switch self {
        case .fast, .auto: return nil
        case .expert, .heavy: return "grok-build"
        }
    }

    public var effort: String? {
        switch self {
        case .fast: return "low"
        case .auto: return nil
        case .expert: return "high"
        case .heavy: return "xhigh"
        }
    }
}

public enum EffortLevel: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public func title(chinese: Bool) -> String {
        switch self {
        case .low: return chinese ? "低" : "Low"
        case .medium: return chinese ? "中" : "Med"
        case .high: return chinese ? "高" : "High"
        case .xhigh: return chinese ? "极高" : "Max"
        }
    }
}

public enum BuildModel: String, CaseIterable, Identifiable, Sendable {
    case grok46 = "grok-4.6"
    case grok45 = "grok-4.5"
    case grokBuild = "grok-build"

    public var id: String { rawValue }
    public var title: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .grok46: return "4.6"
        case .grok45: return "4.5"
        case .grokBuild: return "Build"
        }
    }

    public var menuTitle: String {
        switch self {
        case .grok46: return "Grok 4.6"
        case .grok45: return "Grok 4.5"
        case .grokBuild: return "Grok Build"
        }
    }
}

public enum AgentMode: String, CaseIterable, Identifiable, Sendable {
    case normal
    case plan
    case auto
    case alwaysApprove

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .plan: return "Plan"
        case .auto: return "Auto"
        case .alwaysApprove: return "Always-approve"
        }
    }

    public var next: AgentMode {
        switch self {
        case .normal: return .plan
        case .plan: return .alwaysApprove
        case .auto: return .alwaysApprove
        case .alwaysApprove: return .normal
        }
    }
}

public extension ModelTier {
    func applied(config: GrokConfig) -> (model: BuildModel, effort: EffortLevel) {
        switch self {
        case .fast:
            return (
                BuildModel(rawValue: config.fastModel) ?? .grok46,
                EffortLevel(rawValue: config.fastEffort) ?? .low
            )
        case .auto:
            return (config.defaultBuildModel, config.defaultEffortLevel)
        case .expert:
            return (
                BuildModel(rawValue: config.expertModel) ?? .grokBuild,
                EffortLevel(rawValue: config.expertEffort) ?? .high
            )
        case .heavy:
            return (
                BuildModel(rawValue: config.heavyModel) ?? .grokBuild,
                EffortLevel(rawValue: config.heavyEffort) ?? .xhigh
            )
        }
    }
}

public struct AgentCapabilities: Equatable, Sendable {
    public var methods: [String]
    public var authMethods: [String]
    public var loadSession: Bool

    public init(methods: [String] = [], authMethods: [String] = [], loadSession: Bool = true) {
        self.methods = methods
        self.authMethods = authMethods
        self.loadSession = loadSession
    }

    public func supports(_ method: String) -> Bool {
        methods.contains(method) || methods.contains(where: { method.hasPrefix($0) })
    }

    public static func parse(_ value: Any?) -> AgentCapabilities {
        guard let dict = value as? [String: Any] else { return AgentCapabilities() }
        var methods: [String] = []
        var auth: [String] = []
        if let caps = dict["agentCapabilities"] as? [String: Any] {
            methods.append(contentsOf: caps.keys)
        }
        if let meta = dict["_meta"] as? [String: Any] {
            if let list = meta["methods"] as? [String] { methods.append(contentsOf: list) }
            if let list = meta["extensionMethods"] as? [String] { methods.append(contentsOf: list) }
        }
        if let rows = dict["authMethods"] as? [[String: Any]] {
            auth = rows.compactMap { $0["id"] as? String ?? $0["name"] as? String }
        }
        let load = ((dict["agentCapabilities"] as? [String: Any])?["loadSession"] as? Bool) ?? true
        return AgentCapabilities(methods: methods, authMethods: auth, loadSession: load)
    }
}
