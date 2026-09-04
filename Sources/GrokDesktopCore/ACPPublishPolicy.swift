import Foundation

public enum ACPPublishPolicy {
    public static let coalescedIntervalNanoseconds: UInt64 = 50_000_000

    public static func needsImmediatePublish(method: String?, kind: SessionUpdateKind? = nil) -> Bool {
        if let method {
            if UserQuestionRequest.isMethod(method) { return true }
            switch method {
            case "session/request_permission":
                return true
            case "session/update", "_x.ai/session/update":
                break
            default:
                if method.hasPrefix("fs/") || method.hasPrefix("terminal/") {
                    return true
                }
                if kind == nil { return true }
            }
        }
        switch kind {
        case .agentMessageChunk, .agentThoughtChunk, .toolCallUpdate:
            return false
        default:
            return true
        }
    }

    public static func shouldRecordEvent(method: String?, kind: SessionUpdateKind? = nil) -> Bool {
        needsImmediatePublish(method: method, kind: kind)
    }
}
