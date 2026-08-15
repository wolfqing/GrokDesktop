import Foundation

public struct QueuedPrompt: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var kind: Kind

    public enum Kind: String, Sendable {
        case followUp
        case aside
    }

    public init(id: String = UUID().uuidString, text: String, kind: Kind) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var items: [ConversationItem] = []
    public var planEntries: [PlanEntry] = []
    public var itemDates: [String: Date] = [:]
    public var itemImages: [String: [URL]] = [:]
    public var todos: [AgentTodo] = []
    public var tasks: [AgentTask] = []
    public var assistantID: String?
    public var thoughtID: String?
    public var recap: String = ""
    public var compacted: Bool = false

    public init() {}

    public var lastUserPreview: String {
        items.reversed().compactMap { item -> String? in
            guard case .user(_, let text) = item else { return nil }
            let shown = TranscriptLoader.displayUserText(text)
            return shown.isEmpty ? nil : shown
        }.first ?? ""
    }
}

public enum SessionFold {
    public static func userTurn(_ text: String, at date: Date = Date()) -> SessionUpdate {
        SessionUpdate(
            kind: .userMessageChunk,
            text: text,
            timestamp: date,
            imageURLs: PromptMedia.imageURLs(in: text)
        )
    }

    public static func notice(_ text: String, at date: Date = Date()) -> SessionUpdate {
        SessionUpdate(kind: .notice, text: text, timestamp: date)
    }

    public static func apply(_ update: SessionUpdate, onto snapshot: inout SessionSnapshot) {
        TranscriptLoader.apply(
            update: update,
            items: &snapshot.items,
            planEntries: &snapshot.planEntries,
            assistantID: &snapshot.assistantID,
            thoughtID: &snapshot.thoughtID,
            itemDates: &snapshot.itemDates,
            itemImages: &snapshot.itemImages,
            todos: &snapshot.todos,
            tasks: &snapshot.tasks
        )
        switch update.kind {
        case .sessionRecap:
            let summary = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty { snapshot.recap = summary }
        case .autoCompactCompleted:
            snapshot.compacted = true
        default:
            break
        }
    }

    public static func isAside(_ text: String) -> Bool {
        SlashBuiltins.name(in: text) == "/btw"
    }

    public static func apply(_ updates: [SessionUpdate]) -> SessionSnapshot {
        var snapshot = SessionSnapshot()
        for update in updates {
            apply(update, onto: &snapshot)
        }
        return snapshot
    }
}

public extension SessionWorkspace {
    func fold(_ update: SessionUpdate) {
        TranscriptLoader.apply(
            update: update,
            items: &items,
            planEntries: &planEntries,
            assistantID: &assistantBufferID,
            thoughtID: &thoughtBufferID,
            itemDates: &itemDates,
            itemImages: &itemImages,
            todos: &todos,
            tasks: &tasks
        )
    }
}
