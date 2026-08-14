import Foundation

public struct ImagineAsset: Identifiable, Hashable, Sendable {
    public var url: URL
    public var modified: Date
    public var sessionTitle: String

    public var id: String { url.path }

    public init(url: URL, modified: Date, sessionTitle: String = "") {
        self.url = url
        self.modified = modified
        self.sessionTitle = sessionTitle
    }
}

public enum ImagineLibrary {
    public static func recent(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions"),
        fileManager: FileManager = .default,
        limit: Int = 24
    ) -> [ImagineAsset] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var assets: [ImagineAsset] = []
        for case let url as URL in enumerator {
            let folder = url.deletingLastPathComponent().lastPathComponent.lowercased()
            guard folder == "images" || folder == "assets" else { continue }
            guard PromptMedia.isImageURL(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if values?.isRegularFile == false { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            let sessionTitle = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            assets.append(ImagineAsset(url: url, modified: modified, sessionTitle: sessionTitle))
        }

        return assets
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }
}
