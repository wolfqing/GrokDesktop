import Foundation

public struct SSHHost: Equatable, Sendable, Identifiable {
    public var id: String { alias }
    public var alias: String
    public var hostName: String

    public init(alias: String, hostName: String = "") {
        self.alias = alias
        self.hostName = hostName
    }
}

public enum SSHWorkspace {
    /// The host alias is its own argv element. The remote command is not interpolated into that element.
    public static func argv(host: String, remoteCommand: [String]) -> [String] {
        var args = ["ssh", host]
        if !remoteCommand.isEmpty {
            args.append(remoteCommand.joined(separator: " "))
        }
        return args
    }

    public static func agentArgv(host: String) -> [String] {
        argv(host: host, remoteCommand: ["grok", "agent", "stdio"])
    }

    /// A remote path is never turned into a local cwd.
    public static func localCwd(remotePath: String) -> URL? {
        _ = remotePath
        return nil
    }

    public static func relative(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") { return nil }
        if trimmed.contains(where: { $0.isWhitespace || "'\"\\;|&$`".contains($0) }) { return nil }
        let parts = trimmed.split(separator: "/")
        if parts.contains("..") || parts.contains(".") { return nil }
        return trimmed
    }

    /// A host alias only. A path, a space, or `host:path` is refused.
    public static func sessionHost(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || host.contains("/") || host.contains(":") || host.contains(where: \.isWhitespace) { return nil }
        return host
    }

    public static func testArgv(host: String) -> [String]? {
        guard let host = sessionHost(host) else { return nil }
        return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, "true"]
    }

    public static func watchArgv(host: String) -> [String]? {
        guard let host = sessionHost(host) else { return nil }
        return ["ssh", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15", "-N", host]
    }

    /// Arguments for `/usr/bin/ssh`. BatchMode keeps a missing host from waiting on a password.
    public static func agentArguments(_ host: String) -> [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=2", host, "grok agent --no-leader stdio"]
    }

    public static func remoteReadArgv(host: String, relativePath: String) -> [String]? {
        guard let host = sessionHost(host), let path = relative(relativePath) else { return nil }
        return ["ssh", host, "cat -- \(path)"]
    }

    public static func remoteWriteArgv(host: String, relativePath: String) -> [String]? {
        guard let host = sessionHost(host), let path = relative(relativePath) else { return nil }
        return ["ssh", host, "cat > \(path)"]
    }

    public static func terminalArguments(host: String) -> [String]? {
        guard let host = sessionHost(host) else { return nil }
        return ["-t", host]
    }

    public static func skillsArgv(host: String) -> [String]? {
        guard let host = sessionHost(host) else { return nil }
        return ["ssh", host, "grok skills list"]
    }

    public static func forwardArgv(host: String, localPort: Int, remotePort: Int) -> [String]? {
        guard let host = sessionHost(host), (1...65535).contains(localPort), (1...65535).contains(remotePort) else { return nil }
        return ["ssh", "-N", "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)", host]
    }

    public static func hosts(configText: String) -> [SSHHost] {
        var result: [SSHHost] = []
        var alias = ""
        var hostName = ""
        func flush() {
            let name = alias.trimmingCharacters(in: .whitespaces)
            defer {
                alias = ""
                hostName = ""
            }
            guard !name.isEmpty else { return }
            for part in name.split(separator: " ") {
                let token = String(part)
                if token.hasPrefix("!") || token.contains("*") || token.contains("?") { continue }
                result.append(SSHHost(alias: token, hostName: hostName))
            }
        }
        for line in configText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("host ") {
                flush()
                alias = String(trimmed.dropFirst(5))
            } else if lower.hasPrefix("hostname ") {
                hostName = String(trimmed.dropFirst("hostname ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return result
    }

    public static func loadHosts(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    ) -> [SSHHost] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
        return hosts(configText: text)
    }
}
