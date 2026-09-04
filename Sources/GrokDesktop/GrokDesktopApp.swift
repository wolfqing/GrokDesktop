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
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                    if DemoStudio.isEnabled, let url = DemoStudio.screenshotURL {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            let ok = DemoStudio.writeScreenshot(model: model, to: url)
                            fputs(ok ? "Wrote demo screenshot \(url.path)\n" : "Failed to write demo screenshot\n", stderr)
                            if DemoStudio.shouldExitAfterScreenshot {
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            model.sidebarCollapsed.toggle()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .help(model.sidebarCollapsed ? model.copy.t("Expand sidebar", "展开侧栏") : model.copy.collapseSidebar)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(model.copy.t("About Grok Desktop", "关于 Grok Desktop")) {
                    model.showAbout = true
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(model.copy.newChat) { model.startNewSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Grok") {
                Button(model.copy.productChat) { model.openWebChat() }
                    .keyboardShortcut("1", modifiers: .command)
                Button(model.copy.productBuild) { model.openBuildSurface() }
                    .keyboardShortcut("2", modifiers: .command)
                Button(model.copy.settings) { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button(model.copy.chooseFolder) { model.chooseWorkingDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(model.copy.t("Command palette", "命令面板")) {
                    model.draft = "/"
                    model.showPalette = true
                    model.destination = .build
                }
                .keyboardShortcut("k", modifiers: .command)
                Button(model.copy.t("Open slash menu", "打开斜杠菜单")) {
                    model.draft = "/"
                    model.showPalette = true
                    model.destination = .build
                }
                .keyboardShortcut("p", modifiers: .command)
                Button(model.copy.t("Prompt history", "提示词历史")) {
                    model.showPromptHistory = true
                }
                .keyboardShortcut("y", modifiers: .command)
                Button(model.copy.t("Resume session", "恢复会话")) {
                    model.showResumePicker = true
                    model.sidebarCollapsed = false
                    model.showSearchField = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button(model.copy.t("Inspector", "右侧栏")) {
                    model.showInspector.toggle()
                    model.destination = .build
                }
                .keyboardShortcut("i", modifiers: .command)
                Button(model.copy.t("By the way", "顺便问")) {
                    model.openAsideComposer()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Button(model.copy.t("Cycle mode", "切换模式")) { model.cycleMode() }
                    .keyboardShortcut(.tab, modifiers: .shift)
                Button(model.copy.t("Always approve", "全权")) {
                    model.handleCommand("/always-approve")
                }
                .keyboardShortcut("o", modifiers: .control)
                Button(model.copy.t("Dashboard", "任务面板")) { model.destination = .dashboard }
                    .keyboardShortcut("\\", modifiers: .control)
                Button(model.copy.usage) { model.openUsage() }
            }
            CommandGroup(replacing: .help) {
                Button(model.copy.t("Grok Build Docs", "Grok Build 文档")) {
                    model.handleCommand("/docs")
                }
                Button(model.copy.t("Tutorial", "教程")) {
                    model.handleCommand("/tutorial")
                }
                Button(model.copy.t("Keyboard shortcuts", "键盘快捷键")) {
                    model.showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
                Button("/doctor") { model.handleCommand("/doctor") }
                Button("/inspect") { model.handleCommand("/inspect") }
                Button(model.copy.t("Check CLI updates", "检查 CLI 更新")) {
                    model.handleCommand("/update")
                }
                Button("CHANGELOG") { model.openChangelog() }
            }
        }
    }
}
