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
