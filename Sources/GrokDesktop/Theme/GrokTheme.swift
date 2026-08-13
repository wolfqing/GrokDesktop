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

    var canvas: Color { isDark ? Color(white: 0.02) : Color.white }
    var sidebar: Color { isDark ? Color(white: 0.06) : Color(red: 0.973, green: 0.973, blue: 0.973) }
    var elevated: Color { isDark ? Color(white: 0.11) : Color.white }
    var input: Color { isDark ? Color(white: 0.10) : Color(white: 0.965) }
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

enum GrokTheme {
    static let contentWidth: CGFloat = 720
    static let sidebarWidth: CGFloat = 268
    static let collapsedSidebarWidth: CGFloat = 64
    static let inspectorWidth: CGFloat = 320
}
