import Foundation

public enum CompanionPhase: String, Equatable, Sendable {
    case idle
    case working
    case needsInput
    case done
}

public enum CompanionIntent: Equatable, Sendable {
    case dictate(String)
    case send
    case stop
}

public enum CompanionEffect: Equatable, Sendable {
    case draft(String)
    case send(String)
    case stop
    case ignore
}

public enum CompanionDesk {
    public static func phase(
        turnRunning: Bool,
        needsPermission: Bool,
        needsQuestion: Bool,
        unseen: Bool
    ) -> CompanionPhase {
        if needsPermission || needsQuestion { return .needsInput }
        if turnRunning { return .working }
        if unseen { return .done }
        return .idle
    }

    public static func apply(_ intent: CompanionIntent, draft: String, turnRunning: Bool) -> CompanionEffect {
        switch intent {
        case .dictate(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignore }
            let next = draft.isEmpty ? trimmed : draft + " " + trimmed
            return .draft(next)
        case .send:
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignore }
            return .send(trimmed)
        case .stop:
            return turnRunning ? .stop : .ignore
        }
    }
}
