import Foundation

public enum InspectorFocusChoice: String, Sendable, Equatable {
    case changes
    case tasks
    case commands
    case hooks
    case shell
    case preview
}

public enum InspectorAttention {
    /// One surface at a time. A tab the user clicked stays selected. Otherwise follow the work:
    /// a plan waiting for approval, then files that changed, then a command, then the task list.
    public static func choose(
        pinned: InspectorFocusChoice?,
        available: [InspectorFocusChoice],
        planNeedsApproval: Bool,
        hasChanges: Bool,
        hasCommands: Bool,
        hasWork: Bool
    ) -> InspectorFocusChoice? {
        if let pinned, available.contains(pinned) {
            return pinned
        }
        let preferred: [InspectorFocusChoice]
        if planNeedsApproval {
            preferred = [.tasks, .changes, .commands, .preview, .shell, .hooks]
        } else if hasChanges {
            preferred = [.changes, .tasks, .commands, .preview, .shell, .hooks]
        } else if hasCommands {
            preferred = [.commands, .tasks, .changes, .preview, .shell, .hooks]
        } else if hasWork {
            preferred = [.tasks, .changes, .commands, .preview, .shell, .hooks]
        } else {
            preferred = [.changes, .tasks, .commands, .preview, .shell, .hooks]
        }
        return preferred.first { available.contains($0) }
    }
}
