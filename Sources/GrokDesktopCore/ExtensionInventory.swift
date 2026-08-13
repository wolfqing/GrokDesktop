import Foundation

public struct ExtensionInventory: Sendable, Equatable {
    public var mcp: [String]
    public var plugins: [String]
    public var hooks: [String]

    public init(mcp: [String] = [], plugins: [String] = [], hooks: [String] = []) {
        self.mcp = mcp
        self.plugins = plugins
        self.hooks = hooks
    }

    public static func load(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok"),
        mcpNames: [String] = []
    ) -> ExtensionInventory {
        ExtensionInventory(
            mcp: mcpNames,
            plugins: names(in: home.appendingPathComponent("plugins"))
                + names(in: home.appendingPathComponent("bundled")),
            hooks: names(in: home.appendingPathComponent("hooks"))
        )
    }

    private static func names(in directory: URL) -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return urls
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    || url.pathExtension == "json"
            }
            .map(\.lastPathComponent)
            .sorted()
    }
}

public enum DiagnosticExport {
    public static func make(
        version: String,
        grokVersion: String?,
        state: String,
        lastError: String?,
        sessionID: String?,
        cwd: String,
        stderr: [String]
    ) -> String {
        var lines = [
            "Grok Desktop diagnostic",
            "app: \(version)",
            "grok: \(grokVersion ?? "unknown")",
            "state: \(state)",
            "session: \(sessionID ?? "none")",
            "cwd: \(redact(cwd))",
            "error: \(redact(lastError ?? "none"))",
            "",
            "stderr:"
        ]
        lines.append(contentsOf: stderr.suffix(80).map(redact))
        return lines.joined(separator: "\n")
    }

    public static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"xai-[A-Za-z0-9_\-]+"#,
            #"(?i)(authorization|api[_-]?key|token|refresh_token)["']?\s*[:=]\s*["']?[^\s"']+"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
            }
        }
        return result
    }
}
