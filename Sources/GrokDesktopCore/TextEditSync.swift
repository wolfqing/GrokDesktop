import Foundation

public struct TextEditStamp: Equatable, Sendable {
    public var text: String
    public var modified: Date

    public init(text: String, modified: Date) {
        self.text = text
        self.modified = modified
    }
}

public enum TextEditSync {
    public static func read(_ url: URL) -> TextEditStamp? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return TextEditStamp(text: text, modified: date)
    }

    /// A newer file on disk replaces the editor buffer, including an agent write.
    public static func reload(editor: TextEditStamp, url: URL) -> TextEditStamp {
        guard let disk = read(url) else { return editor }
        if disk.modified > editor.modified { return disk }
        if disk.text != editor.text, disk.modified >= editor.modified { return disk }
        return editor
    }

    public static func save(_ text: String, url: URL) throws -> TextEditStamp {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return read(url) ?? TextEditStamp(text: text, modified: Date())
    }
}
