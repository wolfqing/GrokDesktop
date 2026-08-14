import Foundation

public struct DetectedChatLink: Equatable, Sendable {
    public var range: NSRange
    public var url: URL
    public var kind: Kind

    public enum Kind: String, Sendable, Equatable {
        case web
        case file
        case directory
        case mail
    }

    public init(range: NSRange, url: URL, kind: Kind) {
        self.range = range
        self.url = url
        self.kind = kind
    }

    public var isFile: Bool { kind == .file || kind == .directory }
}

public enum ChatLinkDetector {
    private static let ignoredNames: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "ok.", "ex."
    ]

    private static let absoluteRoots: Set<String> = [
        "Users", "Volumes", "private", "tmp", "var", "opt", "usr", "bin", "sbin",
        "etc", "home", "Library", "System", "Applications", "dev", "cores", "opt"
    ]

    public static func likelyContainsLinks(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.contains("http")
            || text.contains("www.")
            || text.contains("://")
            || text.contains("](")
            || text.contains("~/")
            || text.contains("@/")
            || text.contains("mailto:")
            || text.contains("/Users/")
            || text.contains("/tmp/")
            || text.contains("/var/")
            || text.contains("/opt/")
            || (text.contains("/") && text.contains("."))
    }

    public static func detect(
        in text: String,
        baseDirectory: URL? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [DetectedChatLink] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var candidates: [(NSRange, String)] = []

        func collect(_ pattern: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard range.location != NSNotFound, range.length > 1 else { continue }
                candidates.append((range, ns.substring(with: range)))
            }
        }

        collect(#"(?i)\b((?:https?|file|mailto):[^\s<>\[\]\"'`]+)"#)
        collect(#"(?i)\b((?:www\.)[a-z0-9.-]+\.[a-z]{2,}[^\s<>\[\]\"'`]*)"#)
        collect(#"(?i)\b([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})\b"#)
        collect(#"(@?(?:~|/(?:Users|Volumes|private|tmp|var|opt|usr|bin|sbin|etc|home|Library|System|Applications|dev|cores))[^\s<>\[\]\"'`]+)"#)
        collect(#"(@?/(?:[^\s<>\[\]\"'`]*/)+[^\s<>\[\]\"'`]+)"#)
        collect(#"\b((?:[\w.+-]+/)+\.?[\w.+-]+\.[A-Za-z][A-Za-z0-9]{0,9})\b"#)
        collect(#"\b([\w.+-]+\.[A-Za-z][A-Za-z0-9]{0,9})\b"#)

        candidates.sort {
            if $0.0.location != $1.0.location { return $0.0.location < $1.0.location }
            return $0.0.length > $1.0.length
        }

        var used = IndexSet()
        var result: [DetectedChatLink] = []
        for (range, raw) in candidates {
            let indices = IndexSet(integersIn: range.location..<(range.location + range.length))
            if used.intersects(integersIn: range.location..<(range.location + range.length)) {
                continue
            }
            guard let resolved = resolve(raw, baseDirectory: baseDirectory, fileExists: fileExists) else {
                continue
            }
            used.formUnion(indices)
            result.append(DetectedChatLink(range: range, url: resolved.url, kind: resolved.kind))
        }
        return result
    }

    public static func resolve(
        _ raw: String,
        baseDirectory: URL? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> (url: URL, kind: DetectedChatLink.Kind)? {
        var value = trim(raw)
        guard !value.isEmpty, value != "/" else { return nil }
        if ignoredNames.contains(value.lowercased()) { return nil }

        if value.hasPrefix("mailto:") {
            return URL(string: value).map { ($0, .mail) }
        }
        if value.contains("@"), !value.contains("/"), !value.contains("://"),
           value.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return URL(string: "mailto:\(value)").map { ($0, .mail) }
        }
        if value.lowercased().hasPrefix("www.") {
            value = "https://\(value)"
        }
        if let scheme = scheme(of: value) {
            if scheme == "file" {
                guard let url = URL(string: value) ?? URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? value) else {
                    return nil
                }
                return (url, directoryHint(url.path, fileExists: fileExists))
            }
            if scheme == "http" || scheme == "https" {
                return URL(string: value).map { ($0, .web) }
            }
            return URL(string: value).map { ($0, .web) }
        }

        if isVersionToken(value) { return nil }
        if isSlashCommand(value) { return nil }

        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if value.hasPrefix("~/") || value == "~" {
            value = (value as NSString).expandingTildeInPath
        }

        if value.hasPrefix("/") {
            if !shouldTrustAbsolute(value), !fileExists(value) {
                return nil
            }
            let url = URL(fileURLWithPath: value)
            return (url, directoryHint(url.path, fileExists: fileExists))
        }

        guard let baseDirectory else {
            if value.contains("/") {
                let url = URL(fileURLWithPath: value)
                return (url, .file)
            }
            return nil
        }
        let relative = baseDirectory.appendingPathComponent(value)
        if fileExists(relative.path) {
            return (relative, directoryHint(relative.path, fileExists: fileExists))
        }
        if value.contains("/") {
            return (relative, .file)
        }
        return nil
    }

    private static func trim(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<"), value.hasSuffix(">") {
            value = String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("`"), value.hasSuffix("`") {
            value = String(value.dropFirst().dropLast())
        }
        let closers: [Character] = [")", "]", "}", ">", "\"", "'", "`", ",", ".", ";", ":", "!", "?", "、", "。", "）", "」"]
        while let last = value.last, closers.contains(last) {
            if last == ")" {
                let opens = value.filter { $0 == "(" }.count
                let closes = value.filter { $0 == ")" }.count
                if opens >= closes { break }
            }
            value.removeLast()
        }
        return value
    }

    private static func scheme(of value: String) -> String? {
        guard let range = value.range(of: "://") ?? value.range(of: ":") else { return nil }
        let scheme = String(value[..<range.lowerBound]).lowercased()
        guard scheme.count >= 2, scheme.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        if scheme == "mailto" { return scheme }
        if value[range].starts(with: "://") { return scheme }
        return nil
    }

    private static func shouldTrustAbsolute(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first else { return false }
        if absoluteRoots.contains(String(first)) { return true }
        return parts.count >= 2 && path.contains(".")
    }

    private static func isSlashCommand(_ value: String) -> Bool {
        guard value.hasPrefix("/"), !value.dropFirst().contains("/") else { return false }
        let name = String(value.split(separator: " ").first ?? Substring(value))
        return SlashBuiltins.handles(name)
    }

    private static func isVersionToken(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.count <= 4 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func directoryHint(_ path: String, fileExists: (String) -> Bool) -> DetectedChatLink.Kind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue ? .directory : .file
        }
        if fileExists(path), path.hasSuffix("/") { return .directory }
        return .file
    }
}
