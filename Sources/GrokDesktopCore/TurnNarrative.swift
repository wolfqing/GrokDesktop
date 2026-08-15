import Foundation

public struct TurnStory: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case working
        case stopping
        case done
    }

    public var goal: String
    public var step: String
    public var nextStep: String?
    public var files: [String]
    public var done: Int
    public var total: Int
    public var phase: Phase

    public init(
        goal: String,
        step: String,
        nextStep: String? = nil,
        files: [String] = [],
        done: Int = 0,
        total: Int = 0,
        phase: Phase
    ) {
        self.goal = goal
        self.step = step
        self.nextStep = nextStep
        self.files = files
        self.done = done
        self.total = total
        self.phase = phase
    }
}

public enum TurnNarrative {
    public static func story(
        items: [ConversationItem],
        todos: [AgentTodo],
        hunks: [FileHunk],
        chinese: Bool,
        running: Bool,
        stopping: Bool
    ) -> TurnStory? {
        let activeTodo = todos.first(where: \.isActive)
        let runningTool = items.reversed().compactMap { item -> String? in
            guard case .tool(_, let title, let status, _) = item else { return nil }
            guard ToolVoice.isActive(status) else { return nil }
            if ToolVoice.kind(title) == .todo { return nil }
            return ToolVoice.headline(title, chinese: chinese)
        }.first

        let phase: TurnStory.Phase
        if stopping {
            phase = .stopping
        } else if running || activeTodo != nil || runningTool != nil {
            phase = .working
        } else {
            return nil
        }

        let progress = PromptTimestamp.progress(for: todos)
        let step: String
        if stopping {
            step = chinese ? "正在停止" : "Stopping"
        } else if let activeTodo {
            step = activeTodo.content
        } else if let runningTool {
            step = runningTool
        } else {
            step = chinese ? "在想" : "Thinking"
        }

        return TurnStory(
            goal: lastUserGoal(in: items) ?? "",
            step: step,
            nextStep: todos.first(where: { $0.status == "pending" })?.content,
            files: changedFiles(items: items, hunks: hunks),
            done: progress.done,
            total: progress.total,
            phase: phase
        )
    }

    public static func fileNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_\-./]+\.[A-Za-z0-9]{1,8}"#) else {
            return []
        }
        let ns = text as NSString
        var names: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token.hasPrefix("http") { continue }
            let name = URL(fileURLWithPath: token).lastPathComponent
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    private static func lastUserGoal(in items: [ConversationItem]) -> String? {
        guard let last = items.last(where: { if case .user = $0 { return true }; return false }) else {
            return nil
        }
        guard case .user(_, let text) = last else { return nil }
        let shown = PromptMedia.displayText(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if shown.isEmpty { return nil }
        if shown.count <= 80 { return shown }
        return String(shown.prefix(79)) + "…"
    }

    private static func changedFiles(items: [ConversationItem], hunks: [FileHunk]) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let name = URL(fileURLWithPath: raw).lastPathComponent
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            names.append(name)
        }
        let lastUser = items.lastIndex(where: { if case .user = $0 { return true }; return false }) ?? 0
        for item in items.suffix(from: lastUser) {
            if case .tool(_, let title, let status, _) = item {
                let lower = title.lowercased()
                let looksLikeEdit = lower.contains("edit") || lower.contains("write") || lower.contains("replace") || lower.contains("patch")
                if looksLikeEdit || status == "completed" {
                    fileNames(in: title).forEach(add)
                }
            }
        }
        for hunk in hunks {
            add(hunk.path)
        }
        return names
    }
}
