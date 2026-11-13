import GrokDesktopCore
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
            VStack(spacing: 0) {
                AppUpdateBanner()
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: model.sidebarCollapsed ? GrokTheme.collapsedSidebarWidth : GrokTheme.sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .zIndex(1)
                    ZStack {
                        Group {
                            switch model.destination {
                            case .webChat:
                                Color.clear
                            case .build:
                                ChatView()
                            case .dashboard:
                                DashboardView()
                            case .imagine:
                                ImagineView()
                            case .automations:
                                AutomationsView()
                            case .skills:
                                SkillsView()
                            }
                        }
                        if !DemoStudio.isEnabled, model.destination == .webChat {
                            GrokWebChatView { signedIn in
                                model.webChatSignedIn = signedIn
                            }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .background(palette.canvas)
                    if model.showInspector && model.destination == .build {
                        InspectorResizeHandle(
                            width: model.inspectorWidth,
                            onChange: { model.setInspectorWidth($0) },
                            onReset: { model.resetInspectorWidth() }
                        )
                        InspectorView()
                            .frame(width: model.inspectorWidth)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            if model.showAbout {
                AboutView()
                    .transition(.opacity)
                    .zIndex(2)
            }
            if model.showInAppLogin {
                InAppLoginView()
                    .transition(.opacity)
                    .zIndex(2)
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
            if model.showPalette && model.destination.isBuildSurface && model.destination != .build {
                CommandPalette()
                    .zIndex(4)
            }
            if model.renamingSession != nil {
                renameSheet
                    .zIndex(5)
            }
            if model.showResumePicker {
                resumePicker
                    .zIndex(6)
            }
            if model.showPromptHistory {
                PromptHistorySheet()
                    .zIndex(6)
            }
            if model.showCLIReport {
                CLIReportSheet()
                    .zIndex(6)
            }
            if model.showDocsPicker {
                DocsPickerSheet()
                    .zIndex(6)
            }
            if model.showFeedbackSheet {
                FeedbackSheet()
                    .zIndex(6)
            }
            if model.showShortcuts {
                ShortcutsSheet()
                    .zIndex(6)
            }
            if model.showClaudeImport {
                ClaudeImportSheet()
                    .zIndex(6)
            }
            if model.showAddWorkflow {
                addWorkflowSheet
                    .zIndex(6)
            }
            if model.showAddMCP {
                addMCPSheet
                    .zIndex(6)
            }
            if model.showMemory {
                MemorySheet()
                    .zIndex(6)
            }
            if model.showWorktrees {
                WorktreeSheet()
                    .zIndex(6)
            }
            if model.pluginPending != nil {
                PluginTrustSheet()
                    .zIndex(7)
            }
            if model.showFind {
                FindSheet()
                    .zIndex(6)
            }
            if model.showRewind {
                RewindSheet()
                    .zIndex(6)
            }
            if model.showContextSheet {
                ContextSheet()
                    .zIndex(6)
            }
            if model.showAgents {
                AgentsSheet()
                    .zIndex(6)
            }
            if let toast = model.toast {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.success)
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.elevated, in: Capsule())
                .overlay(Capsule().stroke(palette.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.12), radius: 14, y: 6)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .bottom)))
                .zIndex(8)
            }
        }
        .onAppear {
            model.prepareAttention()
            model.resumeBridgeLive()
            if model.needsFolderPick {
                model.needsFolderPick = false
                model.chooseWorkingDirectory()
            }
        }
        .onChange(of: model.destination) { _, _ in
            model.rememberBuildDestination()
            model.syncAttention()
        }
        .onChange(of: model.notifyThinking) { _, _ in
            model.syncAttention()
        }
        .environment(\.palette, palette)
        .environment(\.l10n, model.copy)
        .environmentObject(model.desk)
        .foregroundStyle(palette.text)
        .background(palette.canvas)
        .animation(.easeOut(duration: 0.16), value: model.toast)
        .animation(.easeOut(duration: 0.16), value: model.showInAppLogin)
        .animation(.easeOut(duration: 0.16), value: model.showSettings)
        .animation(.easeOut(duration: 0.16), value: model.showAbout)
        .animation(.easeOut(duration: 0.16), value: model.destination)
        .animation(.easeOut(duration: 0.16), value: model.sidebarCollapsed)
        .animation(.easeOut(duration: 0.16), value: model.appearanceRaw)
        .animation(.easeOut(duration: 0.16), value: model.languageRaw)
        .animation(.easeOut(duration: 0.16), value: model.appUpdateNotice)
    }

    private var renameSheet: some View {
        OverlaySheet(
            title: model.copy.t("Rename session", "重命名会话"),
            width: 420,
            onDismiss: { model.renamingSession = nil }
        ) {
            TextField(model.copy.t("Title", "标题"), text: $model.renameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(10)
                .grokFieldChrome(cornerRadius: 9)
                .onSubmit {
                    if let session = model.renamingSession {
                        model.rename(session, title: model.renameDraft)
                    }
                }
            HStack {
                Spacer()
                Button(model.copy.t("Cancel", "取消")) { model.renamingSession = nil }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(model.copy.done) {
                    if let session = model.renamingSession {
                        model.rename(session, title: model.renameDraft)
                    }
                }
                .buttonStyle(GrokPrimaryButtonStyle())
            }
        }
    }

    private var resumePicker: some View {
        OverlaySheet(
            title: model.copy.t("Resume session", "恢复会话"),
            width: 480,
            onDismiss: { model.showResumePicker = false }
        ) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                TextField(
                    model.copy.t("Title, folder, or time", "标题、目录或时间"),
                    text: $model.search
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .grokFieldChrome(cornerRadius: 9)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.filteredSessions.prefix(30)) { session in
                        Button {
                            model.showResumePicker = false
                            model.open(session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .lineLimit(1)
                                Text(RelativeTime.meta(session, chinese: model.showsChinese))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .grokHover(cornerRadius: 8)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 320)
        }
    }

    private var addWorkflowSheet: some View {
        OverlaySheet(
            title: model.copy.t("New workflow", "新建工作流"),
            width: 460,
            onDismiss: { model.showAddWorkflow = false }
        ) {
            TextField("review-changes", text: $model.newWorkflowName)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(10)
                .grokFieldChrome(cornerRadius: 9)
            TextField(model.copy.t("What it does", "做什么"), text: $model.newWorkflowDetail, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(2...4)
                .padding(10)
                .grokFieldChrome(cornerRadius: 9)
            Text(model.copy.t("Saves ~/.grok/workflows/<name>.rhai. Run it later from Saved.", "保存到 ~/.grok/workflows/<name>.rhai。之后在「已保存」里运行。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            HStack {
                Spacer()
                Button(model.copy.t("Cancel", "取消")) { model.showAddWorkflow = false }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(model.copy.create) { model.createOfficialWorkflow() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.newWorkflowName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var addMCPSheet: some View {
        OverlaySheet(
            title: model.copy.t("Add MCP server", "添加 MCP"),
            width: 480,
            onDismiss: { model.showAddMCP = false }
        ) {
            TextField("brave-search", text: $model.mcpName)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(10)
                .grokFieldChrome(cornerRadius: 9)
            Picker(model.copy.t("Transport", "传输"), selection: $model.mcpTransport) {
                Text("stdio").tag("stdio")
                Text("http").tag("http")
                Text("sse").tag("sse")
            }
            .pickerStyle(.segmented)
            TextField(
                model.mcpTransport == "stdio" ? "npx" : "https://mcp.example.com/mcp",
                text: $model.mcpCommand
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .padding(10)
            .grokFieldChrome(cornerRadius: 9)
            if model.mcpTransport == "stdio" {
                TextField("-y @modelcontextprotocol/server-github", text: $model.mcpArgs)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .padding(10)
                    .grokFieldChrome(cornerRadius: 9)
            }
            HStack {
                Spacer()
                Button(model.copy.t("Cancel", "取消")) { model.showAddMCP = false }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(model.copy.add) { model.addMCPServer() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.mcpName.isEmpty || model.mcpCommand.isEmpty)
            }
        }
    }
}

private struct InspectorResizeHandle: View {
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let width: CGFloat
    let onChange: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var dragOrigin: CGFloat?
    @State private var hovering = false

    var body: some View {
        let handle = ZStack {
            Rectangle()
                .fill(hovering || dragOrigin != nil ? palette.focusRing : palette.hairline)
                .frame(width: hovering || dragOrigin != nil ? 2 : 1)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = width
                    }
                    onChange((dragOrigin ?? width) - value.translation.width)
                }
                .onEnded { _ in
                    dragOrigin = nil
                }
        )
        .onTapGesture(count: 2, perform: onReset)
        .help(l10n.t("Drag to resize. Double-click to reset.", "拖动调整宽度。双击恢复默认。"))

        if #available(macOS 15.0, *) {
            handle.pointerStyle(.columnResize)
        } else {
            handle
        }
    }
}
