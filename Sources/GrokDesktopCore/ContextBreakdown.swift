import Foundation

public struct ContextSlice: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var tokens: Int
    public var informational: Bool

    public init(id: String, title: String, tokens: Int, informational: Bool = false) {
        self.id = id
        self.title = title
        self.tokens = tokens
        self.informational = informational
    }
}

public struct ContextBreakdown: Equatable, Sendable {
    public var used: Int
    public var window: Int
    /// Window grok wrote for this session. 0 until signals.json reports one.
    public var measuredWindow: Int
    public var percent: Int
    public var messages: Int
    public var reasoning: Int
    public var tools: Int
    public var other: Int
    public var free: Int
    public var skillCount: Int
    public var mcpCount: Int
    public var toolCallCount: Int
    public var turnCount: Int
    public var model: String
    public var sessionID: String

    public init(
        used: Int = 0,
        window: Int = 0,
        measuredWindow: Int = 0,
        percent: Int = 0,
        messages: Int = 0,
        reasoning: Int = 0,
        tools: Int = 0,
        other: Int = 0,
        free: Int = 0,
        skillCount: Int = 0,
        mcpCount: Int = 0,
        toolCallCount: Int = 0,
        turnCount: Int = 0,
        model: String = "",
        sessionID: String = ""
    ) {
        self.used = used
        self.window = window
        self.measuredWindow = measuredWindow
        self.percent = percent
        self.messages = messages
        self.reasoning = reasoning
        self.tools = tools
        self.other = other
        self.free = free
        self.skillCount = skillCount
        self.mcpCount = mcpCount
        self.toolCallCount = toolCallCount
        self.turnCount = turnCount
        self.model = model
        self.sessionID = sessionID
    }

    public var slices: [ContextSlice] {
        [
            ContextSlice(id: "messages", title: "Messages", tokens: messages),
            ContextSlice(id: "reasoning", title: "Reasoning", tokens: reasoning),
            ContextSlice(id: "tools", title: "Tools", tokens: tools),
            ContextSlice(id: "other", title: "System / overhead", tokens: other),
            ContextSlice(id: "free", title: "Free", tokens: free)
        ]
    }

    public static func estimateTokens(_ text: String) -> Int {
        max(text.count / 4, text.isEmpty ? 0 : 1)
    }

    public static func make(
        items: [ConversationItem],
        sessionDirectory: URL?,
        skillCount: Int,
        mcpCount: Int,
        model: String,
        sessionID: String,
        knownWindow: Int = 0
    ) -> ContextBreakdown {
        var messages = 0
        var reasoning = 0
        var tools = 0
        var toolCallCount = 0
        var turnCount = 0
        for item in items {
            switch item {
            case .user(_, let text), .assistant(_, let text, _):
                if case .user = item { turnCount += 1 }
                messages += estimateTokens(text)
            case .thought(_, let text):
                reasoning += estimateTokens(text)
            case .tool(_, let title, _, let detail):
                toolCallCount += 1
                tools += estimateTokens(title + "\n" + detail)
            case .notice(_, let text):
                messages += estimateTokens(text)
            }
        }
        let estimated = messages + reasoning + tools
        var used = estimated
        var window = max(knownWindow, 0)
        var measuredWindow = 0
        var percent = 0
        if let sessionDirectory {
            let signals = sessionDirectory.appendingPathComponent("signals.json")
            if let data = try? Data(contentsOf: signals),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                used = max(jsonInt(object["contextTokensUsed"]), estimated)
                let signaledWindow = jsonInt(object["contextWindowTokens"])
                if signaledWindow > 0 {
                    measuredWindow = signaledWindow
                    window = signaledWindow
                }
                percent = jsonInt(object["contextWindowUsage"])
                let turns = jsonInt(object["turnCount"])
                if turns > 0 { turnCount = turns }
                if object["toolCallCount"] != nil { toolCallCount = jsonInt(object["toolCallCount"]) }
            }
        }
        if percent == 0, window > 0 {
            percent = min(100, Int((Double(used) / Double(window) * 100).rounded()))
        }
        let accounted = min(estimated, used)
        let other = max(used - accounted, 0)
        let free = window > 0 ? max(window - used, 0) : 0
        return ContextBreakdown(
            used: used,
            window: window,
            measuredWindow: measuredWindow,
            percent: percent,
            messages: messages,
            reasoning: reasoning,
            tools: tools,
            other: other,
            free: free,
            skillCount: skillCount,
            mcpCount: mcpCount,
            toolCallCount: toolCallCount,
            turnCount: turnCount,
            model: model,
            sessionID: sessionID
        )
    }

    /// `contextWindowTokens` from a session's signals file. 0 when the file has none.
    public static func signaledWindow(in directory: URL?) -> Int {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("signals.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        return jsonInt(object["contextWindowTokens"])
    }

    private static func jsonInt(_ raw: Any?) -> Int {
        let number: Double
        if let value = raw as? Int {
            number = Double(value)
        } else if let value = raw as? NSNumber {
            number = value.doubleValue
        } else {
            return 0
        }
        guard number.isFinite, number > 0, number < Double(Int.max) else { return 0 }
        return Int(number.rounded())
    }
}

public struct ContextWindowRewrite: Equatable, Sendable {
    public var sessionID: String
    public var previous: Int
    public var current: Int

    public init(sessionID: String, previous: Int, current: Int) {
        self.sessionID = sessionID
        self.previous = previous
        self.current = current
    }

    public var key: String { "\(sessionID):\(previous):\(current)" }

    /// Resume replaced the window stored for this session with a smaller one.
    public static func detect(sessionID: String, previous: Int, current: Int) -> ContextWindowRewrite? {
        guard !sessionID.isEmpty, previous > current, current > 0 else { return nil }
        return ContextWindowRewrite(sessionID: sessionID, previous: previous, current: current)
    }

    public func message(chinese: Bool) -> String {
        let from = PromptTimestamp.compactCount(previous)
        let to = PromptTimestamp.compactCount(current)
        if chinese {
            return "这条会话原来按 \(from) 计。恢复时窗口改成了 \(to)，自动压缩也会更早。占用没有变多。"
        }
        return "This session was counted against \(from). Resume rewrote the window to \(to), so auto-compact starts sooner. Usage itself did not jump."
    }
}
