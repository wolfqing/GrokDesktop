import Foundation

public enum ACPConnectionState: Equatable, Sendable {
    case idle
    case connecting
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
    @Published public private(set) var permission: PermissionRequest?
    @Published public private(set) var lastError: String?
    @Published public var workingDirectory: URL
    @Published public var modelTier: ModelTier = .expert
    @Published public var buildModel: BuildModel = .grokBuild
    @Published public var effort: EffortLevel = .xhigh
    @Published public var mode: AgentMode = .normal

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

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var nextID = 1
    private var pending: [JSONRPCID: CheckedContinuation<JSONRPCEnvelope, Error>] = [:]
    private var stdoutBuffer = Data()
    private var assistantBufferID: String?
    private var thoughtBufferID: String?

    public init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.locator = locator
        self.workingDirectory = workingDirectory
    }

    public var grokURL: URL? { locator.locate() }

    public func connectIfNeeded() async throws {
        if state == .ready, process?.isRunning == true { return }
        try await start()
    }

    public func start() async throws {
        stop()
        guard let grok = locator.locate() else {
            state = .failed(ACPError.grokNotFound.localizedDescription)
            throw ACPError.grokNotFound
        }

        state = .connecting
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
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(code: proc.terminationStatus)
            }
        }

        try process.run()
        self.process = process

        _ = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientInfo": [
                    "name": "GrokDesktop",
                    "version": "0.1.0"
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
        state = .ready
    }

    public func newSession(cwd: URL? = nil) async throws {
        try await connectIfNeeded()
        if let cwd {
            workingDirectory = cwd
        }
        var meta: [String: Any] = [:]
        if mode == .alwaysApprove {
            meta["yoloMode"] = true
        }
        let result = try await request(
            method: "session/new",
            params: [
                "cwd": workingDirectory.path,
                "mcpServers": [],
                "_meta": meta
            ]
        )
        sessionID = firstString(result.result, keys: ["sessionId", "session_id"])
        items = []
        assistantBufferID = nil
        thoughtBufferID = nil
        permission = nil
    }

    public func loadSession(id: String, cwd: URL) async throws {
        try await connectIfNeeded()
        workingDirectory = cwd
        _ = try await request(
            method: "session/load",
            params: [
                "sessionId": id,
                "cwd": cwd.path
            ]
        )
        sessionID = id
        items = [
            .notice(id: UUID().uuidString, text: "Resumed session. New messages continue from here.")
        ]
        assistantBufferID = nil
        thoughtBufferID = nil
    }

    public func send(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await connectIfNeeded()
        if sessionID == nil {
            try await newSession()
        }
        guard let sessionID else {
            throw ACPError.rpc("No session")
        }

        items.append(.user(id: UUID().uuidString, text: trimmed))
        isTurnRunning = true
        assistantBufferID = nil
        thoughtBufferID = nil

        var params: [String: Any] = [
            "sessionId": sessionID,
            "prompt": [["type": "text", "text": trimmed]],
            "model": buildModel.rawValue
        ]
        params["_meta"] = [
            "effort": effort.rawValue,
            "yoloMode": mode == .alwaysApprove
        ]
        do {
            _ = try await request(method: "session/prompt", params: params)
        } catch {
            lastError = error.localizedDescription
            items.append(.notice(id: UUID().uuidString, text: error.localizedDescription))
        }
        isTurnRunning = false
    }

    public func cancelTurn() {
        guard let sessionID else { return }
        fire(method: "session/cancel", params: ["sessionId": sessionID])
        isTurnRunning = false
    }

    public func answerPermission(optionID: String) {
        guard let permission else { return }
        respond(
            id: permission.id,
            result: [
                "outcome": [
                    "outcome": "selected",
                    "optionId": optionID
                ]
            ]
        )
        self.permission = nil
    }

    public func rejectPermission() {
        guard let permission else { return }
        if let cancel = permission.options.first(where: { $0.kind.contains("reject") || $0.id.contains("cancel") }) {
            answerPermission(optionID: cancel.id)
            return
        }
        respond(id: permission.id, result: ["outcome": ["outcome": "cancelled"]])
        self.permission = nil
    }

    public func resetConversation() {
        items = []
        sessionID = nil
        permission = nil
        assistantBufferID = nil
        thoughtBufferID = nil
        isTurnRunning = false
    }

    public func stop() {
        stdinHandle = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        for (_, continuation) in pending {
            continuation.resume(throwing: ACPError.processExited(1))
        }
        pending.removeAll()
        state = .idle
        sessionID = nil
        isTurnRunning = false
    }

    private func handleTermination(code: Int32) {
        for (_, continuation) in pending {
            continuation.resume(throwing: ACPError.processExited(code))
        }
        pending.removeAll()
        if state == .ready || state == .connecting {
            state = .failed(ACPError.processExited(code).localizedDescription)
        }
        isTurnRunning = false
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
        guard let envelope = try? JSONRPCEnvelope.decode(line) else { return }

        if let method = envelope.method, envelope.id != nil, method == "session/request_permission" {
            if let id = envelope.id {
                permission = PermissionRequest.parse(id: id, params: envelope.params)
            }
            return
        }

        if envelope.method == "session/update" {
            apply(update: SessionUpdate.parse(params: envelope.params))
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
        switch update.kind {
        case .agentMessageChunk:
            appendStreaming(kind: .assistant, text: update.text)
        case .agentThoughtChunk:
            appendStreaming(kind: .thought, text: update.text)
        case .toolCall, .toolCallUpdate:
            let id = update.toolCallId ?? UUID().uuidString
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = .tool(
                    id: id,
                    title: update.title.isEmpty ? toolTitle(items[index]) : update.title,
                    status: update.status ?? "running",
                    detail: update.text
                )
            } else {
                items.append(.tool(
                    id: id,
                    title: update.title.isEmpty ? "Tool" : update.title,
                    status: update.status ?? "running",
                    detail: update.text
                ))
            }
        case .plan:
            items.append(.notice(id: UUID().uuidString, text: "Plan updated."))
        case .unknown:
            break
        }
    }

    private func toolTitle(_ item: ConversationItem) -> String {
        if case .tool(_, let title, _, _) = item { return title }
        return "Tool"
    }

    private enum StreamKind { case assistant, thought }

    private func appendStreaming(kind: StreamKind, text: String) {
        switch kind {
        case .assistant:
            if let id = assistantBufferID, let index = items.firstIndex(where: { $0.id == id }),
               case .assistant(_, let existing, _) = items[index] {
                items[index] = .assistant(id: id, text: existing + text, done: false)
            } else {
                let id = UUID().uuidString
                assistantBufferID = id
                items.append(.assistant(id: id, text: text, done: false))
            }
        case .thought:
            if let id = thoughtBufferID, let index = items.firstIndex(where: { $0.id == id }),
               case .thought(_, let existing) = items[index] {
                items[index] = .thought(id: id, text: existing + text)
            } else {
                let id = UUID().uuidString
                thoughtBufferID = id
                items.append(.thought(id: id, text: text))
            }
        }
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

    private func fire(method: String, params: [String: Any]) {
        try? write(JSONRPCEnvelope(method: method, params: params))
    }

    private func respond(id: JSONRPCID, result: Any) {
        try? write(JSONRPCEnvelope(id: id, result: result))
    }

    private func write(_ envelope: JSONRPCEnvelope) throws {
        guard let stdinHandle else {
            throw ACPError.rpc("Agent stdin is closed")
        }
        var data = try envelope.encoded()
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)
    }

    private func firstString(_ value: Any?, keys: [String]) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        for key in keys {
            if let string = dict[key] as? String { return string }
        }
        return nil
    }
}
