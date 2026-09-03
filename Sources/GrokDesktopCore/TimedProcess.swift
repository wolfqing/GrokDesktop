import Foundation

/// Runs a short-lived subprocess with a hard timeout so UI never blocks on git.
public enum TimedProcess {
    public static func run(
        executable: URL = URL(fileURLWithPath: "/usr/bin/git"),
        arguments: [String],
        cwd: URL,
        timeout: TimeInterval = 4,
        limitBytes: Int? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process)
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        var data = output.fileHandleForReading.readDataToEndOfFile()
        if let limitBytes, data.count > limitBytes {
            data = data.prefix(limitBytes)
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    public static func git(
        cwd: URL,
        _ args: [String],
        timeout: TimeInterval = 4,
        limitBytes: Int? = nil
    ) -> String? {
        run(
            arguments: ["-C", cwd.path] + args,
            cwd: cwd,
            timeout: timeout,
            limitBytes: limitBytes
        )
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.4)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

public struct ProcessCapture: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(status: Int32 = 1, stdout: String = "", stderr: String = "", timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var text: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var ok: Bool { !timedOut && status == 0 }
}

public extension TimedProcess {
    static func capture(
        executable: URL,
        arguments: [String],
        cwd: URL,
        timeout: TimeInterval = 8,
        limitBytes: Int = 1_000_000
    ) -> ProcessCapture {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let output = Pipe()
        let err = Pipe()
        process.standardOutput = output
        process.standardError = err
        do {
            try process.run()
        } catch {
            return ProcessCapture(status: 1, stderr: error.localizedDescription)
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process)
            return ProcessCapture(
                status: process.terminationStatus,
                stdout: readLimited(output, limitBytes: limitBytes),
                stderr: readLimited(err, limitBytes: limitBytes),
                timedOut: true
            )
        }
        return ProcessCapture(
            status: process.terminationStatus,
            stdout: readLimited(output, limitBytes: limitBytes),
            stderr: readLimited(err, limitBytes: limitBytes)
        )
    }

    private static func readLimited(_ pipe: Pipe, limitBytes: Int) -> String {
        var data = pipe.fileHandleForReading.readDataToEndOfFile()
        if data.count > limitBytes {
            data = data.prefix(limitBytes)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
