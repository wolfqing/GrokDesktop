import Foundation
import GrokDesktopCore
import Network

/// Official inbound runners. Tokens stay in requests and are never written into status text.
@MainActor
final class BridgeLive {
    private weak var model: AppModel?
    private var jobs: [IMChannel: Task<Void, Never>] = [:]
    private var sockets: [IMChannel: URLSessionWebSocketTask] = [:]
    private var session: URLSession
    private let redirects = RefuseRedirect()
    private var hook: LoopbackHook?
    private var lineSecret = ""
    private var lineOn = false
    private var wecomOn = false
    private var lineVerified = false
    private var wecomVerified = false
    private var hookPort: UInt16 = 0

    init() {
        session = Self.makeSession(delegate: redirects)
    }

    func start(model: AppModel) {
        stop()
        self.model = model
        let configs = model.desk.bridges.filter(\.isComplete)
        guard !configs.isEmpty else {
            noteKey("live", "Save a bridge before starting live.", "先保存桥接，再开实时。")
            return
        }
        for config in configs {
            if config.channel == .line {
                lineOn = true
                lineSecret = config.fields["channelSecret"] ?? ""
            }
            if config.channel == .wecom { wecomOn = true }
        }
        if lineOn || wecomOn { startHook() }
        for config in configs {
            jobs[config.channel] = Task { [weak self] in
                await self?.run(config)
            }
        }
        noteKey("live", "Live is on for saved bridges.", "已保存的桥接正在实时接收。")
    }

    func stop() {
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
        for socket in sockets.values { socket.cancel(with: .goingAway, reason: nil) }
        sockets.removeAll()
        hook?.stop()
        hook = nil
        hookPort = 0
        lineSecret = ""
        lineOn = false
        wecomOn = false
        lineVerified = false
        wecomVerified = false
        session.invalidateAndCancel()
        session = Self.makeSession(delegate: redirects)
    }

    private func run(_ config: IMBridgeConfig) async {
        switch config.channel {
        case .telegram:
            await runTelegram(config.fields["botToken"] ?? "")
        case .discord:
            await runDiscord(config.fields["botToken"] ?? "")
        case .matrix:
            await runMatrix(homeserver: config.fields["homeserver"] ?? "", token: config.fields["accessToken"] ?? "")
        case .slack:
            await runSlack(config.fields["botToken"] ?? "")
        case .qq:
            await runQQ(appId: config.fields["appId"] ?? "", secret: config.fields["token"] ?? "")
        case .dingtalk:
            await runDingTalk(appKey: config.fields["appKey"] ?? "", appSecret: config.fields["appSecret"] ?? "")
        case .weibo:
            await runWeibo(config.fields["accessToken"] ?? "")
        case .imessage:
            await runMessages(config.fields["handle"] ?? "")
        case .feishu:
            await runFeishu(appId: config.fields["appId"] ?? "", appSecret: config.fields["appSecret"] ?? "")
        case .wecom:
            await runWeCom(corpId: config.fields["corpId"] ?? "", secret: config.fields["agentSecret"] ?? "")
        case .line:
            await runLine(config.fields["channelToken"] ?? "")
        case .wechat:
            note(.wechat, "Personal WeChat has no official bot API. Paste the message below.", "个人微信没有官方机器人接口。把消息贴在下面。")
        }
    }

