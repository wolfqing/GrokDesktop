import AppKit
import SwiftUI

@main
struct GrokDesktopApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.colorScheme) private var systemScheme

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.copy.newChat) { model.startNewSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Grok") {
                Button(model.copy.settings) { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button(model.copy.chooseFolder) { model.chooseWorkingDirectory() }
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
