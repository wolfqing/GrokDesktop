import SwiftUI

enum GrokTheme {
    static let canvas = Color(red: 0, green: 0, blue: 0)
    static let sidebar = Color(red: 0.043, green: 0.043, blue: 0.043)
    static let elevated = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let input = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let hairline = Color.white.opacity(0.10)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let secondary = Color(red: 0.54, green: 0.54, blue: 0.54)
    static let chip = Color.white.opacity(0.06)
    static let contentWidth: CGFloat = 760
    static let sidebarWidth: CGFloat = 268
    static let inspectorWidth: CGFloat = 320
}
