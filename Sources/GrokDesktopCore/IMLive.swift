import CryptoKit
import Foundation

public struct IMLiveEvent: Equatable, Sendable {
    public var id: String
    public var sender: String
    public var text: String

    public init(id: String = "", sender: String, text: String) {
        self.id = id
        self.sender = sender
        self.text = text
    }
}

public struct GatewayFrame: Equatable, Sendable {
    public var op: Int
    public var name: String
    public var sequence: Int?
    public var heartbeatMs: Int
    public var events: [IMLiveEvent]

    public init(op: Int, name: String, sequence: Int?, heartbeatMs: Int, events: [IMLiveEvent]) {
        self.op = op
        self.name = name
        self.sequence = sequence
        self.heartbeatMs = heartbeatMs
        self.events = events
    }
}

/// Official inbound parsers and endpoint builders. No network calls.
public enum IMLive {
    public static func telegramURL(token: String, offset: Int) -> URL? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz:_-")
        guard !cleaned.isEmpty, cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.telegram.org"
        parts.path = "/bot\(cleaned)/getUpdates"
        parts.queryItems = [
            URLQueryItem(name: "timeout", value: "25"),
            URLQueryItem(name: "offset", value: String(max(0, offset)))
        ]
        return parts.url
    }

    public static func telegram(data: Data, offset: Int) -> (offset: Int, events: [IMLiveEvent]) {
        guard let object = jsonObject(data),
              (object["ok"] as? Bool) == true,
              let rows = object["result"] as? [[String: Any]]
        else { return (offset, []) }
        var next = offset
        var events: [IMLiveEvent] = []
        for row in rows {
            let update = intValue(row["update_id"])
            if update >= next { next = update + 1 }
            let message = (row["message"] as? [String: Any])
                ?? (row["edited_message"] as? [String: Any])
                ?? (row["channel_post"] as? [String: Any])
            guard let message, let text = trimmed(message["text"] as? String) else { continue }
            let from = message["from"] as? [String: Any]
            let sender = (from?["username"] as? String) ?? string(from?["id"]) 
            events.append(IMLiveEvent(sender: sender, text: text))
        }
        return (next, events)
    }

    public static func matrixSyncURL(homeserver: String, since: String) -> URL? {
        let trimmed = homeserver.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil
        else { return nil }
        parts.path = "/_matrix/client/v3/sync"
        parts.fragment = nil
        var items = [URLQueryItem(name: "timeout", value: "30000")]
        if !since.isEmpty {
            items.append(URLQueryItem(name: "since", value: since))
        }
        parts.queryItems = items
        return parts.url
    }

    public static func matrix(data: Data) -> (next: String, events: [IMLiveEvent]) {
        guard let object = jsonObject(data) else { return ("", []) }
        let next = object["next_batch"] as? String ?? ""
        var events: [IMLiveEvent] = []
        let rooms = object["rooms"] as? [String: Any]
        let join = rooms?["join"] as? [String: Any] ?? [:]
        for (_, value) in join {
            guard let room = value as? [String: Any],
                  let timeline = room["timeline"] as? [String: Any],
                  let rows = timeline["events"] as? [[String: Any]]
            else { continue }
            for row in rows {
                guard (row["type"] as? String) == "m.room.message",
                      let content = row["content"] as? [String: Any],
                      (content["msgtype"] as? String) == "m.text",
                      let text = trimmed(content["body"] as? String)
                else { continue }
                events.append(IMLiveEvent(sender: row["sender"] as? String ?? "", text: text))
            }
        }
        return (next, events)
    }

    public static func discordIdentify(token: String) -> String {
        let body: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "intents": 37377,
                "properties": [
                    "$os": "macOS",
                    "$browser": "GrokDesktop",
                    "$device": "GrokDesktop"
                ]
            ]
        ]
        return jsonString(body)
    }

    public static func qqTokenBody(appId: String, secret: String) -> Data {
        jsonData(["appId": appId, "clientSecret": secret])
    }

    public static func qqAccessToken(data: Data) -> String? {
        guard let object = jsonObject(data) else { return nil }
        return trimmed(object["access_token"] as? String)
    }

    public static func qqIdentify(accessToken: String) -> String {
        let body: [String: Any] = [
            "op": 2,
            "d": [
                "token": "QQBot \(accessToken)",
                "intents": (1 << 25) | (1 << 30) | 512,
                "shard": [0, 1],
                "properties": [
                    "$os": "macOS",
                    "$browser": "GrokDesktop",
                    "$device": "GrokDesktop"
                ]
            ]
        ]
        return jsonString(body)
    }

    public static func gatewayHeartbeat(sequence: Int?) -> String {
        if let sequence {
            return "{\"op\":1,\"d\":\(sequence)}"
        }
        return "{\"op\":1,\"d\":null}"
    }

    /// Discord and QQ gateway frames share opcodes. `qq` keeps group and c2c messages.
    public static func gatewayFrame(_ text: String, qq: Bool) -> GatewayFrame {
        guard let object = jsonObject(Data(text.utf8)) else {
            return GatewayFrame(op: -1, name: "", sequence: nil, heartbeatMs: 0, events: [])
        }
        let op = intValue(object["op"])
        let name = object["t"] as? String ?? ""
        let sequence = object["s"] == nil || object["s"] is NSNull ? nil : intValue(object["s"])
        var heartbeat = 0
        var events: [IMLiveEvent] = []
        if op == 10, let data = object["d"] as? [String: Any] {
            heartbeat = intValue(data["heartbeat_interval"])
        }
        if op == 0, let data = object["d"] as? [String: Any] {
            let accepted = qq
                ? ["C2C_MESSAGE_CREATE", "GROUP_AT_MESSAGE_CREATE", "AT_MESSAGE_CREATE", "DIRECT_MESSAGE_CREATE"]
                : ["MESSAGE_CREATE"]
            if accepted.contains(name), let text = trimmed(data["content"] as? String) {
                let author = data["author"] as? [String: Any]
                if (author?["bot"] as? Bool) != true {
                    let sender = (author?["username"] as? String) ?? (author?["id"] as? String) ?? ""
                    events.append(IMLiveEvent(sender: sender, text: text))
                }
            }
        }
        return GatewayFrame(op: op, name: name, sequence: sequence, heartbeatMs: heartbeat, events: events)
    }

    public static func slackSocketURL(data: Data) -> URL? {
        guard let object = jsonObject(data), (object["ok"] as? Bool) == true, let raw = object["url"] as? String,
              let url = URL(string: raw), url.scheme == "wss",
              let host = url.host?.lowercased(), host == "slack.com" || host.hasSuffix(".slack.com")
        else { return nil }
        return url
    }

    public static func slackEvents(frame: String) -> [IMLiveEvent] {
        guard let object = jsonObject(Data(frame.utf8)),
              (object["type"] as? String) == "events_api",
              let payload = object["payload"] as? [String: Any],
              let event = payload["event"] as? [String: Any],
              (event["type"] as? String) == "message",
              event["subtype"] == nil || (event["subtype"] is NSNull),
              let text = trimmed(event["text"] as? String)
        else { return [] }
        return [IMLiveEvent(sender: event["user"] as? String ?? "", text: text)]
    }

    public static func slackEnvelopeID(_ frame: String) -> String? {
        guard let object = jsonObject(Data(frame.utf8)) else { return nil }
        return trimmed(object["envelope_id"] as? String)
    }

    public static func slackAck(envelopeID: String) -> String {
        jsonString(["envelope_id": envelopeID])
    }

    /// Socket Mode needs an app-level token. A bot token cannot open the socket.
    public static func slackUsesSocket(_ token: String) -> Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("xapp-")
    }

    public static func dingtalkOpenBody(appKey: String, appSecret: String) -> Data {
        jsonData([
            "clientId": appKey,
            "clientSecret": appSecret,
            "subscriptions": [
                ["type": "CALLBACK", "topic": "/v1.0/im/bot/messages/get"]
            ],
            "ua": "GrokDesktop"
        ])
    }

    public static func dingtalkSocket(data: Data) -> URL? {
        guard let object = jsonObject(data),
              let ticket = trimmed(object["ticket"] as? String),
              var raw = object["endpoint"] as? String
        else { return nil }
        if !raw.contains("://") { raw = "wss://\(raw)" }
        guard var parts = URLComponents(string: raw) else { return nil }
        if parts.scheme == "https" { parts.scheme = "wss" }
        guard parts.scheme == "wss", let host = parts.host?.lowercased(),
              host == "dingtalk.com" || host.hasSuffix(".dingtalk.com")
        else { return nil }
        if parts.path.isEmpty { parts.path = "/connect" }
        var items = parts.queryItems ?? []
        if !items.contains(where: { $0.name == "ticket" }) {
            items.append(URLQueryItem(name: "ticket", value: ticket))
        }
        parts.queryItems = items
        return parts.url
    }

    public static func dingtalk(frame: String) -> (messageID: String, events: [IMLiveEvent]) {
        guard let object = jsonObject(Data(frame.utf8)) else { return ("", []) }
        let headers = object["headers"] as? [String: Any]
        let messageID = headers?["messageId"] as? String ?? ""
        let payload = object["data"]
        let inner: [String: Any]?
        if let text = payload as? String {
            inner = jsonObject(Data(text.utf8))
        } else {
            inner = payload as? [String: Any]
        }
        guard let inner else { return (messageID, []) }
        let text = trimmed((inner["text"] as? [String: Any])?["content"] as? String)
            ?? trimmed(inner["content"] as? String)
        guard let text else { return (messageID, []) }
        let sender = inner["senderNick"] as? String ?? inner["senderId"] as? String ?? ""
        return (messageID, [IMLiveEvent(sender: sender, text: text)])
    }

    public static func dingtalkAck(messageID: String) -> String {
        jsonString([
            "code": 200,
            "headers": ["messageId": messageID],
            "message": "OK",
            "data": "{}"
        ])
    }

    public static func feishuTokenBody(appId: String, appSecret: String) -> Data {
        jsonData(["app_id": appId, "app_secret": appSecret])
    }

    public static func feishuTokenOK(data: Data) -> Bool {
        guard let object = jsonObject(data) else { return false }
        if intValue(object["code"]) != 0 { return false }
        return trimmed(object["tenant_access_token"] as? String) != nil
    }

    public static func feishuEvents(frame: String) -> [IMLiveEvent] {
        guard let object = jsonObject(Data(frame.utf8)) else { return [] }
        let header = object["header"] as? [String: Any]
        guard (header?["event_type"] as? String) == "im.message.receive_v1",
              let event = object["event"] as? [String: Any],
              let message = event["message"] as? [String: Any],
              (message["message_type"] as? String) == "text",
              let content = message["content"] as? String,
              let inner = jsonObject(Data(content.utf8)),
              let text = trimmed(inner["text"] as? String)
        else { return [] }
        let senderBox = event["sender"] as? [String: Any]
        let senderID = senderBox?["sender_id"] as? [String: Any]
        let sender = senderID?["open_id"] as? String ?? ""
        return [IMLiveEvent(sender: sender, text: text)]
    }

    public static func lineBotURL() -> URL {
        URL(string: "https://api.line.me/v2/bot/info")!
    }

    public static func lineEvents(data: Data) -> [IMLiveEvent] {
        guard let object = jsonObject(data), let rows = object["events"] as? [[String: Any]] else { return [] }
        var events: [IMLiveEvent] = []
        for row in rows {
            guard (row["type"] as? String) == "message",
                  let message = row["message"] as? [String: Any],
                  (message["type"] as? String) == "text",
                  let text = trimmed(message["text"] as? String)
            else { continue }
            let source = row["source"] as? [String: Any]
            events.append(IMLiveEvent(sender: source?["userId"] as? String ?? "", text: text))
        }
        return events
    }

    public static func lineSignature(secret: String, body: Data) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return Data(code).base64EncodedString()
    }

    public static func weiboURL(token: String) -> URL? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains(where: \.isWhitespace) else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.weibo.com"
        parts.path = "/2/direct_messages.json"
        parts.queryItems = [
            URLQueryItem(name: "access_token", value: cleaned),
            URLQueryItem(name: "count", value: "20")
        ]
        return parts.url
    }

    public static func weiboOK(_ data: Data) -> Bool {
        guard let object = jsonObject(data) else { return false }
        if object["error"] != nil || object["error_code"] != nil { return false }
        return object["direct_messages"] != nil || object["messages"] != nil
    }

    public static func weibo(data: Data) -> [IMLiveEvent] {
        guard weiboOK(data), let object = jsonObject(data) else { return [] }
        let rows = (object["direct_messages"] as? [[String: Any]]) ?? (object["messages"] as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let text = trimmed(row["text"] as? String) else { return nil }
            let sender = (row["sender"] as? [String: Any])?["name"] as? String ?? ""
            return IMLiveEvent(id: string(row["id"]), sender: sender, text: text)
        }
    }

    public static func wecomTokenURL(corpId: String, secret: String) -> URL? {
        let corp = corpId.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corp.isEmpty, !key.isEmpty, !corp.contains(where: \.isWhitespace), !key.contains(where: \.isWhitespace) else {
            return nil
        }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "qyapi.weixin.qq.com"
        parts.path = "/cgi-bin/gettoken"
        parts.queryItems = [
            URLQueryItem(name: "corpid", value: corp),
            URLQueryItem(name: "corpsecret", value: key)
        ]
        return parts.url
    }

    public static func wecomTokenOK(data: Data) -> Bool {
        guard let object = jsonObject(data) else { return false }
        return intValue(object["errcode"]) == 0 && trimmed(object["access_token"] as? String) != nil
    }

    public static func wecomEvents(xml: String) -> [IMLiveEvent] {
        guard let text = trimmed(xmlTag("Content", xml)) else { return [] }
        return [IMLiveEvent(sender: xmlTag("FromUserName", xml) ?? "", text: text)]
    }

    public static func imessageHandleOK(_ handle: String) -> Bool {
        if handle == "*" { return true }
        let allowed = CharacterSet(charactersIn: "+0123456789@.-_")
        return !handle.isEmpty && handle.count < 80 && handle.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func imessage(output: String, handle: String) -> [IMLiveEvent] {
        guard imessageHandleOK(handle) else { return [] }
        var events: [IMLiveEvent] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let id = String(parts[0])
            let sender = String(parts[1])
            guard let text = trimmed(String(parts[2])) else { continue }
            guard handle == "*" || handlesMatch(handle, sender) else { continue }
            events.append(IMLiveEvent(id: id, sender: sender, text: text))
        }
        return events
    }

    private static func handlesMatch(_ wanted: String, _ sender: String) -> Bool {
        if sender.caseInsensitiveCompare(wanted) == .orderedSame { return true }
        let wantedDigits = wanted.filter(\.isNumber)
        let senderDigits = sender.filter(\.isNumber)
        return !wantedDigits.isEmpty && wantedDigits == senderDigits
    }

    private static func xmlTag(_ name: String, _ xml: String) -> String? {
        let pattern = "<\(name)>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</\(name)>"
        guard let range = xml.range(of: pattern, options: .regularExpression) else { return nil }
        var value = String(xml[range])
        if let start = value.range(of: ">")?.upperBound, let end = value.range(of: "</", options: .backwards)?.lowerBound {
            value = String(value[start..<end])
        }
        value = value.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmed(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func jsonData(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func jsonString(_ object: Any) -> String {
        String(data: jsonData(object), encoding: .utf8) ?? ""
    }
}
