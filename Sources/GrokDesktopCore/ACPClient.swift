import Foundation

public enum ACPConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case initialized
    case ready
    case failed(String)
}

@MainActor
public final class ACPClient: ObservableObject {
    public let locator: GrokBinaryLocator

    @Published public private(set) var state: ACPConnectionState = .idle
    @Published public private(set) var sessionID: String?
    @Published public private(set) var items: [ConversationItem] = []
    @Published public private(set) var isTurnRunning = false
    @Published public private(set) var isStopping = false
    @Published public private(set) var permission: PermissionRequest?
    @Published public private(set) var userQuestion: UserQuestionRequest?
    @Published public private(set) var lastError: String?
    @Published public private(set) var stderrLines: [String] = []
    @Published public private(set) var decodeFailures = 0
    @Published public private(set) var grokVersion: String?
    @Published public var workingDirectory: URL
    @Published public var modelTier: ModelTier = .auto
    @Published public var buildModel: BuildModel = .grok45
    @Published public var effort: EffortLevel = .medium
    @Published public var mode: AgentMode = .normal
    @Published public var planEntries: [PlanEntry] = []
    @Published public var planMarkdown = ""
    @Published public var hunks: [FileHunk] = []
    @Published public var promptQueue: [QueuedPrompt] = []
    @Published public var sessionDirectory: URL?
    @Published public private(set) var liveWorkspaces: [SessionWorkspace] = []
    @Published public private(set) var authPresence: AuthPresence = .signedOut
    @Published public private(set) var authChallenge: AuthChallenge?
    @Published public private(set) var itemDates: [String: Date] = [:]
    @Published public private(set) var itemDurations: [String: TimeInterval] = [:]
    @Published public private(set) var itemImages: [String: [URL]] = [:]
    @Published public private(set) var todos: [AgentTodo] = []
    @Published public private(set) var tasks: [AgentTask] = []
    @Published public private(set) var recap = ""
    @Published public private(set) var compacted = false
    @Published public private(set) var subagents: [AgentSubagent] = []
    @Published public private(set) var events: [ACPEvent] = []
    @Published public private(set) var terminals: [TerminalSnapshot] = []
    @Published public var allowEditsThisSession = false
    @Published public private(set) var capabilities = AgentCapabilities()
    @Published public var gitStatusText = ""
    @Published public var gitDiffText = ""
    @Published public private(set) var isReconnecting = false
    @Published public private(set) var isLoadingSession = false

    public var runningTools: Int { currentWorkspace?.runningTools ?? 0 }

    public var finishedTools: Int { currentWorkspace?.finishedTools ?? 0 }

    public var isLive: Bool {
        liveWorkspaces.contains { $0.isLive }
    }

    public var currentWorkspace: SessionWorkspace? {
        sessionID.flatMap { workspaceByID[$0] }
    }

    public var backgroundPermissions: [SessionWorkspace] {
        liveWorkspaces.filter { $0.id != sessionID && $0.permission != nil }
    }

    public var backgroundQuestions: [SessionWorkspace] {
        liveWorkspaces.filter { $0.id != sessionID && $0.userQuestion != nil }
    }

    public var hasBackgroundWork: Bool {
        liveWorkspaces.contains { $0.id != sessionID && $0.isLive }
    }

    public var backgroundLiveTasks: [(sessionID: String, title: String, task: AgentTask)] {
        workspaceByID.values
            .filter { $0.id != sessionID }
            .flatMap { workspace in
                workspace.tasks.filter(\.isRunning).map {
                    (workspace.id, workspace.title.isEmpty ? String(workspace.id.prefix(8)) : workspace.title, $0)
                }
            }
    }

    public var config: GrokConfig { configStore.load() }

    private let configStore: ConfigStore
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var nextID = 1
    private var pending: [JSONRPCID: CheckedContinuation<JSONRPCEnvelope, Error>] = [:]
    private var stdoutBuffer = Data()
    private var assistantBufferID: String?
    private var thoughtBufferID: String?
    private var sessionAllowTitles: Set<String> = []
    private var lastSessionID: String?
    private var pendingWorkingDirectory: URL?
    private var shouldReconnect = true
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var workspaceByID: [String: SessionWorkspace] = [:]
    private var retainedSessionIDs: [String] = []
    private var loadGeneration = 0
    private let terminalsHost = TerminalHost()

