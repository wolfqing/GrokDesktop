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

public struct JSONRPCEnvelope: @unchecked Sendable {
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
    case sessionRecap = "session_recap"
    case autoCompactStarted = "auto_compact_started"
    case autoCompactCompleted = "auto_compact_completed"
    case imageCompressed = "image_compressed"
    case hookExecution = "hook_execution"
    case compactionCheckpoint = "compaction_checkpoint"
    case retryState = "retry_state"
    case hooksChanged = "hooks_changed"
    case pluginsChanged = "plugins_changed"
    case scheduledTaskCreated = "scheduled_task_created"
    case scheduledTaskDeleted = "scheduled_task_deleted"
    case subagentSpawned = "subagent_spawned"
    case subagentFinished = "subagent_finished"
    case notice
    case unknown

    var needsRaw: Bool {
        switch self {
        case .toolCall, .toolCallUpdate, .taskBackgrounded, .taskCompleted,
             .subagentSpawned, .subagentFinished, .retryState,
             .scheduledTaskCreated, .scheduledTaskDeleted,
             .hookExecution, .compactionCheckpoint:
            return true
        default:
            return false
        }
    }
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

    public static let toolDetailLimit = 2_000

    public static func parse(
        params: [String: Any],
        envelopeTimestamp: Any? = nil,
        compactTools: Bool = false
    ) -> SessionUpdate {
        let update = params["update"] as? [String: Any] ?? params
        let kindRaw = (update["sessionUpdate"] as? String)
            ?? (update["session_update"] as? String)
            ?? ""
        let kind = SessionUpdateKind(rawValue: kindRaw) ?? .unknown
        let meta = params["_meta"] as? [String: Any] ?? [:]
        let updateMeta = update["_meta"] as? [String: Any] ?? [:]
        let images = PromptMedia.images(in: update)
        var text = extractText(update)
        if compactTools, kind == .toolCall || kind == .toolCallUpdate, text.count > toolDetailLimit {
            text = String(text.prefix(toolDetailLimit))
        }
        let keepRaw = !compactTools || kind.needsRaw
        return SessionUpdate(
            kind: kind,
            sessionId: params["sessionId"] as? String ?? params["session_id"] as? String,
            text: text,
            title: update["title"] as? String ?? "",
            toolCallId: update["toolCallId"] as? String ?? update["tool_call_id"] as? String,
            status: normalizedStatus(
                update["status"] as? String
                    ?? (meta["updateParams"] as? [String: Any])?["status"] as? String
                    ?? (updateMeta["x.ai/tool"] as? [String: Any])?["status"] as? String
            ),
            planEntries: parsePlanEntries(update["entries"]),
            timestamp: PromptTimestamp.parse(
                meta["agentTimestampMs"]
                    ?? updateMeta["agentTimestampMs"]
                    ?? params["timestamp"]
                    ?? envelopeTimestamp
            ),
            imageURLs: images.urls,
            imageDisplayNumber: images.displayNumber,
            raw: keepRaw ? update : [:]
        )
    }

