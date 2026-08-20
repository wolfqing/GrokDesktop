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

    var canvas: Color { isDark ? Color(hex: 0x000000) : Color.white }
    var sidebar: Color { isDark ? Color(hex: 0x0B0B0B) : Color(red: 0.973, green: 0.973, blue: 0.973) }
    var elevated: Color { isDark ? Color(white: 0.11) : Color.white }
    var input: Color { isDark ? Color(hex: 0x161616) : Color(white: 0.965) }
    var hairline: Color { Color.primary.opacity(isDark ? 0.12 : 0.08) }
    var text: Color { isDark ? Color(white: 0.96) : Color(white: 0.08) }
    var secondary: Color { isDark ? Color(white: 0.58) : Color(white: 0.40) }
    var chip: Color { Color.primary.opacity(isDark ? 0.08 : 0.055) }
    var selected: Color { isDark ? Color.white.opacity(0.08) : Color(white: 0.91) }
    var send: Color { isDark ? Color.white : Color.black }
    var sendGlyph: Color { isDark ? Color.black : Color.white }
    var overlay: Color { Color.black.opacity(isDark ? 0.55 : 0.22) }
    var popover: Color { isDark ? Color(white: 0.12) : Color.white }

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
    case workflows
    case personas

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .context: return chinese ? "上下文" : "Context"
        case .work: return chinese ? "任务" : "Tasks"
        case .terminals: return chinese ? "终端" : "Terminals"
        case .changes: return chinese ? "变更" : "Changes"
        case .workflows: return chinese ? "工作流" : "Workflows"
        case .personas: return chinese ? "人设" : "Personas"
        }
    }
}

enum GrokTheme {
    static let contentWidth: CGFloat = 680
    static let sidebarWidth: CGFloat = 260
    static let collapsedSidebarWidth: CGFloat = 64
    static let inspectorWidth: CGFloat = 320
    static let inspectorMinWidth: CGFloat = 240
    static let inspectorMaxWidth: CGFloat = 720
    static let inspectorPreviewWidth: CGFloat = 420
    static let inputRadius: CGFloat = 28
    static let bubbleMaxWidth: CGFloat = 520

    static func chatBodySize(compact: Bool) -> CGFloat { compact ? 13 : 14 }
    static func chatBubbleSize(compact: Bool) -> CGFloat { compact ? 13 : 14 }
    static func chatCodeSize(compact: Bool) -> CGFloat { compact ? 11.5 : 12.5 }
    static func chatMetaSize(compact: Bool) -> CGFloat { compact ? 11 : 12 }
    static func chatToolSize(compact: Bool) -> CGFloat { compact ? 12 : 12.5 }
    static func chatRowSpacing(compact: Bool) -> CGFloat { compact ? 8 : 20 }
    static func chatBlockSpacing(compact: Bool) -> CGFloat { compact ? 8 : 12 }
    static let chatLineHeight: CGFloat = 1.32
    static let chatParagraphSpacing: CGFloat = 4

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