    public init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configStore: ConfigStore = ConfigStore()
    ) {
        self.locator = locator
        self.workingDirectory = workingDirectory
        self.configStore = configStore
        apply(tier: .auto)
        grokVersion = Self.readVersion(locator: locator)
        authPresence = AuthPresence.probe()
        terminalsHost.onChange = { [weak self] in
            Task { @MainActor in
                self?.refreshTerminals()
            }
        }
    }

    public func refreshTerminals() {
        terminals = terminalsHost.snapshots
    }

    public func killTerminal(_ id: String) {
        terminalsHost.kill(id: id)
        terminals = terminalsHost.snapshots
    }

    public var grokURL: URL? { locator.locate() }

    public func apply(tier: ModelTier) {
        modelTier = tier
        let applied = tier.applied(config: configStore.load())
        buildModel = applied.model
        effort = applied.effort
    }

    public func connectIfNeeded() async throws {
        if (state == .initialized || state == .ready), process?.isRunning == true { return }
        try await start()
    }

    public func start() async throws {
        stop(reconnect: false)
        shouldReconnect = true
        guard let grok = locator.locate() else {
            state = .failed(ACPError.grokNotFound.localizedDescription)
            throw ACPError.grokNotFound
        }

        state = .connecting
        grokVersion = Self.readVersion(locator: locator)
        let process = Process()
        process.executableURL = grok
        process.arguments = ["agent", "--no-leader", "stdio"]
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        let extras = [
            grok.deletingLastPathComponent().path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        environment["PATH"] = (extras + [environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdinHandle = stdin.fileHandleForWriting

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in
                self?.consume(stdout: chunk)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendStderr(text)
            }
        }
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(code: proc.terminationStatus)
            }
        }

        try process.run()
        self.process = process

        let handshake = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientInfo": [
                    "name": "GrokDesktop",
                    "version": "0.1.17"
                ],
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": true,
                        "writeTextFile": true
                    ],
                    "terminal": true
                ]
            ]
        )
        capabilities = AgentCapabilities.parse(handshake.result)
        state = .initialized
        decodeFailures = 0
        reconnectAttempt = 0
        isReconnecting = false
        refreshAuth()
        if authPresence == .signedOut, capabilities.authMethods.isEmpty == false {
            // Agent advertised auth; session/new will fail until the user signs in.
        }
    }

    public func newSession(cwd: URL? = nil) async throws {
        let target = cwd ?? pendingWorkingDirectory ?? workingDirectory
        pendingWorkingDirectory = target
        workingDirectory = target
        defer { pendingWorkingDirectory = nil }
        try await connectIfNeeded()
        workingDirectory = target
        var meta: [String: Any] = [:]
        if mode == .alwaysApprove {
            meta["yoloMode"] = true
        }
        if mode == .auto {
            meta["autoMode"] = true
        }
        let result = try await request(
            method: "session/new",
            params: [
                "cwd": target.path,
                "mcpServers": [],
                "_meta": meta
            ]
        )
        sessionID = firstString(result.result, keys: ["sessionId", "session_id"])
        lastSessionID = sessionID
        guard let sessionID else {
            throw ACPError.rpc("No session")
        }
        workingDirectory = target
        let directory = SessionIndex().directory(cwd: target.path, id: sessionID)
        sessionDirectory = directory
        let workspace = ensureWorkspace(id: sessionID, cwd: target, directory: directory)
        workspace.cwd = target
        workspace.items = []
        workspace.planEntries = []
        workspace.planMarkdown = ""
        workspace.hunks = []
        workspace.promptQueue = []
        workspace.sessionAllowTitles = []
        workspace.assistantBufferID = nil
        workspace.thoughtBufferID = nil
        workspace.permission = nil
        workspace.userQuestion = nil
        workspace.lastError = nil
        workspace.mode = mode
        workspace.loadedOnAgent = true
        workspace.itemDates = [:]
        workspace.itemDurations = [:]
        workspace.turnStartedAt = nil
        workspace.itemImages = [:]
        workspace.todos = []
        workspace.tasks = []
        workspace.recap = ""
        workspace.compacted = false
        workspace.subagents = []
        workspace.stopRequested = false
        workspace.isTurnRunning = false
        workspace.hydratedFromDisk = false
        rememberLoaded(sessionID)
        lastError = nil
        state = .ready
        syncFromCurrent()
        refreshPlanArtifacts()
    }

    @discardableResult
    public func focusIfLoaded(_ id: String) -> Bool {
        guard let workspace = workspaceByID[id], workspace.loadedOnAgent else {
            return false
        }
        sessionID = workspace.id
        lastSessionID = workspace.id
        workingDirectory = workspace.cwd
        sessionDirectory = workspace.directory
        mode = workspace.mode
        state = .ready
        isLoadingSession = false
        syncFromCurrent()
        return true
    }

    public func loadSession(id: String, cwd: URL, directory: URL? = nil) async throws {
        loadGeneration += 1
        let generation = loadGeneration
        workingDirectory = cwd
        sessionDirectory = directory ?? SessionIndex().directory(cwd: cwd.path, id: id)
        let workspace = ensureWorkspace(id: id, cwd: cwd, directory: sessionDirectory)
        workspace.cwd = cwd
        if workspace.directory == nil {
            workspace.directory = sessionDirectory
        }
        sessionID = id
        lastSessionID = id
        isLoadingSession = workspace.items.isEmpty && !workspace.hydratedFromDisk
        syncFromCurrent()

        if workspace.loadedOnAgent {
            isLoadingSession = false
            return
        }

        if !workspace.hydratedFromDisk {
            let dir = sessionDirectory
            let transcript = await Task.detached(priority: .userInitiated) {
                dir.map { TranscriptLoader.load(sessionDirectory: $0, includeHunks: false) }
            }.value
            guard generation == loadGeneration else { return }
            if let transcript {
                workspace.adopt(transcript)
                workspace.hydratedFromDisk = true
            }
            workspace.assistantBufferID = nil
            workspace.thoughtBufferID = nil
            if !workspace.isLive {
                workspace.permission = nil
                workspace.userQuestion = nil
            }
        }

        if sessionID == id {
            isLoadingSession = false
            syncFromCurrent()
        }

        do {
            try await ensureAgentLoaded(workspace)
            guard generation == loadGeneration else { return }
            if sessionID == id {
                lastError = nil
                isReconnecting = false
                state = .ready
                workspace.refreshArtifacts()
                syncFromCurrent()
            }
        } catch {
            guard generation == loadGeneration else { throw error }
            workspace.loadedOnAgent = false
            if isReconnecting, !workspace.items.isEmpty {
                if sessionID == id { syncFromCurrent() }
                throw error
            }
            workspace.lastError = error.localizedDescription
            if sessionID == id {
                lastError = error.localizedDescription
            }
            if !workspace.items.contains(where: {
                if case .notice(_, let text) = $0 { return text == error.localizedDescription }
                return false
            }) {
                workspace.fold(SessionFold.notice(error.localizedDescription))
            }
            if sessionID == id {
                syncFromCurrent()
            }
            throw error
        }
    }

    private func ensureAgentLoaded(_ workspace: SessionWorkspace) async throws {
        if workspace.loadedOnAgent { return }
        try await connectIfNeeded()
        _ = try await request(
            method: "session/load",
            params: [
                "sessionId": workspace.id,
                "cwd": workspace.cwd.path,
                "mcpServers": []
            ]
        )
        workspace.loadedOnAgent = true
        rememberLoaded(workspace.id)
        workspace.lastError = nil
    }

    public func send(text: String, sessionID target: String? = nil, kind: QueuedPrompt.Kind = .followUp) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await connectIfNeeded()
        if sessionID == nil, target == nil {
            try await newSession()
        }
        let id = target ?? sessionID
        guard let id, let workspace = workspaceByID[id] ?? currentWorkspace else {
            throw ACPError.rpc("No session")
        }
        if !workspace.loadedOnAgent {
            try await ensureAgentLoaded(workspace)
        }
        if workspace.isTurnRunning {
            workspace.promptQueue.append(QueuedPrompt(text: trimmed, kind: kind))
            syncFromCurrent()
            return
        }

        let lastUser = workspace.items.last.flatMap { item -> String? in
            if case .user(_, let existing) = item { return existing }
            return nil
        }
        if lastUser != trimmed {
            workspace.fold(SessionFold.userTurn(trimmed))
        }
        workspace.beginTurn()
        isStopping = false
        workspace.assistantBufferID = nil
        workspace.thoughtBufferID = nil
        workspace.lastError = nil
        lastError = nil
        syncFromCurrent()

        apply(tier: modelTier)
        var params: [String: Any] = [
            "sessionId": id,
            "prompt": PromptMedia.promptBlocks(from: trimmed),
            "model": buildModel.rawValue
        ]
        var meta: [String: Any] = [
            "effort": effort.rawValue,
            "yoloMode": workspace.mode == .alwaysApprove,
            "autoMode": workspace.mode == .auto
        ]
        if modelTier == .heavy {
            meta["allowSubagents"] = true
        }
        params["_meta"] = meta
        do {
            _ = try await request(method: "session/prompt", params: params)
        } catch {
            if !workspace.stopRequested, !Self.isCancelError(error) {
                workspace.lastError = error.localizedDescription
                workspace.fold(SessionFold.notice(error.localizedDescription))
                lastError = error.localizedDescription
            }
        }
        workspace.finishTurn()
        workspace.refreshArtifacts()
        syncFromCurrent()
        if workspace.stopRequested {
            workspace.promptQueue.removeAll()
            return
        }
        if let next = workspace.promptQueue.first {
            workspace.promptQueue.removeFirst()
            try await send(text: next.text, sessionID: id, kind: next.kind)
        }
    }

    public func sendNow(text: String, sessionID target: String? = nil) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await connectIfNeeded()
        if sessionID == nil, target == nil {
            try await newSession()
        }
        let id = target ?? sessionID
        guard let id, let workspace = workspaceByID[id] ?? currentWorkspace else {
            throw ACPError.rpc("No session")
        }
        if workspace.isTurnRunning {
            workspace.promptQueue.removeAll { $0.text == trimmed }
            workspace.promptQueue.insert(QueuedPrompt(text: trimmed, kind: .followUp), at: 0)
            fire(method: "session/cancel", params: ["sessionId": id])
            syncFromCurrent()
            return
        }
        try await send(text: trimmed, sessionID: id)
    }

    public func cancelTurn(sessionID target: String? = nil) {
        stopWork(sessionID: target)
    }

    public func stopWork(sessionID target: String? = nil) {
        let id = target ?? sessionID
        isStopping = true
        if let id {
            fire(method: "session/cancel", params: ["sessionId": id])
            if let workspace = workspaceByID[id] {
                let runningTaskIDs = workspace.tasks.filter(\.isRunning).map(\.id)
                workspace.markWorkStopped()
                if let permission = workspace.permission {
                    workspace.permission = nil
                    respond(id: permission.id, result: ["outcome": ["outcome": "cancelled"]])
                }
                if let question = workspace.userQuestion {
                    workspace.userQuestion = nil
                    respond(id: question.rpcID, result: UserQuestionOutcome.skipInterview.json)
                }
                for taskID in runningTaskIDs {
                    let params: [String: Any] = ["taskId": taskID, "task_id": taskID, "sessionId": id]
                    fire(method: "x.ai/task/kill", params: params)
                }
            }
        }
        isTurnRunning = false
        syncFromCurrent()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.currentWorkspace?.stopRequested == true || !self.hasActiveWork {
                self.isStopping = false
                self.syncFromCurrent()
            }
        }
    }

    public func killTask(_ taskID: String, sessionID target: String? = nil) {
        let id = target ?? sessionID
        var params: [String: Any] = ["taskId": taskID, "task_id": taskID]
        if let id {
            params["sessionId"] = id
        }
        fire(method: "x.ai/task/kill", params: params)
        let workspace = id.flatMap { workspaceByID[$0] } ?? currentWorkspace
        if let workspace, let index = workspace.tasks.firstIndex(where: { $0.id == taskID }) {
            workspace.tasks[index].status = "cancelled"
            workspace.tasks[index].endedAt = Date()
        }
        syncFromCurrent()
    }

    public var hasActiveWork: Bool {
        if isStopping { return true }
        guard currentWorkspace?.stopRequested != true else { return false }
        return isTurnRunning || tasks.contains(where: \.isRunning)
    }

    public func answerPermission(optionID: String, rememberSession: Bool = false, sessionID target: String? = nil) {
        let workspace = (target ?? sessionID).flatMap { workspaceByID[$0] } ?? currentWorkspace
        guard let workspace, let permission = workspace.permission else { return }
        if rememberSession {
            workspace.sessionAllowTitles.insert(permission.title)
        }
        respond(
            id: permission.id,
            result: [
                "outcome": [
                    "outcome": "selected",
                    "optionId": optionID
                ]
            ]
        )
        workspace.permission = nil
        syncFromCurrent()
    }

    public func answerQuestion(_ outcome: UserQuestionOutcome, sessionID target: String? = nil) {
        let workspace = (target ?? sessionID).flatMap { workspaceByID[$0] } ?? currentWorkspace
        guard let workspace, let question = workspace.userQuestion else { return }
        respond(id: question.rpcID, result: outcome.json)
        workspace.userQuestion = nil
        if case .chatAboutThis(let text) = outcome {
            let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                Task { try? await send(text: note, sessionID: workspace.id) }
            }
        }
        syncFromCurrent()
    }

    public func rejectPermission(sessionID target: String? = nil) {
        let workspace = (target ?? sessionID).flatMap { workspaceByID[$0] } ?? currentWorkspace
        guard let workspace, let permission = workspace.permission else { return }
        if let cancel = permission.options.first(where: { $0.kind.contains("reject") || $0.id.contains("cancel") }) {
            answerPermission(optionID: cancel.id, sessionID: workspace.id)
            return
        }
        respond(id: permission.id, result: ["outcome": ["outcome": "cancelled"]])
        workspace.permission = nil
        syncFromCurrent()
    }

    public func approvePlan() async {
        if let permission, isPlanPermission(permission) {
            if let allow = permission.options.first(where: { !$0.kind.contains("reject") }) {
                answerPermission(optionID: allow.id)
            }
        }
        mode = .normal
        try? await send(text: "Approve the plan in plan.md and start implementing.")
    }

    public func requestPlanChanges(_ note: String) async {
        mode = .plan
        let body = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await send(text: body.isEmpty ? "Request changes to the plan. Revise plan.md." : body)
    }

    public func quitPlan() {
        mode = .normal
        if let permission, isPlanPermission(permission) {
            rejectPermission()
        }
    }

    public func forkSession() async throws {
        guard let sessionID else { throw ACPError.rpc("No session") }
        do {
            let result = try await request(
                method: "x.ai/session/fork",
                params: ["sessionId": sessionID]
            )
            if let forked = firstString(result.result, keys: ["sessionId", "session_id"]) {
                try await loadSession(id: forked, cwd: workingDirectory)
                return
            }
        } catch {
            lastError = error.localizedDescription
        }
        try await send(text: "/fork")
    }

    public func dropWorkspace(_ id: String) {
        workspaceByID[id] = nil
        retainedSessionIDs.removeAll { $0 == id }
        if sessionID == id {
            resetConversation()
        } else {
            refreshLive()
        }
    }

    public func resetConversation() {
        if let question = currentWorkspace?.userQuestion {
            currentWorkspace?.userQuestion = nil
            respond(id: question.rpcID, result: UserQuestionOutcome.skipInterview.json)
        }
        sessionID = nil
        isLoadingSession = false
        items = []
        permission = nil
        userQuestion = nil
        assistantBufferID = nil
        thoughtBufferID = nil
        isTurnRunning = false
        planEntries = []
        planMarkdown = ""
        hunks = []
        promptQueue = []
        sessionAllowTitles = []
        sessionDirectory = nil
        itemDates = [:]
        itemDurations = [:]
        itemImages = [:]
        todos = []
        tasks = []
        recap = ""
        compacted = false
        subagents = []
        if process?.isRunning == true {
            state = .initialized
        }
        refreshLive()
    }

    public func refreshAuth() {
        authPresence = AuthPresence.probe()
    }

    @discardableResult
    public func beginLogin() async throws -> AuthChallenge {
        try await connectIfNeeded()
        do {
            let result = try await request(method: "x.ai/auth/get_url", params: [:])
            let challenge = AuthChallenge.parse(result.result)
            authChallenge = challenge
            return challenge
        } catch {
            authChallenge = AuthChallenge(message: error.localizedDescription)
            throw error
        }
    }

    public func submitLoginCode(_ code: String) async throws {
        _ = try await request(method: "x.ai/auth/submit_code", params: ["code": code])
        refreshAuth()
        authChallenge = nil
    }

    public func stop() {
        stop(reconnect: false)
    }

    public func dismissError() {
        lastError = nil
        currentWorkspace?.lastError = nil
    }

    /// Seeds a static transcript for screenshots. Does not touch disk or start grok.
    public func applyDemo(
        items: [ConversationItem],
        todos: [AgentTodo],
        hunks: [FileHunk],
        planEntries: [PlanEntry],
        gitDiff: String,
        cwd: URL
    ) {
        resetConversation()
        sessionID = "demo-northwind"
        workingDirectory = cwd
        self.items = items
        self.todos = todos
        self.hunks = hunks
        self.planEntries = planEntries
        gitDiffText = gitDiff
        gitStatusText = "main"
        state = .ready
        lastError = nil
        isTurnRunning = false
        isReconnecting = false
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectAttempt = 0
        lastSessionID = nil
    }

    public func setMode(_ newMode: AgentMode) {
        mode = newMode
        currentWorkspace?.mode = newMode
    }

    public func setAllowEditsThisSession(_ enabled: Bool) {
        allowEditsThisSession = enabled
        currentWorkspace?.allowEditsThisSession = enabled
    }

    public func rewind(toPromptIndex index: Int? = nil) async {
        guard let sessionID else { return }
        do {
            var params: [String: Any] = ["sessionId": sessionID]
            if let index {
                params["promptIndex"] = index
                params["prompt_index"] = index
            }
            _ = try await request(method: "x.ai/rewind", params: params)
        } catch {
            if let index {
                try? await send(text: "/rewind \(index + 1)")
            } else {
                try? await send(text: "/rewind")
            }
        }
        if let directory = sessionDirectory {
            let transcript = await Task.detached(priority: .userInitiated) {
                TranscriptLoader.load(sessionDirectory: directory, includeHunks: false)
            }.value
            currentWorkspace?.adopt(transcript)
            currentWorkspace?.hydratedFromDisk = true
            syncFromCurrent()
        }
    }

    public func refreshGit() async {
        gitStatusText = ""
        gitDiffText = ""
        if let status = try? await request(method: "x.ai/git/status", params: ["cwd": workingDirectory.path]) {
            gitStatusText = Self.pretty(status.result)
        }
        if let diffs = try? await request(method: "x.ai/git/diffs", params: ["cwd": workingDirectory.path]) {
            let extracted = DiffScan.extractPatch(from: diffs.result)
            gitDiffText = extracted.isEmpty ? Self.pretty(diffs.result) : extracted
        }
        if gitDiffText.isEmpty {
            let cwd = workingDirectory
            gitDiffText = await Task.detached { DiffScan.workspaceDiff(cwd: cwd) }.value
        }
        if gitStatusText.isEmpty, gitDiffText.isEmpty {
            // keep WorkspaceSnapshot as the fallback
        }
    }

    public func listRemoteFiles(query: String) async -> [URL] {
        guard let result = try? await request(
            method: "x.ai/fs/list",
            params: [
                "path": workingDirectory.path,
                "query": query
            ]
        ) else { return [] }
        return Self.urls(from: result.result)
    }

    public func compact(note: String = "") async {
        guard let sessionID else { return }
        do {
            var params: [String: Any] = ["sessionId": sessionID]
            if !note.isEmpty { params["context"] = note }
            _ = try await request(method: "x.ai/compact_conversation", params: params)
        } catch {
            try? await send(text: note.isEmpty ? "/compact" : "/compact \(note)")
        }
    }

    private func isEditPermission(_ request: PermissionRequest) -> Bool {
        let blob = (request.title + " " + request.options.map(\.id).joined()).lowercased()
        return blob.contains("edit") || blob.contains("write") || blob.contains("search_replace") || blob.contains("apply")
    }

    public func refreshPlanArtifacts() {
        currentWorkspace?.refreshArtifacts()
        syncFromCurrent()
    }

    private func stop(reconnect: Bool) {
        shouldReconnect = reconnect
        reconnectTask?.cancel()
        stdinHandle = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        for (_, continuation) in pending {
            continuation.resume(throwing: ACPError.processExited(1))
        }
        pending.removeAll()
        if !reconnect {
            state = .idle
            isReconnecting = false
            reconnectAttempt = 0
            terminalsHost.releaseAll()
            terminals = []
        }
        isTurnRunning = false
    }

    private func handleTermination(code: Int32) {
        for (_, continuation) in pending {
            continuation.resume(throwing: ACPError.processExited(code))
        }
        pending.removeAll()
        for workspace in workspaceByID.values {
            workspace.isTurnRunning = false
            workspace.loadedOnAgent = false
            workspace.userQuestion = nil
        }
        userQuestion = nil
        isTurnRunning = false
        refreshLive()
        guard shouldReconnect, lastSessionID != nil else {
            let message = ACPError.processExited(code).localizedDescription
            state = .failed(message)
            lastError = message
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        isReconnecting = true
        lastError = nil
        state = .connecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            self.reconnectAttempt += 1
            if self.reconnectAttempt > 8 {
                self.isReconnecting = false
                self.state = .failed("Lost grok agent.")
                self.lastError = "Lost grok agent."
                return
            }
            let delay = UInt64(min(1.2 * pow(2.0, Double(self.reconnectAttempt - 1)), 20.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, self.shouldReconnect else { return }
            do {
                try await self.start()
                await self.reloadRetainedSessions(focus: self.lastSessionID)
                self.isReconnecting = false
            } catch {
                self.scheduleReconnect()
            }
        }
    }

    private func consume(stdout chunk: Data) {
        stdoutBuffer.append(chunk)
        while let range = stdoutBuffer.range(of: Data([0x0A])) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<range.upperBound)
            guard !line.isEmpty else { continue }
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard let envelope = try? JSONRPCEnvelope.decode(line) else {
            decodeFailures += 1
            appendStderr("Invalid ACP JSON: \(String(data: line, encoding: .utf8) ?? "<binary>")")
            if decodeFailures >= 8 {
                lastError = "Repeated invalid ACP JSON. Reconnecting."
                process?.terminate()
            }
            return
        }

        if let method = envelope.method {
            recordEvent(inbound: true, method: method, params: envelope.params)
        }

        if let method = envelope.method, let id = envelope.id, UserQuestionRequest.isMethod(method) {
            present(questionID: id, params: envelope.params)
            return
        }

        if let method = envelope.method, let id = envelope.id, handleClientRequest(id: id, method: method, params: envelope.params) {
            return
        }

        if let method = envelope.method, envelope.id != nil, method == "session/request_permission" {
            if let id = envelope.id {
                let request = PermissionRequest.parse(id: id, params: envelope.params)
                let workspace = workspaceForSession(request.sessionId ?? sessionID ?? UUID().uuidString)
                if workspace.allowEditsThisSession, isEditPermission(request),
                   let allow = request.options.first(where: { !$0.kind.contains("reject") }) {
                    respond(
                        id: id,
                        result: [
                            "outcome": [
                                "outcome": "selected",
                                "optionId": allow.id
                            ]
                        ]
                    )
                    return
                }
                if workspace.sessionAllowTitles.contains(request.title),
                   let allow = request.options.first(where: { !$0.kind.contains("reject") }) {
                    respond(
                        id: id,
                        result: [
                            "outcome": [
                                "outcome": "selected",
                                "optionId": allow.id
                            ]
                        ]
                    )
                    return
                }
                workspace.permission = request
                syncFromCurrent()
            }
            return
        }

        if envelope.method == "session/update" || envelope.method == "_x.ai/session/update" {
            apply(update: SessionUpdate.parse(params: envelope.params, envelopeTimestamp: envelope.timestamp))
            return
        }

        if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
            if let error = envelope.error {
                let message = error["message"] as? String ?? "RPC error"
                continuation.resume(throwing: ACPError.rpc(message))
            } else {
                continuation.resume(returning: envelope)
            }
        }
    }

    private func apply(update: SessionUpdate) {
        let id = update.sessionId ?? sessionID
        guard let id else { return }
        let workspace = workspaceForSession(id)
        workspace.fold(update)
        if workspace.stopRequested {
            workspace.markWorkStopped()
        }
        if update.kind == .turnCompleted {
            workspace.finishTurn(at: update.timestamp ?? Date())
        }
        if update.kind == .plan {
            workspace.refreshArtifacts()
        }
        syncFromCurrent()
    }

    private func workspaceForSession(_ id: String) -> SessionWorkspace {
        if let existing = workspaceByID[id] {
            return existing
        }
        let directory = SessionIndex().directory(cwd: workingDirectory.path, id: id)
        return ensureWorkspace(id: id, cwd: workingDirectory, directory: directory)
    }

    @discardableResult
    private func ensureWorkspace(id: String, cwd: URL, directory: URL?) -> SessionWorkspace {
        if let existing = workspaceByID[id] {
            if existing.directory == nil, let directory {
                existing.directory = directory
            }
            return existing
        }
        let workspace = SessionWorkspace(id: id, cwd: cwd, directory: directory)
        workspace.mode = mode
        workspaceByID[id] = workspace
        return workspace
    }

    private func rememberLoaded(_ id: String) {
        if !retainedSessionIDs.contains(id) {
            retainedSessionIDs.append(id)
        }
    }

    private func reloadRetainedSessions(focus: String?) async {
        let ids = retainedSessionIDs
        for id in ids {
            guard let workspace = workspaceByID[id] else { continue }
            do {
                try await loadSession(id: id, cwd: workspace.cwd, directory: workspace.directory)
            } catch {
                workspace.loadedOnAgent = false
            }
        }
        if let focus, workspaceByID[focus]?.loadedOnAgent == true {
            _ = focusIfLoaded(focus)
        }
    }

    private func syncFromCurrent() {
        if let workspace = currentWorkspace {
            if workspace.items != items {
                items = workspace.items
            }
            isTurnRunning = workspace.isTurnRunning
            permission = workspace.permission
            userQuestion = workspace.userQuestion
            lastError = workspace.lastError ?? lastError
            planEntries = workspace.planEntries
            planMarkdown = workspace.planMarkdown
            hunks = workspace.hunks
            promptQueue = workspace.promptQueue
            sessionDirectory = workspace.directory
            if pendingWorkingDirectory == nil {
                workingDirectory = workspace.cwd
            }
            mode = workspace.mode
            allowEditsThisSession = workspace.allowEditsThisSession
            itemDates = workspace.itemDates
            itemDurations = workspace.itemDurations
            itemImages = workspace.itemImages
            todos = workspace.todos
            tasks = workspace.tasks
            recap = workspace.recap
            compacted = workspace.compacted
            subagents = workspace.subagents
        }
        terminals = terminalsHost.snapshots
        refreshLive()
    }

    private func refreshLive() {
        liveWorkspaces = workspaceByID.values.filter(\.isLive).sorted { $0.id < $1.id }
    }

    private func present(questionID id: JSONRPCID, params: [String: Any]) {
        if let request = UserQuestionRequest.parse(id: id, params: params) {
            present(question: request)
            return
        }
        respond(id: id, result: UserQuestionOutcome.skipInterview.json)
        appendStderr("ask_user_question had no questions")
    }

    private func present(question: UserQuestionRequest) {
        let workspace = workspaceForSession(question.sessionId ?? sessionID ?? UUID().uuidString)
        if let existing = workspace.userQuestion, existing.rpcID != question.rpcID {
            respond(id: existing.rpcID, result: UserQuestionOutcome.skipInterview.json)
        }
        workspace.userQuestion = question
        if sessionID == nil {
            sessionID = workspace.id
            lastSessionID = workspace.id
        }
        syncFromCurrent()
    }

    private func isPlanPermission(_ request: PermissionRequest) -> Bool {
        let blob = (request.title + request.options.map(\.id).joined()).lowercased()
        return blob.contains("plan") || blob.contains("exit_plan")
    }

    private func appendStderr(_ text: String) {
        let parts = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        stderrLines.append(contentsOf: parts)
        if stderrLines.count > 200 {
            stderrLines.removeFirst(stderrLines.count - 200)
        }
    }

    private func recordEvent(inbound: Bool, method: String, params: [String: Any], extra: String = "") {
        let preview = DiagnosticExport.redact(ACPEvent.preview(method: method, params: params, extra: extra))
        events.append(ACPEvent(inbound: inbound, method: method, preview: preview))
        if events.count > 80 {
            events.removeFirst(events.count - 80)
        }
    }

    @discardableResult
    private func handleClientRequest(id: JSONRPCID, method: String, params: [String: Any]) -> Bool {
        switch method {
        case "fs/read_text_file", "fs/readTextFile":
            handleReadTextFile(id: id, params: params)
            return true
        case "fs/write_text_file", "fs/writeTextFile":
            handleWriteTextFile(id: id, params: params)
            return true
        case "terminal/create":
            handleTerminalCreate(id: id, params: params)
            return true
        case "terminal/output":
            handleTerminalOutput(id: id, params: params)
            return true
        case "terminal/wait_for_exit", "terminal/waitForExit":
            handleTerminalWait(id: id, params: params)
            return true
        case "terminal/kill":
            handleTerminalKill(id: id, params: params)
            return true
        case "terminal/release":
            handleTerminalRelease(id: id, params: params)
            return true
        default:
            return false
        }
    }

    private func handleReadTextFile(id: JSONRPCID, params: [String: Any]) {
        guard let path = params["path"] as? String, !path.isEmpty else {
            respondError(id: id, message: "Missing path")
            return
        }
        do {
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            let sliced = sliceFile(text, line: params["line"] as? Int, limit: params["limit"] as? Int)
            respond(id: id, result: ["content": sliced])
        } catch {
            respondError(id: id, message: error.localizedDescription)
        }
    }

    private func handleWriteTextFile(id: JSONRPCID, params: [String: Any]) {
        guard let path = params["path"] as? String, !path.isEmpty else {
            respondError(id: id, message: "Missing path")
            return
        }
        let content = params["content"] as? String ?? ""
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            respond(id: id, result: [:] as [String: Any])
        } catch {
            respondError(id: id, message: error.localizedDescription)
        }
    }

    private func handleTerminalCreate(id: JSONRPCID, params: [String: Any]) {
        let command = params["command"] as? String ?? ""
        let args = params["args"] as? [String] ?? []
        let cwdPath = params["cwd"] as? String
        let cwd = cwdPath.map(URL.init(fileURLWithPath:)) ?? currentWorkspace?.cwd ?? workingDirectory
        var env: [String: String] = [:]
        if let rows = params["env"] as? [[String: Any]] {
            for row in rows {
                if let name = row["name"] as? String, let value = row["value"] as? String {
                    env[name] = value
                }
            }
        } else if let dict = params["env"] as? [String: String] {
            env = dict
        }
        let limit = params["outputByteLimit"] as? Int ?? params["output_byte_limit"] as? Int ?? TerminalHost.defaultByteLimit
        do {
            let terminalID = try terminalsHost.create(
                command: command,
                args: args,
                cwd: cwd,
                env: env,
                outputByteLimit: limit
            )
            terminals = terminalsHost.snapshots
            respond(id: id, result: ["terminalId": terminalID])
        } catch {
            respondError(id: id, message: error.localizedDescription)
        }
    }

    private func handleTerminalOutput(id: JSONRPCID, params: [String: Any]) {
        guard let terminalID = params["terminalId"] as? String ?? params["terminal_id"] as? String,
              let output = terminalsHost.output(id: terminalID)
        else {
            respondError(id: id, message: "Unknown terminal")
            return
        }
        respond(id: id, result: output.json)
    }

    private func handleTerminalWait(id: JSONRPCID, params: [String: Any]) {
        guard let terminalID = params["terminalId"] as? String ?? params["terminal_id"] as? String else {
            respondError(id: id, message: "Missing terminalId")
            return
        }
        Task { @MainActor in
            let status = await terminalsHost.waitForExit(id: terminalID)
            var body: [String: Any] = [:]
            if let code = status.exitCode { body["exitCode"] = Int(code) }
            if let signal = status.signal { body["signal"] = signal }
            self.respond(id: id, result: body)
            self.terminals = self.terminalsHost.snapshots
        }
    }

    private func handleTerminalKill(id: JSONRPCID, params: [String: Any]) {
        guard let terminalID = params["terminalId"] as? String ?? params["terminal_id"] as? String else {
            respondError(id: id, message: "Missing terminalId")
            return
        }
        terminalsHost.kill(id: terminalID)
        terminals = terminalsHost.snapshots
        respond(id: id, result: [:] as [String: Any])
    }

    private func handleTerminalRelease(id: JSONRPCID, params: [String: Any]) {
        guard let terminalID = params["terminalId"] as? String ?? params["terminal_id"] as? String else {
            respondError(id: id, message: "Missing terminalId")
            return
        }
        terminalsHost.release(id: terminalID)
        terminals = terminalsHost.snapshots
        respond(id: id, result: [:] as [String: Any])
    }

    private func sliceFile(_ text: String, line: Int?, limit: Int?) -> String {
        guard line != nil || limit != nil else { return text }
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = max((line ?? 1) - 1, 0)
        let end = min(rows.count, start + max(limit ?? (rows.count - start), 0))
        guard start < rows.count else { return "" }
        return rows[start..<end].joined(separator: "\n")
    }

    private func respondError(id: JSONRPCID, message: String) {
        try? write(JSONRPCEnvelope(id: id, error: ["code": -32000, "message": message]))
    }

    @discardableResult
    private func request(method: String, params: [String: Any]) async throws -> JSONRPCEnvelope {
        let id = JSONRPCID.int(nextID)
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(JSONRPCEnvelope(id: id, method: method, params: params))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private static func isCancelError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("cancel") || text.contains("abort") || text.contains("interrupt")
    }

    private func fire(method: String, params: [String: Any]) {
        try? write(JSONRPCEnvelope(method: method, params: params))
    }

    private func respond(id: JSONRPCID, result: Any) {
        try? write(JSONRPCEnvelope(id: id, result: result))
    }

    private func write(_ envelope: JSONRPCEnvelope) throws {
        guard let stdinHandle else {
            scheduleReconnect()
            throw ACPError.rpc("Agent stdin is closed")
        }
        if let method = envelope.method {
            recordEvent(inbound: false, method: method, params: envelope.params)
        }
        var data = try envelope.encoded()
        data.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            scheduleReconnect()
            throw error
        }
    }

    private func firstString(_ value: Any?, keys: [String]) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        for key in keys {
            if let string = dict[key] as? String { return string }
        }
        return nil
    }

    static func pretty(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String { return text }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(4000))
        }
        return String(describing: value)
    }

    static func urls(from value: Any?) -> [URL] {
        var paths: [String] = []
        if let list = value as? [String] {
            paths = list
        } else if let dict = value as? [String: Any] {
            if let list = dict["entries"] as? [String] { paths = list }
            if let list = dict["files"] as? [String] { paths = list }
            if let list = dict["paths"] as? [String] { paths = list }
            if let entries = dict["entries"] as? [[String: Any]] {
                paths.append(contentsOf: entries.compactMap { $0["path"] as? String ?? $0["name"] as? String })
            }
        }
        return paths.compactMap { path in
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
            return nil
        }
    }

    public static func readVersion(locator: GrokBinaryLocator) -> String? {
        guard let grok = locator.locate() else { return nil }
        let process = Process()
        process.executableURL = grok
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
    }
}
