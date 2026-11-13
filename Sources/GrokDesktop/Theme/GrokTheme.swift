import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        case .system: return "系统模式"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

struct Palette: Equatable {
    var isDark: Bool

    // Surfaces
    var canvas: Color { isDark ? Color(hex: 0x0A0A0C) : Color(hex: 0xFFFFFF) }
    var sidebar: Color { isDark ? Color(hex: 0x101013) : Color(hex: 0xF7F7F8) }
    var surface: Color { isDark ? Color(hex: 0x141418) : Color(hex: 0xFAFAFB) }
    var elevated: Color { isDark ? Color(hex: 0x18181C) : Color(hex: 0xFFFFFF) }
    var input: Color { isDark ? Color(hex: 0x151519) : Color(hex: 0xF8F8FA) }
    var inputFocused: Color { isDark ? Color(hex: 0x19191E) : Color(hex: 0xFFFFFF) }
    var popover: Color { isDark ? Color(hex: 0x18181C) : Color(hex: 0xFFFFFF) }
    var codeHeader: Color { isDark ? Color(hex: 0x1A1A20) : Color(hex: 0xF2F2F5) }

    // Borders & Focus
    var hairline: Color { Color.primary.opacity(isDark ? 0.10 : 0.08) }
    var borderStrong: Color { Color.primary.opacity(isDark ? 0.22 : 0.16) }
    var focusRing: Color { Color.primary.opacity(isDark ? 0.28 : 0.20) }

    // Text
    var text: Color { isDark ? Color(white: 0.95) : Color(hex: 0x111114) }
    var secondary: Color { isDark ? Color(hex: 0x9898A2) : Color(hex: 0x63636B) }
    var tertiary: Color { isDark ? Color(hex: 0x686873) : Color(hex: 0x8E8E98) }

    // Interactive states
    var chip: Color { Color.primary.opacity(isDark ? 0.075 : 0.05) }
    var hover: Color { Color.primary.opacity(isDark ? 0.06 : 0.045) }
    var selected: Color { Color.primary.opacity(isDark ? 0.11 : 0.08) }

    // Conversation & Actions
    var promptBubble: Color { isDark ? Color(hex: 0x1C1C21) : Color(hex: 0xF2F2F5) }
    var promptBubbleBorder: Color { Color.primary.opacity(isDark ? 0.11 : 0.07) }
    var promptBubbleText: Color { isDark ? Color(white: 0.95) : Color(hex: 0x111114) }
    var send: Color { isDark ? Color(white: 0.95) : Color(hex: 0x141417) }
    var sendGlyph: Color { isDark ? Color(hex: 0x0E0E11) : Color.white }
    var overlay: Color { Color.black.opacity(isDark ? 0.62 : 0.28) }

    // Semantic accents
    var success: Color { isDark ? Color(hex: 0x34D399) : Color(hex: 0x15803D) }
    var warning: Color { isDark ? Color(hex: 0xF59E0B) : Color(hex: 0xD97706) }
    var danger: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xDC2626) }
    var info: Color { isDark ? Color(hex: 0x60A5FA) : Color(hex: 0x2563EB) }
    var avatarFill: Color { isDark ? Color(hex: 0x26262C) : Color(hex: 0x1F1F24) }

    static func resolve(preference: AppearancePreference, system: ColorScheme) -> Palette {
        switch preference {
        case .light: return Palette(isDark: false)
        case .dark: return Palette(isDark: true)
        case .system: return Palette(isDark: system == .dark)
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(isDark: false)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum InspectorPane: String, CaseIterable, Identifiable {
    case context
    case work
    case terminals
    case changes
    case hooks
    case aside
    case shell

    var id: String { rawValue }

    /// The shell stays closed until someone turns it on. It is not part of the rail by default.
    static let closedUntilChosen: Set<String> = [InspectorPane.shell.rawValue]

    func title(chinese: Bool) -> String {
        switch self {
        case .context: return chinese ? "上下文" : "Context"
        case .work: return chinese ? "任务" : "Tasks"
        case .terminals: return chinese ? "代理命令" : "Agent commands"
        case .changes: return chinese ? "变更" : "Changes"
        case .hooks: return chinese ? "钩子" : "Hooks"
        case .aside: return chinese ? "顺便问" : "Aside"
        case .shell: return chinese ? "终端" : "Terminal"
        }
    }
}

enum InspectorFocus: String, CaseIterable, Identifiable {
    case changes
    case preview
    case terminal
    case aside

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .changes: return "chevron.left.forwardslash.chevron.right"
        case .preview: return "eye"
        case .terminal: return "terminal"
        case .aside: return "text.bubble"
        }
    }

    func title(chinese: Bool) -> String {
        switch self {
        case .changes: return chinese ? "变更" : "Changes"
        case .preview: return chinese ? "预览" : "Preview"
        case .terminal: return chinese ? "终端" : "Terminal"
        case .aside: return chinese ? "顺便问" : "Aside"
        }
    }
}

enum GrokTheme {
    static let contentWidth: CGFloat = 700
    static let sidebarWidth: CGFloat = 260
    static let collapsedSidebarWidth: CGFloat = 60
    static let inspectorWidth: CGFloat = 320
    static let shellHeight: CGFloat = 220
    static let shellMinHeight: CGFloat = 140
    static let shellMaxHeight: CGFloat = 520
    static let inspectorMinWidth: CGFloat = 240
    static let inspectorMaxWidth: CGFloat = 720
    static let inspectorPreviewWidth: CGFloat = 420
    static let inputRadius: CGFloat = 20
    static let bubbleMaxWidth: CGFloat = 540

    static func chatBodySize(compact: Bool) -> CGFloat { compact ? 13 : 14 }
    static func chatBubbleSize(compact: Bool) -> CGFloat { compact ? 13 : 14 }
    static func chatCodeSize(compact: Bool) -> CGFloat { compact ? 11.5 : 12.5 }
    static func chatMetaSize(compact: Bool) -> CGFloat { compact ? 11 : 12 }
    static func chatToolSize(compact: Bool) -> CGFloat { compact ? 12 : 12.5 }
    static func chatRowSpacing(compact: Bool) -> CGFloat { compact ? 10 : 20 }
    static func chatBlockSpacing(compact: Bool) -> CGFloat { compact ? 8 : 12 }
    static let chatLineHeight: CGFloat = 1.42
    static let chatParagraphSpacing: CGFloat = 6

    static func chatHeadingSize(level: Int, compact: Bool) -> CGFloat {
        let body = chatBodySize(compact: compact)
        switch max(1, min(level, 3)) {
        case 1: return body + 4.5
        case 2: return body + 2.5
        default: return body + 1
        }
    }

    static func clampInspectorWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, inspectorMinWidth), inspectorMaxWidth)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
