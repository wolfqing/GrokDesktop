import Foundation

public struct ACPEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var at: Date
    public var inbound: Bool
    public var method: String
    public var preview: String

    public init(
        id: String = UUID().uuidString,
        at: Date = Date(),
        inbound: Bool,
        method: String,
        preview: String
    ) {
        self.id = id
        self.at = at
        self.inbound = inbound
        self.method = method
        self.preview = preview
    }

    public var directionLabel: String { inbound ? "←" : "→" }

    public var line: String {
        "\(directionLabel) \(method) \(preview)"
    }

    public static func preview(method: String, params: [String: Any], extra: String = "") -> String {
        var parts: [String] = []
        if let session = params["sessionId"] as? String ?? params["session_id"] as? String {
            parts.append("session \(session.prefix(8))")
        }
        if let path = params["path"] as? String {
            parts.append(path)
        }
        if let terminal = params["terminalId"] as? String ?? params["terminal_id"] as? String {
            parts.append("term \(terminal.prefix(8))")
        }
        if let command = params["command"] as? String {
            parts.append(command)
        }
        if let update = params["update"] as? [String: Any],
           let kind = update["sessionUpdate"] as? String ?? update["session_update"] as? String {
            parts.append(kind)
        }
        if !extra.isEmpty { parts.append(extra) }
        let text = parts.joined(separator: " · ")
        return String(text.prefix(220))
    }
}
