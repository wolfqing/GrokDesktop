import Foundation

public struct MediaSpan: Equatable, Sendable {
    public var range: NSRange
    public var url: URL
    public var isImage: Bool

    public init(range: NSRange, url: URL, isImage: Bool) {
        self.range = range
        self.url = url
        self.isImage = isImage
    }
}

public enum PromptMedia {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]

    public static func isImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        default: return "image/png"
        }
    }

    public static func mentionToken(for url: URL) -> String {
        let path = url.path
        if path.contains(where: { $0.isWhitespace || $0 == "\"" }) {
            let escaped = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "@\"\(escaped)\""
        }
        return "@\(path)"
    }

    public static func fileURL(from raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2)
            || (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
            value = unescapeQuoted(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("~/") || value == "~" {
            value = (value as NSString).expandingTildeInPath
        }
        if value.hasPrefix("file:") {
            return URL(string: value)
                ?? URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? value)
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return nil
    }

    public static func spans(in text: String) -> [MediaSpan] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var candidates: [MediaSpan] = []

        func add(_ range: NSRange, raw: String) {
            guard range.location != NSNotFound, range.length > 1 else { return }
            guard let url = fileURL(from: raw) else { return }
            if isImageURL(url), !isPlausibleImagePath(url.path) { return }
            candidates.append(MediaSpan(range: range, url: url, isImage: isImageURL(url)))
        }

        if let regex = try? NSRegularExpression(pattern: #"@"([^"]+)""#) {
            for match in regex.matches(in: text, range: full) {
                add(match.range, raw: ns.substring(with: match.range(at: 1)))
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"@'([^']+)'"#) {
            for match in regex.matches(in: text, range: full) {
                add(match.range, raw: ns.substring(with: match.range(at: 1)))
            }
        }

        let extensions = imageExtensions.sorted().joined(separator: "|")
        if let regex = try? NSRegularExpression(pattern: "(?i)@?((?:file://)?/.+?\\.(?:\(extensions)))\\b") {
            for match in regex.matches(in: text, range: full) {
                add(match.range, raw: ns.substring(with: match.range(at: 1)))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"@((?:file://)?(?:~|/)\S+)"#) {
            for match in regex.matches(in: text, range: full) {
                add(match.range, raw: ns.substring(with: match.range(at: 1)))
            }
        }

        candidates.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        var used = IndexSet()
        var result: [MediaSpan] = []
        for span in candidates {
            let end = span.range.location + span.range.length
            guard span.range.location < end else { continue }
            let interval = span.range.location..<end
            if used.intersects(integersIn: interval) { continue }
            used.insert(integersIn: interval)
            result.append(span)
        }
        return result
    }

    public static func imageURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for span in spans(in: text) where span.isImage {
            if seen.insert(span.url.path).inserted {
                urls.append(span.url)
            }
        }
        return urls
    }

    public static func displayText(_ text: String) -> String {
        let ns = text as NSString
        var ranges: [NSRange] = []
        if let regex = try? NSRegularExpression(pattern: #"\[Image #\d+\]"#) {
            ranges.append(contentsOf: regex.matches(
                in: text,
                range: NSRange(location: 0, length: ns.length)
            ).map(\.range))
        }
        ranges.append(contentsOf: spans(in: text).filter(\.isImage).map(\.range))
        ranges.sort {
            if $0.location != $1.location { return $0.location > $1.location }
            return $0.length > $1.length
        }
        var result = text
        var consumedUntil = Int.max
        for range in ranges {
            let end = range.location + range.length
            if end > consumedUntil { continue }
            guard let swiftRange = Range(range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: " ")
            consumedUntil = range.location
        }
        result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func samePrompt(_ lhs: String, _ rhs: String) -> Bool {
        displayText(lhs) == displayText(rhs)
    }

    public static func images(in update: [String: Any]) -> (urls: [URL], displayNumber: Int?) {
        var urls: [URL] = []
        var displayNumber: Int?
        func ingest(_ content: [String: Any]) {
            let type = (content["type"] as? String)?.lowercased()
            guard type == "image" else { return }
            let meta = content["_meta"] as? [String: Any] ?? [:]
            if displayNumber == nil {
                displayNumber = intValue(meta["xai.dev/imageDisplayNumber"] ?? content["imageDisplayNumber"])
            }
            if let url = resolveImageURL(content) {
                urls.append(url)
            }
        }
        if let content = update["content"] as? [String: Any] {
            ingest(content)
        } else if let items = update["content"] as? [Any] {
            for item in items {
                if let dict = item as? [String: Any] { ingest(dict) }
            }
        }
        return (urls, displayNumber)
    }

    public static func promptBlocks(from text: String) -> [[String: Any]] {
        let urls = imageURLs(in: text)
        guard !urls.isEmpty else {
            return [["type": "text", "text": text]]
        }
        let indexByPath = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ($0.element.path, $0.offset) })
        var labeled = text
        let imageSpans = spans(in: text).filter(\.isImage).sorted {
            $0.range.location > $1.range.location
        }
        var used = IndexSet()
        var replacedPaths = Set<String>()
        for span in imageSpans {
            let end = span.range.location + span.range.length
            let interval = span.range.location..<end
            if used.intersects(integersIn: interval) { continue }
            guard let number = indexByPath[span.url.path] else { continue }
            guard let range = Range(span.range, in: labeled) else { continue }
            labeled.replaceSubrange(range, with: "[Image #\(number + 1)]")
            used.insert(integersIn: interval)
            replacedPaths.insert(span.url.path)
        }
        for (index, url) in urls.enumerated() where !replacedPaths.contains(url.path) {
            let token = "[Image #\(index + 1)]"
            let variants = [mentionToken(for: url), "@\(url.path)", url.path, url.absoluteString]
            var replaced = false
            for variant in variants {
                if let range = labeled.range(of: variant) {
                    labeled.replaceSubrange(range, with: token)
                    replaced = true
                    break
                }
            }
            if !replaced {
                labeled = labeled.trimmingCharacters(in: .whitespacesAndNewlines)
                labeled = labeled.isEmpty ? token : "\(token) \(labeled)"
            }
        }
        labeled = labeled.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks: [[String: Any]] = []
        if !labeled.isEmpty {
            blocks.append(["type": "text", "text": labeled])
        }
        for url in urls {
            if let block = imageBlock(url: url) {
                blocks.append(block)
            }
        }
        return blocks.isEmpty ? [["type": "text", "text": text]] : blocks
    }

    public static func merge(
        _ incoming: [URL],
        displayNumber: Int?,
        onto id: String,
        itemImages: inout [String: [URL]]
    ) {
        guard !incoming.isEmpty else { return }
        var existing = itemImages[id] ?? []
        for (offset, url) in incoming.enumerated() {
            if let number = displayNumber, number > 0 {
                let index = number - 1
                while existing.count <= index {
                    existing.append(url)
                }
                existing[index] = url
                continue
            }
            if existing.contains(where: { $0.path == url.path }) {
                continue
            }
            if let index = existing.firstIndex(where: isTransientPaste) {
                existing[index] = url
            } else if offset < existing.count, isTransientPaste(existing[offset]) {
                existing[offset] = url
            } else {
                existing.append(url)
            }
        }
        itemImages[id] = existing
    }

    public static func resolvedImages(stored: [URL]?, text: String) -> [URL] {
        let stored = stored ?? []
        if !stored.isEmpty { return stored }
        return imageURLs(in: text)
    }

    private static func isTransientPaste(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("grok-paste-") || url.path.contains("/grokdesktop-images/")
    }

    private static func unescapeQuoted(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    private static func isPlausibleImagePath(_ path: String) -> Bool {
        guard isImageURL(URL(fileURLWithPath: path)) else { return false }
        if FileManager.default.fileExists(atPath: path) { return true }
        if !path.contains(where: \.isWhitespace) { return true }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return !directory.contains(where: \.isWhitespace)
    }

    private static func resolveImageURL(_ content: [String: Any]) -> URL? {
        let uri = fileURL(from: content["uri"] as? String)
        if let uri, FileManager.default.fileExists(atPath: uri.path) {
            return uri
        }
        if let data = content["data"] as? String {
            return materialize(base64: data, mimeType: content["mimeType"] as? String, preferredURL: uri)
        }
        return uri
    }

    private static func materialize(base64: String, mimeType: String?, preferredURL: URL?) -> URL? {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return nil }
        if let preferredURL {
            let folder = preferredURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? data.write(to: preferredURL, options: .atomic)) != nil {
                return preferredURL
            }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grokdesktop-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = fileExtension(for: mimeType)
        let url = folder.appendingPathComponent("image-\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static func imageBlock(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return [
            "type": "image",
            "data": data.base64EncodedString(),
            "mimeType": mimeType(for: url),
            "uri": url.absoluteString
        ]
    }

    private static func fileExtension(for mimeType: String?) -> String {
        switch mimeType?.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        default: return "png"
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
