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
        sessionID: String
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
        var window = 200_000
        var percent = 0
        if let sessionDirectory {
            let signals = sessionDirectory.appendingPathComponent("signals.json")
            if let data = try? Data(contentsOf: signals),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let signaled = object["contextTokensUsed"] as? Int ?? 0
                used = max(signaled, estimated)
                window = object["contextWindowTokens"] as? Int ?? window
                percent = object["contextWindowUsage"] as? Int ?? 0
                if let turns = object["turnCount"] as? Int, turns > 0 { turnCount = turns }
                if let calls = object["toolCallCount"] as? Int { toolCallCount = calls }
            }
        }
        if window <= 0 { window = 200_000 }
        if percent == 0, window > 0 {
            percent = min(100, Int((Double(used) / Double(window) * 100).rounded()))
        }
        let accounted = min(estimated, used)
        let other = max(used - accounted, 0)
        let free = max(window - used, 0)
        return ContextBreakdown(
            used: used,
            window: window,
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
}
