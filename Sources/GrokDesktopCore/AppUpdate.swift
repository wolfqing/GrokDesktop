import Foundation

/// Marketing version such as `0.1.29`. A leading `v` is accepted. Pre-release
/// suffixes are ignored so `0.1.30-beta` compares as `0.1.30`.
public struct AppVersion: Comparable, Equatable, Hashable, Sendable {
    public var components: [Int]
    public var raw: String

    public init?(parsing text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        if let end = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            trimmed = String(trimmed[..<end])
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part), number >= 0 else {
                return nil
            }
            numbers.append(number)
        }
        self.components = numbers
        self.raw = numbers.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct AppRelease: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var notes: String
    public var pageURL: URL?
    public var zipURL: URL
    public var fileName: String
    public var byteCount: Int64
}

public enum AppUpdateDecision: Equatable, Sendable {
    case upToDate
    case download(AppRelease)
}

public enum AppUpdateFailure: String, Error, Equatable, Sendable {
    case unavailable
    case malformed
    case noZip
    case untrusted
    case tooLarge
    case badArchive
    case installFailed
}

public enum AppUpdateFeed {
    public static let owner = "wolfqing"
    public static let repo = "GrokDesktop"
    public static let bundleIdentifier = "com.wolfqing.GrokDesktop"
    public static let bundleName = "Grok Desktop.app"
    public static let executableName = "GrokDesktop"
    /// While the app stays open, look again on this interval. Launch always checks.
    public static let checkInterval: TimeInterval = 4 * 60 * 60
    public static let maxZipBytes: Int64 = 200_000_000

    public static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    public static func parseLatest(_ data: Data, current: AppVersion) -> Result<AppUpdateDecision, AppUpdateFailure> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformed)
        }
        guard let tag = object["tag_name"] as? String,
              let version = AppVersion(parsing: tag),
              tag == "v\(version.raw)"
        else {
            return .failure(.malformed)
        }
        guard version > current else { return .success(.upToDate) }
        guard let assets = object["assets"] as? [[String: Any]] else { return .failure(.noZip) }
        let fileName = "Grok-Desktop-\(version.raw).zip"
        guard let asset = assets.first(where: { $0["name"] as? String == fileName }),
              let urlText = asset["browser_download_url"] as? String,
              let zipURL = URL(string: urlText),
              isTrustedDownloadURL(zipURL, version: version)
        else {
            return .failure(.noZip)
        }
        let byteCount = (asset["size"] as? NSNumber)?.int64Value ?? 0
        if byteCount > maxZipBytes { return .failure(.tooLarge) }
        let notes = String(((object["body"] as? String) ?? "").prefix(4_000))
        let pageURL = (object["html_url"] as? String).flatMap(URL.init(string:))
        let release = AppRelease(
            version: version,
            tag: tag,
            notes: notes,
            pageURL: pageURL,
            zipURL: zipURL,
            fileName: fileName,
            byteCount: byteCount
        )
        return .success(.download(release))
    }

    /// The URL we are willing to request. Redirects are checked separately.
    public static func isTrustedDownloadURL(_ url: URL, version: AppVersion) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard url.user == nil, url.password == nil, url.port == nil else { return false }
        guard url.host?.lowercased() == "github.com" else { return false }
        let expected = "/\(owner)/\(repo)/releases/download/v\(version.raw)/Grok-Desktop-\(version.raw).zip"
        return url.path == expected
    }

    public static func isTrustedRedirect(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard url.user == nil, url.password == nil else { return false }
        if let port = url.port, port != 443 { return false }
        switch url.host?.lowercased() {
        case "github.com",
             "objects.githubusercontent.com",
             "release-assets.githubusercontent.com",
             "github-releases.githubusercontent.com":
            return true
        default:
            return false
        }
    }
}

public struct StagedAppUpdate: Codable, Equatable, Sendable {
    public var version: String
    public var appPath: String
    public var stagedAt: Date

    public init(version: String, appPath: String, stagedAt: Date) {
        self.version = version
        self.appPath = appPath
        self.stagedAt = stagedAt
    }
}

public struct AppUpdateCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("com.wolfqing.GrokDesktop/updates", isDirectory: true)
    }

    public var manifestURL: URL { root.appendingPathComponent("staged.json") }
    public var extractDirectory: URL { root.appendingPathComponent("extracted", isDirectory: true) }

    public func zipURL(version: AppVersion) -> URL {
        root.appendingPathComponent("Grok-Desktop-\(version.raw).zip")
    }

    public func partialURL(version: AppVersion) -> URL {
        root.appendingPathComponent("Grok-Desktop-\(version.raw).zip.partial")
    }

    public func load() -> StagedAppUpdate? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StagedAppUpdate.self, from: data)
    }

    public func save(_ staged: StagedAppUpdate) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(staged)
        try data.write(to: manifestURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The staged bundle has to live inside this cache and match the release we asked for.
    public func verifiedApp(version: AppVersion) -> URL? {
        guard let staged = load(), staged.version == version.raw else { return nil }
        let app = URL(fileURLWithPath: staged.appPath).resolvingSymlinksInPath().standardizedFileURL
        let extract = extractDirectory.resolvingSymlinksInPath().standardizedFileURL
        let prefix = extract.path.hasSuffix("/") ? extract.path : extract.path + "/"
        guard app.path.hasPrefix(prefix) else { return nil }
        guard AppBundleCheck.matchesRelease(app, version: version) else { return nil }
        return app
    }
}

