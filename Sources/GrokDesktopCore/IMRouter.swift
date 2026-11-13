import Foundation

public enum IMChannel: String, CaseIterable, Codable, Sendable, Equatable {
    case feishu
    case telegram
    case discord
    case slack
    case dingtalk
    case wecom
    case wechat
    case qq
    case matrix
    case line
    case weibo
    case imessage

    public var requiredFields: [String] {
        switch self {
        case .feishu: return ["appId", "appSecret"]
        case .telegram: return ["botToken"]
        case .discord: return ["botToken"]
        case .slack: return ["botToken"]
        case .dingtalk: return ["appKey", "appSecret"]
        case .wecom: return ["corpId", "agentSecret"]
        case .wechat: return ["account"]
        case .qq: return ["appId", "token"]
        case .matrix: return ["homeserver", "accessToken"]
        case .line: return ["channelSecret", "channelToken"]
        case .weibo: return ["appKey", "accessToken"]
        case .imessage: return ["handle"]
        }
    }
}

public struct IMBridgeConfig: Equatable, Sendable, Codable {
    public var channel: IMChannel
    public var fields: [String: String]

    public init(channel: IMChannel, fields: [String: String]) {
        self.channel = channel
        self.fields = fields
    }

    public var isComplete: Bool {
        channel.requiredFields.allSatisfy {
            !(fields[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct IMInbound: Equatable, Sendable {
    public var channel: IMChannel
    public var sender: String
    public var text: String

    public init(channel: IMChannel, sender: String, text: String) {
        self.channel = channel
        self.sender = sender
        self.text = text
    }
}

public enum IMRoute: Equatable, Sendable {
    case rejectedIncomplete
    case rejectedUntrusted
    case start(project: String, prompt: String)
    case resume(sessionID: String, prompt: String)
    case turn(project: String, prompt: String)
}

public enum IMRouter {
    public static func fixtureConfig(_ channel: IMChannel) -> IMBridgeConfig {
        let fields = Dictionary(uniqueKeysWithValues: channel.requiredFields.map { ($0, "fixture") })
        return IMBridgeConfig(channel: channel, fields: fields)
    }

    public static func fixturePayload(_ channel: IMChannel) -> [String: String] {
        ["channel": channel.rawValue, "sender": "fixture", "text": "ping"]
    }

    public static func accept(payload: [String: String], config: IMBridgeConfig) -> IMInbound? {
        guard config.isComplete else { return nil }
        if let named = payload["channel"], named != config.channel.rawValue { return nil }
        let text = payload["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        return IMInbound(channel: config.channel, sender: payload["sender"] ?? "", text: text)
    }

    /// `/p` starts a session only for a trusted project. `/r` resumes one that already exists.
    /// Other text becomes a turn only when the bound project is trusted.
    public static func route(
        inbound: IMInbound,
        trustedProjects: [String],
        sessions: [String],
        boundProject: String?
    ) -> IMRoute {
        let text = inbound.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/p ") {
            let (name, prompt) = splitCommand(text, prefixCount: 3)
            guard let project = matchProject(name, trusted: trustedProjects) else { return .rejectedUntrusted }
            return .start(project: project, prompt: prompt)
        }
        if text.hasPrefix("/r ") {
            let (id, prompt) = splitCommand(text, prefixCount: 3)
            guard sessions.contains(id) else { return .rejectedUntrusted }
            guard let project = boundProject, matchProject(project, trusted: trustedProjects) != nil else {
                return .rejectedUntrusted
            }
            return .resume(sessionID: id, prompt: prompt)
        }
        guard let project = boundProject, let trusted = matchProject(project, trusted: trustedProjects) else {
            return .rejectedUntrusted
        }
        return .turn(project: trusted, prompt: text)
    }

    private static func splitCommand(_ text: String, prefixCount: Int) -> (String, String) {
        let rest = text.dropFirst(prefixCount).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let head = parts.first.map(String.init) ?? ""
        let tail = parts.count > 1 ? String(parts[1]) : ""
        return (head, tail)
    }

    private static func matchProject(_ name: String, trusted: [String]) -> String? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let wanted = URL(fileURLWithPath: needle).standardizedFileURL.path
        for project in trusted {
            let path = URL(fileURLWithPath: project).standardizedFileURL.path
            if path == wanted || URL(fileURLWithPath: path).lastPathComponent == needle {
                return path
            }
        }
        return nil
    }
}
