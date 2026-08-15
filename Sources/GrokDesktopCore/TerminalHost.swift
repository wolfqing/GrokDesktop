import Foundation

public struct TerminalSnapshot: Identifiable, Equatable, Sendable {
    public var id: String
    public var command: String
    public var running: Bool
    public var exitCode: Int32?
    public var truncated: Bool
    public var preview: String

    public init(
        id: String,
        command: String,
        running: Bool,
        exitCode: Int32? = nil,
        truncated: Bool = false,
        preview: String = ""
    ) {
        self.id = id
        self.command = command
        self.running = running
        self.exitCode = exitCode
        self.truncated = truncated
        self.preview = preview
    }
}

public struct TerminalOutput: Equatable, Sendable {
    public var output: String
    public var truncated: Bool
    public var exitCode: Int32?
    public var signal: String?

    public var json: [String: Any] {
        var body: [String: Any] = [
            "output": output,
            "truncated": truncated
        ]
        if exitCode != nil || signal != nil {
            var status: [String: Any] = [:]
            if let exitCode { status["exitCode"] = Int(exitCode) }
            if let signal { status["signal"] = signal }
            body["exitStatus"] = status
        }
        return body
    }
}

public final class TerminalHost: @unchecked Sendable {
    public static let defaultByteLimit = 1_048_576

    private struct Slot {
        var id: String
        var command: String
        var process: Process
        var output = Data()
        var outputByteLimit: Int
        var truncated = false
        var exitCode: Int32?
        var signal: String?
        var waiters: [CheckedContinuation<(exitCode: Int32?, signal: String?), Never>] = []
    }

    private var slots: [String: Slot] = [:]
    private let lock = NSLock()
    private var notifyScheduled = false
    public var onChange: (@Sendable () -> Void)?

    public init() {}

    public var snapshots: [TerminalSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return slots.values
            .map {
                TerminalSnapshot(
                    id: $0.id,
                    command: $0.command,
                    running: $0.process.isRunning,
                    exitCode: $0.exitCode,
                    truncated: $0.truncated,
                    preview: Self.tail(of: $0.output)
                )
            }
            .sorted { $0.id < $1.id }
    }

    public var runningCount: Int {
        snapshots.filter(\.running).count
    }

    @discardableResult
    public func create(
        command: String,
        args: [String] = [],
        cwd: URL? = nil,
        env: [String: String] = [:],
        outputByteLimit: Int = TerminalHost.defaultByteLimit
    ) throws -> String {
        let id = UUID().uuidString
        let process = Process()
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if args.isEmpty {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", trimmed]
        } else if trimmed.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: trimmed)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [trimmed] + args
        }
        if let cwd { process.currentDirectoryURL = cwd }
        if !env.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            process.environment = environment
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = Pipe()

        lock.lock()
        slots[id] = Slot(id: id, command: displayCommand(trimmed, args: args), process: process, outputByteLimit: max(outputByteLimit, 4_096))
        lock.unlock()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(id: id, chunk)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(id: id, chunk)
        }
        process.terminationHandler = { [weak self] proc in
            self?.finished(id: id, code: proc.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            lock.lock()
            slots[id] = nil
            lock.unlock()
            throw error
        }
        return id
    }

    public func output(id: String) -> TerminalOutput? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots[id] else { return nil }
        return TerminalOutput(
            output: String(data: slot.output, encoding: .utf8) ?? String(decoding: slot.output, as: UTF8.self),
            truncated: slot.truncated,
            exitCode: slot.exitCode,
            signal: slot.signal
        )
    }

    public func waitForExit(id: String) async -> (exitCode: Int32?, signal: String?) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(exitCode: Int32?, signal: String?), Never>) in
            lock.lock()
            guard var slot = slots[id] else {
                lock.unlock()
                continuation.resume(returning: (exitCode: nil, signal: nil))
                return
            }
            if slot.exitCode != nil || slot.signal != nil || !slot.process.isRunning {
                let result = (exitCode: slot.exitCode ?? slot.process.terminationStatus, signal: slot.signal)
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            slot.waiters.append(continuation)
            slots[id] = slot
            lock.unlock()
        }
    }

    public func kill(id: String) {
        lock.lock()
        let process = slots[id]?.process
        lock.unlock()
        process?.terminate()
    }

    public func release(id: String) {
        lock.lock()
        let slot = slots.removeValue(forKey: id)
        lock.unlock()
        if let process = slot?.process, process.isRunning {
            process.terminate()
        }
        if let waiters = slot?.waiters {
            for waiter in waiters {
                waiter.resume(returning: (exitCode: slot?.exitCode ?? 1, signal: slot?.signal ?? "killed"))
            }
        }
    }

    public func releaseAll() {
        lock.lock()
        let all = slots
        slots.removeAll()
        lock.unlock()
        for slot in all.values {
            if slot.process.isRunning { slot.process.terminate() }
            for waiter in slot.waiters {
                waiter.resume(returning: (exitCode: slot.exitCode, signal: slot.signal ?? "released"))
            }
        }
    }

    private func append(id: String, _ chunk: Data) {
        lock.lock()
        guard var slot = slots[id] else {
            lock.unlock()
            return
        }
        let remaining = slot.outputByteLimit - slot.output.count
        if remaining <= 0 {
            slot.truncated = true
        } else if chunk.count > remaining {
            slot.output.append(chunk.prefix(remaining))
            slot.truncated = true
        } else {
            slot.output.append(chunk)
        }
        slots[id] = slot
        lock.unlock()
        scheduleNotify()
    }

    private func finished(id: String, code: Int32) {
        lock.lock()
        guard var slot = slots[id] else {
            lock.unlock()
            return
        }
        slot.exitCode = code
        let waiters = slot.waiters
        slot.waiters.removeAll()
        slots[id] = slot
        lock.unlock()
        for waiter in waiters {
            waiter.resume(returning: (exitCode: code, signal: nil))
        }
        scheduleNotify(force: true)
    }

    private func scheduleNotify(force: Bool = false) {
        if force {
            onChange?()
            return
        }
        lock.lock()
        if notifyScheduled {
            lock.unlock()
            return
        }
        notifyScheduled = true
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.notifyScheduled = false
            self.lock.unlock()
            self.onChange?()
        }
    }

    public static func tail(of data: Data, lines: Int = 8) -> String {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        return rows.suffix(lines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayCommand(_ command: String, args: [String]) -> String {
        ([command] + args).joined(separator: " ")
    }
}