    private func runTelegram(_ token: String) async {
        var offset = 0
        var seeded = false
        note(.telegram, "Telegram is connecting.", "Telegram 正在连接。")
        while !Task.isCancelled {
            guard let url = IMLive.telegramURL(token: token, offset: offset) else {
                note(.telegram, "The Telegram token is not usable.", "Telegram 令牌不能用。")
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 35
            do {
                let data = try await pinnedData(request, host: "api.telegram.org")
                let parsed = IMLive.telegram(data: data, offset: offset)
                offset = parsed.offset
                if !seeded {
                    seeded = true
                    note(.telegram, "Telegram is listening. Older messages stay out.", "Telegram 在听。更早的消息不会送进去。")
                    continue
                }
                for event in parsed.events { await deliver(.telegram, event) }
            } catch {
                if Task.isCancelled { return }
                note(.telegram, "Telegram did not answer. Retrying.", "Telegram 没有响应。正在重试。")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func runMatrix(homeserver: String, token: String) async {
        var since = ""
        var seeded = false
        note(.matrix, "Matrix is connecting.", "Matrix 正在连接。")
        while !Task.isCancelled {
            guard let url = IMLive.matrixSyncURL(homeserver: homeserver, since: since), let host = url.host else {
                note(.matrix, "The Matrix homeserver must be an http or https origin.", "Matrix 服务器要是 http 或 https 地址。")
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let data = try await pinnedData(request, host: host)
                let parsed = IMLive.matrix(data: data)
                guard !parsed.next.isEmpty else {
                    note(.matrix, "Matrix did not return a sync cursor.", "Matrix 没有返回同步位置。")
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    continue
                }
                if !seeded {
                    since = parsed.next
                    seeded = true
                    note(.matrix, "Matrix is listening. The first sync stays out.", "Matrix 在听。第一次同步的旧消息不会送进去。")
                    continue
                }
                since = parsed.next
                for event in parsed.events { await deliver(.matrix, event) }
            } catch {
                if Task.isCancelled { return }
                note(.matrix, "Matrix did not answer. Retrying.", "Matrix 没有响应。正在重试。")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func runWeibo(_ token: String) async {
        var seen = Set<String>()
        var seeded = false
        note(.weibo, "Weibo is connecting.", "微博正在连接。")
        while !Task.isCancelled {
            guard let url = IMLive.weiboURL(token: token) else {
                note(.weibo, "The Weibo token is not usable.", "微博令牌不能用。")
                return
            }
            do {
                let data = try await pinnedData(URLRequest(url: url), host: "api.weibo.com")
                guard IMLive.weiboOK(data) else {
                    note(.weibo, "Weibo did not return messages. Retrying.", "微博没有返回私信。正在重试。")
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    continue
                }
                let events = IMLive.weibo(data: data)
                if !seeded {
                    seen = Set(events.map(\.id).filter { !$0.isEmpty })
                    seeded = true
                    note(.weibo, "Weibo is listening. Older messages stay out.", "微博在听。更早的私信不会送进去。")
                } else {
                    for event in events where !event.id.isEmpty && seen.insert(event.id).inserted {
                        await deliver(.weibo, event)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                note(.weibo, "Weibo did not answer. Retrying.", "微博没有响应。正在重试。")
            }
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    private func runDiscord(_ token: String) async {
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        note(.discord, "Discord is connecting.", "Discord 正在连接。")
        var delay: UInt64 = 2
        while !Task.isCancelled {
            switch await gatewayOnce(channel: .discord, url: url, identify: IMLive.discordIdentify(token: token), qq: false, host: "gateway.discord.gg") {
            case .rejected:
                note(.discord, "Discord rejected the session.", "Discord 拒绝了这次连接。")
                return
            case .stop:
                return
            case .retry:
                note(.discord, "Discord disconnected. Retrying.", "Discord 断开了。正在重试。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        }
    }

    private func runSlack(_ token: String) async {
        guard IMLive.slackUsesSocket(token) else {
            note(.slack, "Slack live needs an app-level token that starts with xapp-. A bot token cannot receive events here. Paste still works.", "Slack 实时需要以 xapp- 开头的应用级令牌。机器人令牌在这里收不到事件。仍可以粘贴。")
            return
        }
        note(.slack, "Slack is connecting.", "Slack 正在连接。")
        var delay: UInt64 = 2
        while !Task.isCancelled {
            guard let url = await slackSocket(token) else {
                if Task.isCancelled { return }
                note(.slack, "Slack did not open a socket. Check the app-level token.", "Slack 没有打开连接。检查应用级令牌。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
                continue
            }
            switch await slackOnce(url) {
            case .stop, .rejected:
                return
            case .retry:
                note(.slack, "Slack disconnected. Retrying.", "Slack 断开了。正在重试。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        }
    }

    private func slackSocket(_ token: String) async -> URL? {
        guard let url = URL(string: "https://slack.com/api/apps.connections.open") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let data = try await pinnedData(request, host: "slack.com")
            return IMLive.slackSocketURL(data: data)
        } catch {
            return nil
        }
    }

    private func slackOnce(_ url: URL) async -> LiveStep {
        guard let socket = openSocket(url, channel: .slack, hostSuffix: "slack.com") else { return .retry }
        note(.slack, "Slack is listening.", "Slack 在听。")
        defer { socket.cancel(with: .goingAway, reason: nil) }
        while !Task.isCancelled {
            do {
                let text = try await receiveText(socket)
                if let envelope = IMLive.slackEnvelopeID(text) {
                    try? await socket.send(.string(IMLive.slackAck(envelopeID: envelope)))
                }
                for event in IMLive.slackEvents(frame: text) { await deliver(.slack, event) }
            } catch {
                return Task.isCancelled ? .stop : .retry
            }
        }
        return .stop
    }

    private func runQQ(appId: String, secret: String) async {
        guard let gateway = URL(string: "wss://api.bot.qq.com/websocket/") else { return }
        note(.qq, "QQ is connecting.", "QQ 正在连接。")
        var delay: UInt64 = 2
        while !Task.isCancelled {
            guard let access = await qqAccess(appId: appId, secret: secret) else {
                if Task.isCancelled { return }
                note(.qq, "QQ did not issue a token.", "QQ 没有发访问令牌。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
                continue
            }
            switch await gatewayOnce(channel: .qq, url: gateway, identify: IMLive.qqIdentify(accessToken: access), qq: true, host: "api.bot.qq.com") {
            case .stop:
                return
            case .rejected:
                note(.qq, "QQ rejected the session. Check the bot's event subscriptions.", "QQ 拒绝了这次连接。检查机器人的事件订阅。")
                return
            case .retry:
                note(.qq, "QQ disconnected. Retrying.", "QQ 断开了。正在重试。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        }
    }

    private func qqAccess(appId: String, secret: String) async -> String? {
        guard let url = URL(string: "https://api.bot.qq.com/app/getAppAccessToken") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = IMLive.qqTokenBody(appId: appId, secret: secret)
        do {
            let data = try await pinnedData(request, host: "api.bot.qq.com")
            return IMLive.qqAccessToken(data: data)
        } catch {
            return nil
        }
    }

    private func runDingTalk(appKey: String, appSecret: String) async {
        note(.dingtalk, "DingTalk is connecting.", "钉钉正在连接。")
        var delay: UInt64 = 2
        while !Task.isCancelled {
            guard let url = await dingSocket(appKey: appKey, appSecret: appSecret) else {
                if Task.isCancelled { return }
                note(.dingtalk, "DingTalk did not open a connection.", "钉钉没有打开连接。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
                continue
            }
            switch await dingOnce(url) {
            case .stop, .rejected:
                return
            case .retry:
                note(.dingtalk, "DingTalk disconnected. Retrying.", "钉钉断开了。正在重试。")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        }
    }

    private func dingSocket(appKey: String, appSecret: String) async -> URL? {
        guard let url = URL(string: "https://api.dingtalk.com/v1.0/gateway/connections/open") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = IMLive.dingtalkOpenBody(appKey: appKey, appSecret: appSecret)
        do {
            let data = try await pinnedData(request, host: "api.dingtalk.com")
            return IMLive.dingtalkSocket(data: data)
        } catch {
            return nil
        }
    }

    private func dingOnce(_ url: URL) async -> LiveStep {
        guard let socket = openSocket(url, channel: .dingtalk, hostSuffix: "dingtalk.com") else { return .retry }
        note(.dingtalk, "DingTalk is listening.", "钉钉在听。")
        defer { socket.cancel(with: .goingAway, reason: nil) }
        while !Task.isCancelled {
            do {
                let text = try await receiveText(socket)
                let parsed = IMLive.dingtalk(frame: text)
                if !parsed.messageID.isEmpty {
                    try? await socket.send(.string(IMLive.dingtalkAck(messageID: parsed.messageID)))
                }
                for event in parsed.events { await deliver(.dingtalk, event) }
            } catch {
                return Task.isCancelled ? .stop : .retry
            }
        }
        return .stop
    }

    private func gatewayOnce(channel: IMChannel, url: URL, identify: String, qq: Bool, host: String) async -> LiveStep {
        guard let socket = openSocket(url, channel: channel, hostSuffix: host) else { return .retry }
        let seq = LiveSeq()
        var heart: Task<Void, Never>?
        defer {
            heart?.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }
        while !Task.isCancelled {
            do {
                let text = try await receiveText(socket)
                let frame = IMLive.gatewayFrame(text, qq: qq)
                if let value = frame.sequence { seq.value = value }
                if frame.op == 9 { return .rejected }
                if frame.op == 7 { return .retry }
                if frame.op == 10, heart == nil {
                    let interval = UInt64(max(frame.heartbeatMs, 10_000))
                    heart = Task { @MainActor in
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: interval * 1_000_000)
                            if Task.isCancelled { return }
                            try? await socket.send(.string(IMLive.gatewayHeartbeat(sequence: seq.value)))
                        }
                    }
                    try await socket.send(.string(identify))
                    note(channel, "\(channel.rawValue) is listening.", "\(Self.channelName(channel))在听。")
                }
                for event in frame.events { await deliver(channel, event) }
            } catch {
                return Task.isCancelled ? .stop : .retry
            }
        }
        return .stop
    }

    private func runFeishu(appId: String, appSecret: String) async {
        let urls = [
            "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
            "https://open.larksuite.com/open-apis/auth/v3/tenant_access_token/internal"
        ]
        for raw in urls {
            guard let url = URL(string: raw), let host = url.host else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = IMLive.feishuTokenBody(appId: appId, appSecret: appSecret)
            do {
                let data = try await pinnedData(request, host: host)
                if IMLive.feishuTokenOK(data: data) {
                    note(.feishu, "Feishu credentials are valid. The long connection is a private SDK protocol, so messages still paste.", "飞书凭证有效。长连接是私有协议，消息仍要粘贴。")
                    return
                }
            } catch {
                continue
            }
        }
        note(.feishu, "Feishu did not accept these credentials. Paste still works.", "飞书没有接受这组凭证。仍可以粘贴。")
    }

    private func runWeCom(corpId: String, secret: String) async {
        guard let url = IMLive.wecomTokenURL(corpId: corpId, secret: secret) else {
            note(.wecom, "The WeCom credentials are not usable.", "企业微信凭证不能用。")
            return
        }
        do {
            let data = try await pinnedData(URLRequest(url: url), host: "qyapi.weixin.qq.com")
            guard IMLive.wecomTokenOK(data: data) else {
                note(.wecom, "WeCom did not accept these credentials. Paste still works.", "企业微信没有接受这组凭证。仍可以粘贴。")
                return
            }
            wecomVerified = true
        } catch {
            note(.wecom, "WeCom did not answer. Paste still works.", "企业微信没有响应。仍可以粘贴。")
            return
        }
        let local = hookPort > 0 ? " http://127.0.0.1:\(hookPort)/wecom" : ""
        note(.wecom, "WeCom credentials are valid. There is no official pull. This Mac can read an unsigned callback on\(local). Paste still works.", "企业微信凭证有效。没有官方拉取接口。这台 Mac 可以在\(local)接收未签名回调。仍可以粘贴。")
    }

    private func runLine(_ token: String) async {
        guard let url = URL(string: "https://api.line.me/v2/bot/info") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let local = hookPort > 0 ? " http://127.0.0.1:\(hookPort)/line" : ""
        do {
            _ = try await pinnedData(request, host: "api.line.me")
            lineVerified = true
            note(.line, "LINE token is valid. LINE only pushes to a webhook. A signed POST can arrive on\(local). Cloud cannot reach this Mac by itself. Paste still works.", "LINE 令牌有效。LINE 只走 webhook。签名后的 POST 可以发到\(local)。云端到不了这台 Mac。仍可以粘贴。")
        } catch {
            note(.line, "LINE did not accept this token. Paste still works.", "LINE 没有接受这个令牌。仍可以粘贴。")
        }
    }

    private func runMessages(_ handle: String) async {
        let cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IMLive.imessageHandleOK(cleaned) else {
            note(.imessage, "The iMessage handle is not usable. Use * or a phone or email without quotes.", "iMessage 联系人不能用。填 *，或电话、邮箱，不要带引号。")
            return
        }
        note(.imessage, "Reading Messages on this Mac. Older messages stay out.", "正在读这台 Mac 上的信息。更早的消息不会送进去。")
        var seen = Set<String>()
        var seeded = false
        while !Task.isCancelled {
            let output = await Self.readMessages()
            if Task.isCancelled { return }
            guard let output else {
                note(.imessage, "Messages did not answer. Paste still works.", "信息没有响应。仍可以粘贴。")
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                continue
            }
            let events = IMLive.imessage(output: output, handle: cleaned)
            if !seeded {
                seen = Set(events.map(\.id).filter { !$0.isEmpty })
                seeded = true
            } else {
                for event in events where !event.id.isEmpty && seen.insert(event.id).inserted {
                    await deliver(.imessage, event)
                }
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }

    private func deliver(_ channel: IMChannel, _ event: IMLiveEvent) async {
        let sender = event.sender.isEmpty ? channel.rawValue : event.sender
        await model?.receiveBridge(text: event.text, channel: channel, sender: sender, quiet: true)
    }

    private func note(_ channel: IMChannel, _ en: String, _ zh: String) {
        noteKey(channel.rawValue, en, zh)
    }

    private func noteKey(_ key: String, _ en: String, _ zh: String) {
        model?.desk.bridgeNotes[key] = model?.copy.t(en, zh) ?? en
    }

    private func openSocket(_ url: URL, channel: IMChannel, hostSuffix: String) -> URLSessionWebSocketTask? {
        guard url.scheme == "wss", let host = url.host?.lowercased(), host == hostSuffix || host.hasSuffix(".\(hostSuffix)") else {
            return nil
        }
        let task = session.webSocketTask(with: url)
        sockets[channel] = task
        task.resume()
        return task
    }

    private func receiveText(_ task: URLSessionWebSocketTask) async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            return ""
        }
    }

    private func pinnedData(_ request: URLRequest, host: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let got = http.url?.host?.lowercased(),
              got == host.lowercased(),
              (200..<300).contains(http.statusCode)
        else { throw URLError(.badServerResponse) }
        return data
    }

    private func startHook() {
        let hook = LoopbackHook()
        hook.onReady = { [weak self] port in
            self?.hookPort = port
            self?.refreshHookNotes()
        }
        hook.onRequest = { [weak self] path, headers, body in
            self?.receiveHook(path: path, headers: headers, body: body)
        }
        hook.start()
        self.hook = hook
    }

    private func refreshHookNotes() {
        guard hookPort > 0 else { return }
        if lineOn && lineVerified {
            note(.line, "LINE accepts a signed webhook at http://127.0.0.1:\(hookPort)/line. Cloud cannot reach this Mac by itself. Paste still works.", "LINE 的签名 webhook 可以发到 http://127.0.0.1:\(hookPort)/line。云端到不了这台 Mac。仍可以粘贴。")
        }
        if wecomOn && wecomVerified {
            note(.wecom, "WeCom can post unsigned text to http://127.0.0.1:\(hookPort)/wecom. Paste still works.", "企业微信可以把未签名文字发到 http://127.0.0.1:\(hookPort)/wecom。仍可以粘贴。")
        }
    }

    private func receiveHook(path: String, headers: [String: String], body: Data) {
        if path == "/line", lineOn {
            let given = headers["x-line-signature"] ?? ""
            let expected = IMLive.lineSignature(secret: lineSecret, body: body)
            guard !lineSecret.isEmpty, Self.constantEqual(given, expected) else { return }
            for event in IMLive.lineEvents(data: body) {
                Task { await self.deliver(.line, event) }
            }
        } else if path == "/wecom", wecomOn, let xml = String(data: body, encoding: .utf8) {
            for event in IMLive.wecomEvents(xml: xml) {
                Task { await self.deliver(.wecom, event) }
            }
        }
    }

    private static func constantEqual(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8)
        let b = Array(right.utf8)
        guard a.count == b.count, !a.isEmpty else { return false }
        var diff: UInt8 = 0
        for index in a.indices { diff |= a[index] ^ b[index] }
        return diff == 0
    }

    private static func makeSession(delegate: URLSessionTaskDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func channelName(_ channel: IMChannel) -> String {
        switch channel {
        case .discord: return "Discord"
        case .qq: return "QQ"
        default: return channel.rawValue
        }
    }

    /// The handle is not interpolated. Swift filters the rows.
    private static func readMessages() async -> String? {
        let script = """
        on flatten(value)
            set junk to {character id 10, character id 13, character id 9}
            set text item delimiters to junk
            set parts to text items of (value as text)
            set text item delimiters to " "
            set cleaned to parts as text
            set text item delimiters to ""
            return cleaned
        end flatten
        set output to {}
        tell application "Messages"
            set chatCount to count of chats
            if chatCount > 12 then set chatCount to 12
            repeat with chatIndex from 1 to chatCount
                try
                    set aChat to chat chatIndex
                    set msgList to messages of aChat
                    set messageCount to count of msgList
                    set startIndex to messageCount - 2
                    if startIndex < 1 then set startIndex to 1
                    repeat with messageIndex from startIndex to messageCount
                        try
                            set aMessage to item messageIndex of msgList
                            set mid to id of aMessage as text
                            set body to my flatten(text of aMessage)
                            set who to ""
                            try
                                set who to handle of sender of aMessage as text
                            end try
                            if who is "" then
                                try
                                    set who to name of sender of aMessage as text
                                end try
                            end if
                            set who to my flatten(who)
                            set end of output to mid & tab & who & tab & body
                        end try
                    end repeat
                end try
            end repeat
        end tell
        set text item delimiters to linefeed
        return output as text
        """
        return await Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }.value
    }
}

private enum LiveStep {
    case stop
    case retry
    case rejected
}

private final class LiveSeq: @unchecked Sendable {
    var value: Int?
}

private final class RefuseRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class LoopbackHook: @unchecked Sendable {
    var onReady: (@MainActor (UInt16) -> Void)?
    var onRequest: (@MainActor (String, [String: String], Data) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "grok.bridge.hook")

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.read(connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            let ready = self?.onReady
            Task { @MainActor in ready?(port) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.count > 262_144 {
                self.respond(connection, ok: false)
                return
            }
            if let split = next.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(data: next.subdata(in: next.startIndex..<split.lowerBound), encoding: .utf8) ?? ""
                let length = self.contentLength(header)
                let bodyStart = split.upperBound
                let have = next.count - bodyStart
                if have >= length {
                    let bodyEnd = bodyStart + length
                    let body = next.subdata(in: bodyStart..<bodyEnd)
                    self.finish(connection, header: header, body: body)
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.read(connection, buffer: next)
        }
    }

    private func finish(_ connection: NWConnection, header: String, body: Data) {
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false)
        let parts = lines.first?.split(separator: " ") ?? []
        let method = parts.first.map(String.init) ?? ""
        let path = parts.dropFirst().first.map(String.init) ?? ""
        guard method == "POST", path == "/line" || path == "/wecom" else {
            respond(connection, ok: false)
            return
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let mark = line.firstIndex(of: ":") else { continue }
            let name = line[..<mark].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: mark)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let deliver = onRequest
        Task { @MainActor in deliver?(path, headers, body) }
        respond(connection, ok: true)
    }

    private func contentLength(_ header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private func respond(_ connection: NWConnection, ok: Bool) {
        let text = ok
            ? "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
            : "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
