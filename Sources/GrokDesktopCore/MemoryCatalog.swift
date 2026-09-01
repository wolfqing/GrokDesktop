import Foundation

public struct MemoryFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var title: String
    public var scope: String
    public var modifiedAt: Date?

    public init(url: URL, title: String, scope: String, modifiedAt: Date? = nil) {
        self.url = url
        self.title = title
        self.scope = scope
        self.modifiedAt = modifiedAt
    }
}

public enum MemoryCatalog {
    public static func load(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/memory"),
        fileManager: FileManager = .default
    ) -> [MemoryFile] {
        var files: [MemoryFile] = []
        let global = home.appendingPathComponent("MEMORY.md")
        if fileManager.fileExists(atPath: global.path) {
            files.append(make(global, title: "MEMORY.md", scope: "global", fileManager: fileManager))
        }
        guard let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let workspace = child.appendingPathComponent("MEMORY.md")
            if fileManager.fileExists(atPath: workspace.path) {
                files.append(make(workspace, title: child.lastPathComponent, scope: "workspace", fileManager: fileManager))
            }
            let sessions = child.appendingPathComponent("sessions", isDirectory: true)
            if let logs = try? fileManager.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                for log in logs where log.pathExtension.lowercased() == "md" {
                    files.append(make(
                        log,
                        title: "\(child.lastPathComponent)/\(log.lastPathComponent)",
                        scope: "session",
                        fileManager: fileManager
                    ))
                }
            }
        }
        return files
    }

    public static func preview(_ file: MemoryFile, limit: Int = 4_000) -> String {
        let text = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "\n…"
    }

    private static func make(_ url: URL, title: String, scope: String, fileManager: FileManager) -> MemoryFile {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return MemoryFile(url: url, title: title, scope: scope, modifiedAt: modified)
    }
}
