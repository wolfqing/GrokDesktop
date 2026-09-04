import Foundation

public enum ChatDisplayRow: Equatable, Identifiable, Sendable {
    case message(ConversationItem)
    case stream(id: String, items: [ConversationItem])

    public var id: String {
        switch self {
        case .message(let item):
            return item.id
        case .stream(let id, _):
            return id
        }
    }
}

public enum ChatStreamPiece: Equatable, Identifiable, Sendable {
    case tools(id: String, items: [ConversationItem])
    case item(ConversationItem)

    public var id: String {
        switch self {
        case .tools(let id, _):
            return id
        case .item(let item):
            return item.id
        }
    }
}

public enum ChatDisplay {
    public static func streamID(for items: [ConversationItem]) -> String {
        "stream-\(items.first?.id ?? "empty")"
    }

    public static func toolClusterID(for items: [ConversationItem]) -> String {
        "tools-\(items.first?.id ?? "empty")"
    }

    public static func rows(
        items: [ConversationItem],
        hideAsides: Bool = true,
        showThinking: Bool = true,
        skipTodoTools: Bool = true
    ) -> [ChatDisplayRow] {
        var rows: [ChatDisplayRow] = []
        var pending: [ConversationItem] = []
        var asideTurn = false
        let hasMainUser = items.contains { item in
            if case .user(_, let text) = item { return !SessionFold.isAside(text) }
            return false
        }

        func flush() {
            guard !pending.isEmpty else { return }
            rows.append(.stream(id: streamID(for: pending), items: pending))
            pending = []
        }

        for item in items {
            if case .user(_, let text) = item {
                asideTurn = SessionFold.isAside(text)
            }
            if hideAsides, hasMainUser, asideTurn { continue }
            if case .thought = item, !showThinking { continue }
            if skipTodoTools, isTodoTool(item) { continue }
            switch item {
            case .user, .assistant:
                flush()
                rows.append(.message(item))
            default:
                pending.append(item)
            }
        }
        flush()
        return rows
    }

    public static func streamPieces(
        _ items: [ConversationItem],
        mergeTools: Bool
    ) -> [ChatStreamPiece] {
        var pieces: [ChatStreamPiece] = []
        var pending: [ConversationItem] = []

        func flush() {
            guard !pending.isEmpty else { return }
            pieces.append(.tools(id: toolClusterID(for: pending), items: pending))
            pending = []
        }

        for item in items {
            if case .tool(_, let title, let status, _) = item,
               canMerge(title: title, status: status, onto: pending, mergeTools: mergeTools) {
                pending.append(item)
            } else {
                flush()
                if case .tool(_, let title, let status, _) = item,
                   mergeTools,
                   !ToolVoice.isActive(status),
                   ToolVoice.foldsInVerbGroup(title) {
                    pending = [item]
                } else {
                    pieces.append(.item(item))
                }
            }
        }
        flush()
        return pieces
    }

    private static func canMerge(
        title: String,
        status: String,
        onto pending: [ConversationItem],
        mergeTools: Bool
    ) -> Bool {
        guard mergeTools else { return false }
        guard !ToolVoice.isActive(status), ToolVoice.foldsInVerbGroup(title) else { return false }
        guard let last = pending.last else { return true }
        guard case .tool(_, let previousTitle, let previousStatus, _) = last else { return false }
        guard !ToolVoice.isActive(previousStatus) else { return false }
        return ToolVoice.foldsInVerbGroup(previousTitle)
    }

    private static func isTodoTool(_ item: ConversationItem) -> Bool {
        guard case .tool(_, let title, _, _) = item else { return false }
        return ToolVoice.kind(title) == .todo
    }
}
