import Foundation

public enum FilePreviewKind: String, Sendable, Equatable {
    case markdown
    case html
    case image
    case text
    case binary
    case directory
    case missing
}

public struct FilePreviewDocument: Equatable, Sendable {
    public var url: URL
    public var kind: FilePreviewKind
    public var text: String
    public var truncated: Bool
    public var byteCount: Int
    public var exists: Bool

    public init(
        url: URL,
        kind: FilePreviewKind,
        text: String = "",
        truncated: Bool = false,
        byteCount: Int = 0,
        exists: Bool = true
    ) {
        self.url = url
        self.kind = kind
        self.text = text
        self.truncated = truncated
        self.byteCount = byteCount
        self.exists = exists
    }

    public var name: String { url.lastPathComponent }
    public var canRender: Bool {
        exists && (kind == .markdown || kind == .html || kind == .image || kind == .text)
    }
}

public enum FilePreview {
    public static let textLimit = 400_000

    public static func kind(for url: URL) -> FilePreviewKind {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue { return .directory }
        if let classified = classify(extension: url.pathExtension) {
            return classified
        }
        if !exists { return .missing }
        return looksLikeText(url) ? .text : .binary
    }

    public static func load(_ url: URL, limit: Int = FilePreview.textLimit) -> FilePreviewDocument {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let kind = kind(for: url)
        guard exists else {
            return FilePreviewDocument(url: url, kind: kind == .directory ? .missing : kind, exists: false)
        }
        if isDir.boolValue {
            return FilePreviewDocument(url: url, kind: .directory, exists: true)
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        switch kind {
        case .markdown, .html, .text:
            let loaded = readText(url, limit: limit)
            return FilePreviewDocument(
                url: url,
                kind: kind,
                text: loaded.text,
                truncated: loaded.truncated,
                byteCount: bytes,
                exists: true
            )
        default:
            return FilePreviewDocument(url: url, kind: kind, byteCount: bytes, exists: true)
        }
    }

    public static func classify(extension raw: String) -> FilePreviewKind? {
        switch raw.lowercased() {
        case "md", "markdown", "mdown", "mdx":
            return .markdown
        case "html", "htm":
            return .html
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico":
            return .image
        case "svg":
            return .image
        case "swift", "txt", "text", "json", "jsonl", "toml", "yml", "yaml", "xml",
             "plist", "sh", "zsh", "bash", "py", "rb", "rs", "go", "ts", "tsx", "js",
             "jsx", "css", "scss", "c", "h", "hh", "hpp", "cpp", "cc", "m", "mm",
             "java", "kt", "kts", "sql", "graphql", "rhai", "log", "conf", "ini",
             "env", "csv", "tsv", "gitignore", "dockerignore", "editorconfig",
             "makefile", "cmake", "gradle", "properties", "mod", "sum", "lock",
             "dockerfile", "r", "lua", "php", "ex", "exs", "erl", "hs", "clj",
             "proto", "tf", "hcl", "nix", "vim", "diff", "patch":
            return .text
        default:
            return nil
        }
    }

    private static func looksLikeText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let sample = handle.readData(ofLength: 512)
        if sample.isEmpty { return true }
        if sample.contains(0) { return false }
        return String(data: sample, encoding: .utf8) != nil
    }

    private static func readText(_ url: URL, limit: Int) -> (text: String, truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ("", false)
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limit + 1)
        let truncated = data.count > limit
        let slice = truncated ? data.prefix(limit) : data
        let text = String(data: slice, encoding: .utf8)
            ?? String(decoding: slice, as: UTF8.self)
        return (text, truncated)
    }
}