    public static func normalizedStatus(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "pending": return "pending"
        case "in_progress", "inprogress": return "in_progress"
        case "running": return "running"
        case "completed", "complete", "success": return "completed"
        case "failed", "error": return "failed"
        case "cancelled", "canceled": return "cancelled"
        default: return raw.lowercased()
        }
    }

    public static func extractText(_ update: [String: Any]) -> String {
        if let content = update["content"] as? [String: Any], let text = content["text"] as? String {
            return text
        }
        if let text = update["text"] as? String { return text }
        if let summary = update["summary"] as? String { return summary }
        if let message = update["message"] as? String { return message }
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
    public var kind: String
    public var detail: String
    public var command: String?
    public var path: String?
    public var questions: [UserQuestion]
    public var source: String

    public init(
        id: JSONRPCID,
        sessionId: String? = nil,
        title: String,
        options: [Option],
        kind: String = "",
        detail: String = "",
        command: String? = nil,
        path: String? = nil,
        questions: [UserQuestion] = [],
        source: String = ""
    ) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.options = options
        self.kind = kind
        self.detail = detail
        self.command = command
        self.path = path
        self.questions = questions
        self.source = source
    }

    public var isQuestion: Bool {
        !questions.isEmpty || title.lowercased().contains("ask_user") || title.lowercased().contains("ask user")
    }

    public static func parse(id: JSONRPCID, params: [String: Any]) -> PermissionRequest {
        let toolCall = params["toolCall"] as? [String: Any]
            ?? params["tool_call"] as? [String: Any]
            ?? [:]
        let rawInput = toolCall["rawInput"] as? [String: Any]
            ?? toolCall["raw_input"] as? [String: Any]
            ?? params["rawInput"] as? [String: Any]
            ?? [:]
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
        let command = firstString(rawInput, keys: ["command", "cmd", "shell"])
        let path = firstString(rawInput, keys: ["path", "file_path", "filePath", "target"])
        let detail = permissionDetail(toolCall: toolCall, rawInput: rawInput, command: command, path: path)
        return PermissionRequest(
            id: id,
            sessionId: params["sessionId"] as? String ?? params["session_id"] as? String,
            title: title,
            options: options,
            kind: toolCall["kind"] as? String ?? params["kind"] as? String ?? "",
            detail: detail,
            command: command,
            path: path,
            questions: UserQuestion.parseList(rawInput["questions"] ?? params["questions"] ?? toolCall["questions"]),
            source: permissionSource(params: params, toolCall: toolCall)
        )
    }

    private static func permissionSource(params: [String: Any], toolCall: [String: Any]) -> String {
        let meta = params["_meta"] as? [String: Any] ?? [:]
        let toolMeta = toolCall["_meta"] as? [String: Any] ?? [:]
        let nested = (meta["x.ai/permission"] as? [String: Any])
            ?? (toolMeta["x.ai/permission"] as? [String: Any])
            ?? [:]
        let raw = firstString(nested, keys: ["source", "reason", "rule", "mode"])
            ?? firstString(meta, keys: ["source", "permissionSource", "reason", "rule"])
            ?? firstString(params, keys: ["source", "permissionSource", "reason"])
            ?? firstString(toolCall, keys: ["source", "reason"])
        guard let raw, !raw.isEmpty else { return "" }
        switch raw.lowercased() {
        case "rule", "config": return "rule"
        case "hook": return "hook"
        case "mode", "permission_mode": return "mode"
        case "classifier", "auto": return "classifier"
        case "session", "always_allow": return "session"
        default: return raw
        }
    }

    private static func permissionDetail(
        toolCall: [String: Any],
        rawInput: [String: Any],
        command: String?,
        path: String?
    ) -> String {
        if let command, !command.isEmpty { return command }
        if let path, !path.isEmpty { return path }
        if let description = toolCall["description"] as? String, !description.isEmpty {
            return description
        }
        let extracted = SessionUpdate.extractText(toolCall)
        if !extracted.isEmpty {
            return String(extracted.prefix(400))
        }
        if let description = rawInput["description"] as? String, !description.isEmpty {
            return description
        }
        return ""
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

public enum UserQuestionIntent: Hashable, Sendable {
    case generic
    case planReview(approve: String)

    public static func parse(
        _ raw: Any?,
        question: String,
        header: String,
        detail: String,
        options: [UserQuestionOption]
    ) -> UserQuestionIntent {
        if let dict = raw as? [String: Any] {
            let kind = (dict["kind"] as? String ?? "").lowercased()
            if kind == "plan-review" || kind == "plan_review" || kind == "planreview" {
                let approve = dict["approve"] as? String
                    ?? options.first?.label
                    ?? ""
                if !approve.isEmpty { return .planReview(approve: approve) }
            }
        }
        let blob = (question + " " + header + " " + detail).lowercased()
        let looksLikePlan = blob.contains("plan") || blob.contains("计划")
        if looksLikePlan, let approve = options.first(where: {
            let label = $0.label.lowercased()
            return label.contains("approve") || label.contains("批准") || label.contains("accept")
        }) {
            return .planReview(approve: approve.label)
        }
        return .generic
    }
}

public struct UserQuestion: Identifiable, Hashable, Sendable {
    public var id: String
    public var header: String
    public var question: String
    public var options: [UserQuestionOption]
    public var multiSelect: Bool
    public var detail: String
    public var intent: UserQuestionIntent

    public init(
        id: String = UUID().uuidString,
        header: String = "",
        question: String,
        options: [UserQuestionOption],
        multiSelect: Bool = false,
        detail: String = "",
        intent: UserQuestionIntent = .generic
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
        self.detail = detail
        self.intent = intent
    }

    public static func parseList(_ value: Any?) -> [UserQuestion] {
        if let rows = value as? [[String: Any]] {
            return rows.compactMap(parse)
        }
        if let dict = value as? [String: Any], dict["question"] != nil || dict["options"] != nil {
            return parse(dict).map { [$0] } ?? []
        }
        return []
    }

    public static func parse(_ raw: [String: Any]) -> UserQuestion? {
        let question = (raw["question"] as? String)
            ?? (raw["prompt"] as? String)
            ?? (raw["text"] as? String)
            ?? ""
        let options = parseOptions(raw["options"] ?? raw["choices"])
        if question.isEmpty && options.isEmpty { return nil }
        let detail = raw["detail"] as? String ?? raw["description"] as? String ?? ""
        return UserQuestion(
            id: raw["id"] as? String ?? question,
            header: raw["header"] as? String ?? raw["title"] as? String ?? "",
            question: question,
            options: options,
            multiSelect: raw["multi_select"] as? Bool ?? raw["multiSelect"] as? Bool ?? false,
            detail: detail,
            intent: UserQuestionIntent.parse(raw["intent"], question: question, header: raw["header"] as? String ?? "", detail: detail, options: options)
        )
    }

    private static func parseOptions(_ value: Any?) -> [UserQuestionOption] {
        if let rows = value as? [[String: Any]] {
            return rows.compactMap { row in
                let label = row["label"] as? String ?? row["name"] as? String ?? row["id"] as? String
                guard let label, !label.isEmpty else { return nil }
                return UserQuestionOption(
                    label: label,
                    detail: row["description"] as? String ?? row["detail"] as? String ?? "",
                    preview: row["preview"] as? String
                )
            }
        }
        if let labels = value as? [String] {
            return labels.filter { !$0.isEmpty }.map { UserQuestionOption(label: $0) }
        }
        return []
    }
}

public struct UserQuestionOption: Hashable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var detail: String
    public var preview: String?

    public init(label: String, detail: String = "", preview: String? = nil) {
        self.label = label
        self.detail = detail
        self.preview = preview
    }
}

