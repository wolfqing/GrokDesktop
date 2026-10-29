import Foundation

public enum InspectorTool: String, Sendable, Equatable, CaseIterable {
    case changes
    case preview
    case terminal
    case aside
    case context
    case tasks
    case commands
    case hooks
}

public struct InspectorToolState: Equatable, Sendable {
    public var tool: InspectorTool?
    public var focused: Bool

    public init(tool: InspectorTool? = nil, focused: Bool = false) {
        self.tool = tool
        self.focused = focused
    }
}

public struct InspectorToolToggleResult: Equatable, Sendable {
    public var columnVisible: Bool
    public var state: InspectorToolState

    public init(columnVisible: Bool, state: InspectorToolState) {
        self.columnVisible = columnVisible
        self.state = state
    }
}

public enum InspectorToolAction: Equatable, Sendable {
    case toggle(InspectorTool)
    case close
    case focusLeft
    case focusPane
}

public enum InspectorToolToggle {
    /// Closed opens. Open while the conversation has the look only focuses. Open and looked-at closes.
    /// A hidden column always opens onto the tool. Closing a tool leaves the column up.
    public static func toggle(
        columnVisible: Bool,
        state: InspectorToolState,
        tool: InspectorTool
    ) -> InspectorToolToggleResult {
        if !columnVisible {
            return InspectorToolToggleResult(
                columnVisible: true,
                state: InspectorToolState(tool: tool, focused: true)
            )
        }
        return InspectorToolToggleResult(
            columnVisible: true,
            state: next(state, .toggle(tool))
        )
    }

    public static func next(_ state: InspectorToolState, _ action: InspectorToolAction) -> InspectorToolState {
        switch action {
        case .toggle(let tool):
            if state.tool != tool || !state.focused {
                return InspectorToolState(tool: tool, focused: true)
            }
            return InspectorToolState(tool: nil, focused: false)
        case .close:
            return InspectorToolState(tool: nil, focused: false)
        case .focusLeft:
            return InspectorToolState(tool: state.tool, focused: false)
        case .focusPane:
            guard state.tool != nil else {
                return InspectorToolState(tool: nil, focused: false)
            }
            return InspectorToolState(tool: state.tool, focused: true)
        }
    }

    /// Pressed follows the open tool. Focus is separate. Empty changes stay unpressed.
    public static func pressed(tool: InspectorTool, state: InspectorToolState, changesEmpty: Bool) -> Bool {
        guard state.tool == tool else { return false }
        if tool == .changes, changesEmpty { return false }
        return true
    }
}
