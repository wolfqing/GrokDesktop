import AppKit
import SwiftUI

@main
struct GrokDesktopApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .background(GrokTheme.canvas)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新会话") { model.startNewSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Grok") {
                Button("设置…") { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("选择工作目录…") { model.chooseWorkingDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("命令面板") {
                    model.draft = "/"
                    model.showPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
