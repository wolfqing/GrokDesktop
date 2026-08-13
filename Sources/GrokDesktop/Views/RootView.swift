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
                .frame(maxWidth: .infinity)
                if model.showInspector && model.destination == .chat {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(width: 1)
                    InspectorView()
                        .frame(width: GrokTheme.inspectorWidth)
                }
            }

            if model.showAbout {
                AboutView()
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
            if model.showPalette && model.destination != .chat {
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
            if model.showAddWorkflow {
                addWorkflowSheet
                    .zIndex(6)
            }
            if model.showAddMCP {
                addMCPSheet
                    .zIndex(6)
            }
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(palette.elevated, in: Capsule())
                    .overlay(Capsule().stroke(palette.hairline))
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(8)
            }
        }
        .onAppear {
            if model.needsFolderPick {
                model.needsFolderPick = false
                model.chooseWorkingDirectory()
            }
        }
        .environment(\.palette, palette)
        .environment(\.l10n, model.copy)
        .foregroundStyle(palette.text)
        .background(palette.canvas)
        .animation(.easeInOut(duration: 0.18), value: model.showSettings)
        .animation(.easeInOut(duration: 0.18), value: model.showAbout)
        .animation(.easeInOut(duration: 0.18), value: model.destination)
        .animation(.easeInOut(duration: 0.18), value: model.sidebarCollapsed)
        .animation(.easeInOut(duration: 0.18), value: model.appearanceRaw)
        .animation(.easeInOut(duration: 0.18), value: model.languageRaw)
    }

    private var renameSheet: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.renamingSession = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text(model.copy.t("Rename session", "重命名会话"))
                    .font(.system(size: 16, weight: .semibold))
                TextField(model.copy.t("Title", "标题"), text: $model.renameDraft)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                HStack {
                    Spacer()
                    Button(model.copy.done) {
                        if let session = model.renamingSession {
                            model.rename(session, title: model.renameDraft)
                        }
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var resumePicker: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showResumePicker = false }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.copy.t("Resume session", "恢复会话"))
                    .font(.system(size: 16, weight: .semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.filteredSessions.prefix(30)) { session in
                            Button {
                                model.showResumePicker = false
                                model.open(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title).font(.system(size: 14))
                                    Text(session.cwdName).font(.system(size: 11)).foregroundStyle(palette.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 320)
            }
            .padding(18)
            .frame(width: 460)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var addWorkflowSheet: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showAddWorkflow = false }
            VStack(alignment: .leading, spacing: 12) {
                Text(model.copy.t("New workflow", "新建工作流"))
                    .font(.system(size: 16, weight: .semibold))
                TextField("review-changes", text: $model.newWorkflowName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                TextField(model.copy.t("What it does", "做什么"), text: $model.newWorkflowDetail, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                Text(model.copy.t("Saves ~/.grok/workflows/<name>.rhai and runs /workflow <name>.", "保存到 ~/.grok/workflows/<name>.rhai，并运行 /workflow <name>。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                HStack {
                    Spacer()
                    Button(model.copy.create) { model.createOfficialWorkflow() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                        .disabled(model.newWorkflowName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 460)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var addMCPSheet: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showAddMCP = false }
            VStack(alignment: .leading, spacing: 12) {
                Text(model.copy.t("Add MCP server", "添加 MCP"))
                    .font(.system(size: 16, weight: .semibold))
                TextField("brave-search", text: $model.mcpName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
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
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                if model.mcpTransport == "stdio" {
                    TextField("-y @modelcontextprotocol/server-github", text: $model.mcpArgs)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                }
                HStack {
                    Spacer()
                    Button(model.copy.add) { model.addMCPServer() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                        .disabled(model.mcpName.isEmpty || model.mcpCommand.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 480)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
