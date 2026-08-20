import CoreGraphics
import Foundation
import ImageIO

public struct ImagineAsset: Identifiable, Hashable, Sendable {
    public var url: URL
    public var modified: Date
    public var sessionTitle: String
    public var pixelSize: CGSize

    public var id: String { url.path }

    public var aspectRatio: CGFloat {
        guard pixelSize.width > 1, pixelSize.height > 1 else { return 1 }
        return pixelSize.width / pixelSize.height
    }

    public init(url: URL, modified: Date, sessionTitle: String = "", pixelSize: CGSize = .zero) {
        self.url = url
        self.modified = modified
        self.sessionTitle = sessionTitle
        self.pixelSize = pixelSize
    }
}

public enum ImaginePrompt {
    public static func make(
        text: String,
        video: Bool,
        aspect: String = "auto",
        reference: URL? = nil,
        count: Int = 1,
        mode: String = "auto"
    ) -> String {
        let command = video ? "/imagine-video" : "/imagine"
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = body.isEmpty ? command : "\(command) \(body)"
        var notes: [String] = []
        if aspect != "auto", !aspect.isEmpty {
            notes.append("Set image_gen aspect_ratio to \(aspect).")
        }
        let n = min(max(count, 1), 4)
        if !video, n > 1 {
            notes.append("Make \(n) distinct variations as separate image_gen calls.")
        }
        switch mode {
        case "speed":
            notes.append(video ? "One 6s shot at 480p." : "Prefer a single fast image_gen call.")
        case "quality":
            notes.append(video ? "10s at 720p. Stage a strong first frame first." : "Craft a detailed image_gen prompt and make one strong frame.")
        default:
            break
        }
        if !notes.isEmpty {
            line += " " + notes.joined(separator: " ")
        }
        if let reference {
            line += " @\(reference.path)"
        }
        return line
    }

    public static func ratioValue(_ aspect: String) -> CGFloat {
        let parts = aspect.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0
        else { return 1 }
        return CGFloat(width / height)
    }
}

public enum ImagineLibrary {
    public static func recent(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions"),
        fileManager: FileManager = .default,
        limit: Int = 36
    ) -> [ImagineAsset] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var rows: [(asset: ImagineAsset, fileSize: Int, prefer: Bool)] = []
        for case let url as URL in enumerator {
            let folder = url.deletingLastPathComponent().lastPathComponent.lowercased()
            guard folder == "images" || folder == "assets" else { continue }
            guard PromptMedia.isImageURL(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            if values?.isRegularFile == false { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            let sessionTitle = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            rows.append((
                ImagineAsset(
                    url: url,
                    modified: modified,
                    sessionTitle: sessionTitle,
                    pixelSize: pixelSize(of: url)
                ),
                values?.fileSize ?? 0,
                folder == "images"
            ))
        }

        rows.sort { $0.asset.modified > $1.asset.modified }

        var chosen: [String: (asset: ImagineAsset, prefer: Bool)] = [:]
        var order: [String] = []
        for row in rows {
            let key = row.fileSize > 0 ? "\(row.asset.sessionTitle):\(row.fileSize)" : row.asset.url.path
            if let existing = chosen[key] {
                if row.prefer && !existing.prefer {
                    chosen[key] = (row.asset, true)
                }
                continue
            }
            chosen[key] = (row.asset, row.prefer)
            order.append(key)
        }

        return order.prefix(limit).compactMap { chosen[$0]?.asset }
    }

    public static func pixelSize(of url: URL) -> CGSize {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .zero }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        return CGSize(width: width, height: height)
    }
}