public enum AppBundleCheck {
    public struct Identity: Equatable, Sendable {
        public var identifier: String
        public var version: AppVersion
    }

    public static func identity(app: URL) -> Identity? {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let executable = app.appendingPathComponent("Contents/MacOS/\(AppUpdateFeed.executableName)")
        guard FileManager.default.fileExists(atPath: executable.path) else { return nil }
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = object["CFBundleIdentifier"] as? String,
              let versionText = object["CFBundleShortVersionString"] as? String,
              let version = AppVersion(parsing: versionText)
        else { return nil }
        return Identity(identifier: identifier, version: version)
    }

    public static func matchesRelease(_ app: URL, version: AppVersion) -> Bool {
        guard let identity = identity(app: app) else { return false }
        return identity.identifier == AppUpdateFeed.bundleIdentifier && identity.version == version
    }
}

public enum RunningApp {
    public enum Blocker: Equatable, Sendable {
        case notInstalledApp
        case translocated
        case notWritable
    }

    public static func bundleURL(bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL
        guard url.pathExtension == "app" else { return nil }
        guard bundle.bundleIdentifier == AppUpdateFeed.bundleIdentifier else { return nil }
        return url
    }

    public static func blocker(appURL: URL?) -> Blocker? {
        guard let appURL, appURL.pathExtension == "app" else { return .notInstalledApp }
        if appURL.resolvingSymlinksInPath().path.contains("/AppTranslocation/") { return .translocated }
        let parent = appURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) { return .notWritable }
        return nil
    }
}

public enum AppUpdateInstaller {
    public enum SwapError: Error, Equatable {
        case unreadableSource
        case copyFailed
        case verifyFailed
        case replaceFailed
    }

    public static func looksLikeZip(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        // Local file header, or an empty archive.
        return data == Data([0x50, 0x4B, 0x03, 0x04]) || data == Data([0x50, 0x4B, 0x05, 0x06])
    }

    public static func extract(zip: URL, into directory: URL) -> Bool {
        let files = FileManager.default
        try? files.removeItem(at: directory)
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let result = TimedProcess.capture(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zip.path, directory.path],
            cwd: directory,
            timeout: 120
        )
        return result.ok
    }

    public static func stagedApp(in extractDirectory: URL) -> URL {
        extractDirectory.appendingPathComponent(AppUpdateFeed.bundleName)
    }

    /// Unzip, require our bundle id and version, then remember the staged app.
    public static func stage(zip: URL, version: AppVersion, cache: AppUpdateCache) -> URL? {
        guard looksLikeZip(zip) else { return nil }
        guard extract(zip: zip, into: cache.extractDirectory) else { return nil }
        let app = stagedApp(in: cache.extractDirectory)
        guard AppBundleCheck.matchesRelease(app, version: version) else { return nil }
        let staged = StagedAppUpdate(version: version.raw, appPath: app.path, stagedAt: Date())
        guard (try? cache.save(staged)) != nil else { return nil }
        return cache.verifiedApp(version: version)
    }

    /// Copy the new app beside the running one, then swap names.
    /// On failure after the running app was moved aside, the previous bundle is put back.
    public static func swap(stagedApp: URL, destination: URL) throws {
        let files = FileManager.default
        guard AppBundleCheck.identity(app: stagedApp) != nil else { throw SwapError.unreadableSource }
        let parent = destination.deletingLastPathComponent()
        let incoming = parent.appendingPathComponent(destination.lastPathComponent + ".incoming")
        let previous = parent.appendingPathComponent(destination.lastPathComponent + ".previous")
        try? files.removeItem(at: incoming)
        let copied = TimedProcess.capture(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: [stagedApp.path, incoming.path],
            cwd: parent,
            timeout: 120
        )
        guard copied.ok else {
            try? files.removeItem(at: incoming)
            throw SwapError.copyFailed
        }
        guard AppBundleCheck.identity(app: incoming) != nil else {
            try? files.removeItem(at: incoming)
            throw SwapError.verifyFailed
        }
        clearQuarantine(incoming)
        do {
            if files.fileExists(atPath: previous.path) {
                try files.removeItem(at: previous)
            }
            if files.fileExists(atPath: destination.path) {
                try files.moveItem(at: destination, to: previous)
            }
            try files.moveItem(at: incoming, to: destination)
        } catch {
            if !files.fileExists(atPath: destination.path), files.fileExists(atPath: previous.path) {
                try? files.moveItem(at: previous, to: destination)
            }
            try? files.removeItem(at: incoming)
            throw SwapError.replaceFailed
        }
        clearQuarantine(destination)
    }

    public static func clearQuarantine(_ url: URL) {
        _ = TimedProcess.capture(
            executable: URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", url.path],
            cwd: url.deletingLastPathComponent(),
            timeout: 20
        )
    }

    public static func removeIncoming(beside destination: URL) {
        let incoming = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".incoming")
        try? FileManager.default.removeItem(at: incoming)
    }

    public static func removePrevious(beside destination: URL) {
        let previous = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".previous")
        try? FileManager.default.removeItem(at: previous)
    }
}
