import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            GrokTheme.canvas.ignoresSafeArea()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: GrokTheme.sidebarWidth)
                Rectangle()
                    .fill(GrokTheme.hairline)
                    .frame(width: 1)
                ChatView()
                    .frame(maxWidth: .infinity)
                if model.showInspector {
                    Rectangle()
                        .fill(GrokTheme.hairline)
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
        .foregroundStyle(GrokTheme.text)
        .animation(.easeInOut(duration: 0.18), value: model.showSettings)
        .animation(.easeInOut(duration: 0.18), value: model.showInspector)
    }
}
