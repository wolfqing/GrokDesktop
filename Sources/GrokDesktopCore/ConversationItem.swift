import Foundation

public enum ConversationItem: Identifiable, Hashable, Sendable {
    case user(id: String, text: String)
    case assistant(id: String, text: String, done: Bool)
    case thought(id: String, text: String)
    case tool(id: String, title: String, status: String, detail: String)
    case notice(id: String, text: String)

    public var id: String {
        switch self {
        case .user(let id, _), .assistant(let id, _, _), .thought(let id, _), .tool(let id, _, _, _), .notice(let id, _):
            return id
        }
    }
}
