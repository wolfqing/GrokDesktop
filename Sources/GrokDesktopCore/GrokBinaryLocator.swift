import Foundation

public struct GrokBinaryLocator: Sendable {
    public var extraSearchPaths: [URL]
    public var pathEnvironment: String?
    public var fileExists: @Sendable (URL) -> Bool

    public init(
        extraSearchPaths: [URL] = [],
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
        self.extraSearchPaths = extraSearchPaths
        self.pathEnvironment = pathEnvironment
        self.fileExists = fileExists
    }

    public func locate() -> URL? {
        var seen = Set<String>()
        for url in candidates() {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if fileExists(url) {
                return url
            }
        }
        return nil
    }

    public func candidates() -> [URL] {
        var urls: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let pathEnvironment {
            for entry in pathEnvironment.split(separator: ":") {
                let dir = URL(fileURLWithPath: String(entry), isDirectory: true)
                urls.append(dir.appendingPathComponent("grok"))
            }
        }

        urls.append(contentsOf: extraSearchPaths)
        urls.append(home.appendingPathComponent(".local/bin/grok"))
        urls.append(home.appendingPathComponent(".grok/bin/grok"))
        urls.append(URL(fileURLWithPath: "/opt/homebrew/bin/grok"))
        urls.append(URL(fileURLWithPath: "/usr/local/bin/grok"))
        return urls
    }
}
