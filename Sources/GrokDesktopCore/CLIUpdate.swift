import Foundation

public struct CLIUpdateStatus: Equatable, Sendable {
    public var current: String
    public var latest: String
    public var updateAvailable: Bool
    public var channel: String
    public var installer: String
    public var autoUpdate: Bool
    public var error: String?
    public var checkedAt: Date?

    public init(
        current: String = "",
        latest: String = "",
        updateAvailable: Bool = false,
        channel: String = "",
        installer: String = "",
        autoUpdate: Bool = false,
        error: String? = nil,
        checkedAt: Date? = nil
    ) {
        self.current = current
        self.latest = latest
        self.updateAvailable = updateAvailable
        self.channel = channel
        self.installer = installer
        self.autoUpdate = autoUpdate
        self.error = error
        self.checkedAt = checkedAt
    }

    public var summary: String {
        if let error, !error.isEmpty { return error }
        if current.isEmpty { return "" }
        if latest.isEmpty || latest == current {
            return updateAvailable ? current : current
        }
        return "\(current) → \(latest)"
    }

    public static func parse(_ text: String, at date: Date = Date()) -> CLIUpdateStatus {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let current = object["currentVersion"] as? String ?? object["current"] as? String ?? ""
            let latest = object["latestVersion"] as? String ?? object["latest"] as? String ?? current
            let available = object["updateAvailable"] as? Bool
                ?? (current != latest && !latest.isEmpty)
            let err = object["error"] as? String
            return CLIUpdateStatus(
                current: current,
                latest: latest,
                updateAvailable: available,
                channel: object["channel"] as? String ?? "",
                installer: object["installer"] as? String ?? "",
                autoUpdate: object["autoUpdate"] as? Bool ?? false,
                error: (err?.isEmpty == false) ? err : nil,
                checkedAt: date
            )
        }
        return parsePlain(trimmed, at: date)
    }

    public static func check(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CLIUpdateStatus {
        guard let grok = locator.locate() else {
            return CLIUpdateStatus(error: "grok not found", checkedAt: Date())
        }
        let captured = TimedProcess.capture(
            executable: grok,
            arguments: ["update", "--check", "--json"],
            cwd: cwd,
            timeout: 20
        )
        let text = captured.text
        if text.isEmpty {
            return CLIUpdateStatus(
                error: captured.timedOut ? "Timed out" : "No output from grok update --check",
                checkedAt: Date()
            )
        }
        var status = parse(text)
        if status.current.isEmpty, status.error == nil {
            status.error = captured.ok ? "Could not parse update status" : text
        }
        return status
    }

    public static func install(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        cwd: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ProcessCapture {
        guard let grok = locator.locate() else {
            return ProcessCapture(status: 1, stderr: "grok not found")
        }
        return TimedProcess.capture(
            executable: grok,
            arguments: ["update"],
            cwd: cwd,
            timeout: 180,
            limitBytes: 2_000_000
        )
    }

    private static func parsePlain(_ text: String, at date: Date) -> CLIUpdateStatus {
        // Grok Build - v1.0.13 (latest: 1.0.13) [stable]
        var current = ""
        var latest = ""
        var channel = ""
        if let match = text.range(of: #"v?(\d+\.\d+\.[0-9A-Za-z.\-]+)"#, options: .regularExpression) {
            current = String(text[match]).trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        }
        if let range = text.range(of: "latest:") {
            let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            latest = rest.split(whereSeparator: { $0 == ")" || $0 == " " || $0 == "]" }).first.map(String.init) ?? ""
        }
        if let start = text.firstIndex(of: "["), let end = text.firstIndex(of: "]"), start < end {
            channel = String(text[text.index(after: start)..<end])
        }
        if current.isEmpty, latest.isEmpty {
            return CLIUpdateStatus(error: text, checkedAt: date)
        }
        if latest.isEmpty { latest = current }
        return CLIUpdateStatus(
            current: current,
            latest: latest,
            updateAvailable: current != latest && !latest.isEmpty,
            channel: channel,
            checkedAt: date
        )
    }
}
