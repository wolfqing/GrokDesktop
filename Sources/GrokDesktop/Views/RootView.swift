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
                Group {
                    switch model.destination {
                    case .chat:
                        ChatView()
                    case .automations:
                        AutomationsView()
                    case .skills:
                        SkillsView()
                    }
                }
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
            if model.showCreateProject {
                CreateProjectSheet()
                    .zIndex(3)
            }
            if model.showPalette {
                CommandPalette()
                    .zIndex(4)
            }
        }
        .environment(\.palette, palette)
        .environment(\.l10n, model.copy)
        .foregroundStyle(palette.text)
        .background(palette.canvas)
        .animation(.easeInOut(duration: 0.18), value: model.showSettings)
        .animation(.easeInOut(duration: 0.18), value: model.destination)
        .animation(.easeInOut(duration: 0.18), value: model.sidebarCollapsed)
        .animation(.easeInOut(duration: 0.18), value: model.appearanceRaw)
        .animation(.easeInOut(duration: 0.18), value: model.languageRaw)
    }
}
