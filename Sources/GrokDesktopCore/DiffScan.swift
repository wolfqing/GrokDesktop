import Foundation

public struct DiffFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var lines: [DiffLine]

    public init(path: String, lines: [DiffLine] = []) {
        self.path = path
        self.lines = lines
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    public var added: Int { lines.filter { $0.kind == .added }.count }

    public var removed: Int { lines.filter { $0.kind == .removed }.count }
}

public struct DiffLine: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case added
        case removed
        case header
        case meta
        case context
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum DiffScan {
    public static func parse(_ raw: String, limit: Int = 400) -> [DiffFile] {
        let text = extractPatch(raw)
        guard !text.isEmpty else { return [] }
        var files: [DiffFile] = []
        var current: DiffFile?
        func flush() {
            if let current, !current.path.isEmpty {
                files.append(current)
            }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            if rawLine.hasPrefix("diff --git ") {
                flush()
                let path = TranscriptLoader.parseDiffFiles(rawLine).first ?? fallbackPath(rawLine)
                current = DiffFile(path: path)
                current?.lines.append(DiffLine(kind: .meta, text: rawLine))
                continue
            }
            if rawLine.hasPrefix("+++ ") {
                let path = stripDiffPrefix(String(rawLine.dropFirst(4)))
                if current == nil || current?.path == "/dev/null" || (current?.path.isEmpty ?? true) {
                    current = DiffFile(path: path)
                } else if path != "/dev/null", !path.isEmpty {
                    current?.path = path
                }
                current?.lines.append(DiffLine(kind: .meta, text: rawLine))
                continue
            }
            if current == nil, rawLine.hasPrefix("--- ") {
                current = DiffFile(path: stripDiffPrefix(String(rawLine.dropFirst(4))))
                current?.lines.append(DiffLine(kind: .meta, text: rawLine))
                continue
            }
            guard current != nil else { continue }
            if current!.lines.count >= limit {
                continue
            }
            if rawLine.hasPrefix("@@") {
                current?.lines.append(DiffLine(kind: .header, text: rawLine))
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                current?.lines.append(DiffLine(kind: .added, text: rawLine))
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                current?.lines.append(DiffLine(kind: .removed, text: rawLine))
            } else if rawLine.hasPrefix("index ") || rawLine.hasPrefix("new file") || rawLine.hasPrefix("deleted file") || rawLine.hasPrefix("--- ") {
                current?.lines.append(DiffLine(kind: .meta, text: rawLine))
            } else {
                current?.lines.append(DiffLine(kind: .context, text: rawLine))
            }
        }
        flush()
        return files
    }

    public static func extractPatch(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("diff --git ") || trimmed.contains("\ndiff --git ") {
            return trimmed
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                let extracted = extractPatch(from: object)
                if !extracted.isEmpty { return extracted }
            }
        }
        return trimmed
    }

    public static func extractPatch(from value: Any?) -> String {
        if let text = value as? String {
            return extractPatch(text)
        }
        if let rows = value as? [Any] {
            return rows.map(extractPatch(from:)).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard let dict = value as? [String: Any] else { return "" }
        for key in ["diff", "patch", "text", "unified", "content"] {
            if let text = dict[key] as? String, text.contains("diff --git") || text.contains("\n+") {
                return text
            }
        }
        if let files = dict["files"] as? [Any] {
            return extractPatch(from: files)
        }
        if let files = dict["diffs"] as? [Any] {
            return extractPatch(from: files)
        }
        return ""
    }

    public static func workspaceDiff(cwd: URL, limitBytes: Int = 80_000) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd.path, "diff", "--no-color", "HEAD"]
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let slice = data.count > limitBytes ? data.prefix(limitBytes) : data
        return String(data: slice, encoding: .utf8) ?? ""
    }

    private static func stripDiffPrefix(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if let tab = value.firstIndex(of: "\t") {
            value = String(value[..<tab])
        }
        if value.hasPrefix("a/") || value.hasPrefix("b/") {
            value = String(value.dropFirst(2))
        }
        return value
    }

    private static func fallbackPath(_ line: String) -> String {
        let parts = line.split(separator: " ")
        if let last = parts.last {
            var path = String(last)
            if path.hasPrefix("b/") { path = String(path.dropFirst(2)) }
            return path
        }
        return "diff"
    }
}