public struct UserQuestionRequest: Identifiable, Equatable, Sendable {
    public var rpcID: JSONRPCID
    public var sessionId: String?
    public var questions: [UserQuestion]

    public var isPlanReview: Bool {
        questions.contains {
            if case .planReview = $0.intent { return true }
            return false
        }
    }

    public var id: String {
        switch rpcID {
        case .int(let value): return "q-\(value)"
        case .string(let value): return "q-\(value)"
        }
    }

    public init(rpcID: JSONRPCID, sessionId: String? = nil, questions: [UserQuestion]) {
        self.rpcID = rpcID
        self.sessionId = sessionId
        self.questions = questions
    }

    public static func parse(id: JSONRPCID, params: [String: Any]) -> UserQuestionRequest? {
        let questions = UserQuestion.parseList(params["questions"] ?? params["payload"])
        guard !questions.isEmpty else { return nil }
        return UserQuestionRequest(
            rpcID: id,
            sessionId: params["sessionId"] as? String ?? params["session_id"] as? String,
            questions: questions
        )
    }

    public static func isMethod(_ method: String) -> Bool {
        let name = method.split(separator: "/").last.map(String.init) ?? method
        return name == "ask_user_question" || name == "askUserQuestion"
    }
}

public enum UserQuestionOutcome: Equatable, Sendable {
    case accepted(answers: [String: [String]], partial: Bool)
    case chatAboutThis(String)
    case skipInterview

    public var json: [String: Any] {
        switch self {
        case .accepted(let answers, let partial):
            var mapped: [String: Any] = [:]
            for (question, labels) in answers {
                mapped[question] = labels.count == 1 ? labels[0] : labels
            }
            return [
                "type": "Accepted",
                "answers": mapped,
                "partial_answers": partial
            ]
        case .chatAboutThis(let text):
            var body: [String: Any] = ["type": "ChatAboutThis"]
            if !text.isEmpty { body["text"] = text }
            return body
        case .skipInterview:
            return ["type": "SkipInterview"]
        }
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

    public var title: String { self.title(chinese: false) }

    public func title(chinese: Bool) -> String {
        switch self {
        case .normal: return chinese ? "询问" : "Ask me"
        case .plan: return chinese ? "计划" : "Plan"
        case .auto: return chinese ? "自动" : "Auto"
        case .alwaysApprove: return chinese ? "全权" : "Do it"
        }
    }

    public func subtitle(chinese: Bool) -> String {
        switch self {
        case .normal: return chinese ? "做事之前先问你" : "Ask before acting"
        case .plan: return chinese ? "先做计划，你点头再动手" : "Plan first, then act"
        case .auto: return chinese ? "自己判断，必要时再问" : "Act, ask when unsure"
        case .alwaysApprove: return chinese ? "自己干，不再问" : "Act without asking"
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

    public init?(settings: String) {
        switch settings.lowercased() {
        case "ask", "default": self = .normal
        case "plan": self = .plan
        case "auto": self = .auto
        case "always-approve", "bypasspermissions", "dontask": self = .alwaysApprove
        default: return nil
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
