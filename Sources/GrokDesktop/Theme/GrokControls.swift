import SwiftUI

struct GrokHoverBackground: ViewModifier {
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat = 8
    var selected: Bool = false
    var activeFill: Color? = nil

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                fillColor,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var fillColor: Color {
        if selected {
            return activeFill ?? palette.selected
        }
        return hovering ? palette.hover : .clear
    }
}

struct GrokFieldChrome: ViewModifier {
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat = 10
    var focused: Bool = false

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                focused ? palette.inputFocused : palette.input,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        focused ? palette.focusRing : (hovering ? palette.borderStrong : palette.hairline),
                        lineWidth: 1
                    )
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: focused)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct GrokCardChrome: ViewModifier {
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat = 14
    var interactive: Bool = false

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                interactive && hovering ? palette.elevated : palette.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        interactive && hovering ? palette.borderStrong : palette.hairline,
                        lineWidth: 1
                    )
            )
            .onHover { if interactive { hovering = $0 } }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

extension View {
    func grokHover(cornerRadius: CGFloat = 8, selected: Bool = false) -> some View {
        modifier(GrokHoverBackground(cornerRadius: cornerRadius, selected: selected))
    }

    func grokFieldChrome(cornerRadius: CGFloat = 10, focused: Bool = false) -> some View {
        modifier(GrokFieldChrome(cornerRadius: cornerRadius, focused: focused))
    }

    func grokCard(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        modifier(GrokCardChrome(cornerRadius: cornerRadius, interactive: interactive))
    }
}

struct GrokIconButton: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 12.5
    var selected: Bool = false
    var cornerRadius: CGFloat = 8
    var helpText: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(selected || hovering ? palette.text : palette.secondary)
                .frame(width: size, height: size)
                .background(
                    selected ? palette.selected : (hovering ? palette.hover : .clear),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)

        if let helpText, !helpText.isEmpty {
            button
                .help(helpText)
                .accessibilityLabel(helpText)
        } else {
            button
        }
    }
}

struct GrokAvatar: View {
    @Environment(\.palette) private var palette
    let initial: String
    var size: CGFloat = 28
    var fontSize: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.avatarFill)
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
            Text(initial.isEmpty ? "G" : initial)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: size, height: size)
    }
}

struct GrokKbdBadge: View {
    @Environment(\.palette) private var palette
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
    }
}
