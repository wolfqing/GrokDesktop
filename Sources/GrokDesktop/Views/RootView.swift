import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette {
        Palette.resolve(preference: model.appearance, system: colorScheme)
    }

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: model.sidebarCollapsed ? GrokTheme.collapsedSidebarWidth : GrokTheme.sidebarWidth)
                ChatView()
                    .frame(maxWidth: .infinity)
                if model.showInspector {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(width: 1)
                    InspectorView()
                        .frame(width: GrokTheme.inspectorWidth)
                }
            }

            if model.showSettings {
                SettingsView()
                    .transition(.opacity)
                    .zIndex(2)
            }

            if model.showPalette {
                CommandPalette()
                    .zIndex(3)
            }
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.text)
        .background(palette.canvas)
        .animation(.easeInOut(duration: 0.18), value: model.showSettings)
        .animation(.easeInOut(duration: 0.18), value: model.showInspector)
        .animation(.easeInOut(duration: 0.18), value: model.sidebarCollapsed)
        .animation(.easeInOut(duration: 0.18), value: model.appearanceRaw)
    }
}
