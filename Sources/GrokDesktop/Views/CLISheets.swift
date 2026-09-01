import GrokDesktopCore
import SwiftUI

struct OverlaySheet<Content: View>: View {
    @Environment(\.palette) private var palette
    var width: CGFloat = 520
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(20)
            .frame(width: width)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hairline))
        }
    }
}

struct PromptHistorySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var query = ""

    var body: some View {
        OverlaySheet(width: 520, onDismiss: { model.showPromptHistory = false }) {
            Text(l10n.t("Prompt history", "提示词历史"))
                .font(.system(size: 16, weight: .semibold))
            TextField(l10n.searchEllipsis, text: $query)
                .textFieldStyle(.plain)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            if filtered.isEmpty {
                Text(l10n.t("No saved prompts yet. Send something first, or press ↑ on an empty composer.", "还没有保存的提示词。先发送一条，或在空输入框按 ↑。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, text in
                            Button {
                                model.applyHistory(text)
                            } label: {
                                Text(text)
                                    .font(.system(size: 13))
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 320)
            }
        }
    }

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return model.promptHistory }
        return model.promptHistory.filter { $0.localizedCaseInsensitiveContains(needle) }
    }
}

struct CLIReportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 640, onDismiss: { model.showCLIReport = false }) {
            HStack {
                Text(model.cliReportTitle)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(l10n.t("Copy", "复制")) {
                    model.copyText(model.cliReportBody)
                    model.flash(l10n.copied)
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
            ScrollView {
                Text(model.cliReportBody)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 380)
        }
    }
}

struct DocsPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 520, onDismiss: { model.showDocsPicker = false }) {
            Text(model.docsPickerTutorial
                 ? l10n.t("Tutorial", "教程")
                 : l10n.t("How-to guides", "使用指南"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(guides) { guide in
                        Button {
                            model.openGuide(guide)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guide.title)
                                    .font(.system(size: 14, weight: .medium))
                                Text(guide.filename)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 360)
            Button(l10n.t("Open web docs", "打开网页文档")) {
                model.showDocsPicker = false
                model.openDocs()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
    }

    private var guides: [LocalGuide] {
        model.docsPickerTutorial ? LocalGuides.tutorial() : LocalGuides.all()
    }
}

struct FeedbackSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 480, onDismiss: { model.showFeedbackSheet = false }) {
            Text(l10n.t("Feedback", "反馈"))
                .font(.system(size: 16, weight: .semibold))
            Text(l10n.t("This is sent as /feedback in the current session.", "会作为 /feedback 发到当前会话。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(l10n.t("What happened?", "发生了什么？"), text: $model.feedbackDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button(l10n.t("Send", "发送")) { model.submitFeedback() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct ShortcutsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showShortcuts = false }) {
            Text(l10n.t("Shortcuts", "快捷键"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    row("⌘N", l10n.t("New chat", "新对话"))
                    row("⌘K / ⌘P", l10n.t("Command palette", "命令面板"))
                    row("⌘,", l10n.t("Settings", "设置"))
                    row("⌘⇧R", l10n.t("Resume session", "恢复会话"))
                    row("⌘Y", l10n.t("Prompt history", "提示词历史"))
                    row("⌘I", l10n.t("Inspector", "右侧栏"))
                    row("⇧⇥", l10n.t("Cycle permission mode", "切换权限模式"))
                    row("⌃\\", l10n.t("Dashboard", "任务面板"))
                    row("↑ / ↓", l10n.t("Recall previous prompts", "回忆上一条提示词"))
                    row("Esc Esc", l10n.t("Clear prompt, or rewind if empty", "清空输入；空输入则回退一轮"))
                    row("Esc", l10n.t("Stop a running turn", "停止进行中的任务"))
                    row("/", l10n.t("Slash commands", "斜杠命令"))
                    row("@", l10n.t("Attach a file", "附加文件"))
                }
            }
            .frame(height: 360)
        }
    }

    private func row(_ key: String, _ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.secondary)
        }
        .font(.system(size: 13))
        .padding(.vertical, 2)
    }
}

struct ClaudeImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 600, onDismiss: { model.showClaudeImport = false }) {
            Text(l10n.t("Import Claude settings", "导入 Claude 设置"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                Text(model.claudeImport.report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 280)
            HStack {
                Button(l10n.t("Import MCP", "导入 MCP")) {
                    model.importClaudeMCP()
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(model.claudeImport.servers.isEmpty)
                Button(l10n.t("Ask Grok to finish", "交给 Grok 处理其余")) {
                    model.sendClaudeImportToAgent()
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Spacer()
            }
        }
    }
}

struct FindSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showFind = false }) {
            Text(model.findTimeline ? l10n.t("Timeline", "时间线") : l10n.t("Find in conversation", "在对话中查找"))
                .font(.system(size: 16, weight: .semibold))
            if !model.findTimeline {
                TextField(l10n.t("Search this chat", "搜索这条对话"), text: $model.findQuery)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            }
            if model.findHits.isEmpty {
                Text(l10n.t("No matches.", "没有匹配。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.findHits) { hit in
                            Button {
                                model.jumpToHit(hit)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(hit.snippet)
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(2)
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
        }
    }
}

struct RewindSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showRewind = false }) {
            Text(l10n.t("Rewind to a turn", "回退到某一轮"))
                .font(.system(size: 16, weight: .semibold))
            Text(l10n.t("Everything after the turn you pick is discarded.", "选中这一轮之后的内容都会丢掉。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            if model.rewindTurns.isEmpty {
                Text(l10n.t("No user turns yet.", "还没有用户轮次。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.rewindTurns.reversed()) { turn in
                            Button {
                                model.rewindTo(turn)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(l10n.t("Turn \(turn.promptIndex + 1)", "第 \(turn.promptIndex + 1) 轮"))
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        if let date = turn.date {
                                            Text(PromptTimestamp.format(date))
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(palette.secondary)
                                        }
                                    }
                                    Text(turn.text)
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 340)
            }
        }
    }
}

struct ContextSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showContextSheet = false }) {
            Text(l10n.t("Context", "上下文"))
                .font(.system(size: 16, weight: .semibold))
            HStack {
                Text("\(model.contextBreakdown.percent)%")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(model.contextBreakdown.used) / \(model.contextBreakdown.window)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.contextBreakdown.slices) { slice in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title(for: slice))
                            Spacer()
                            Text("\(slice.tokens)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.system(size: 12))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.chip)
                                Capsule()
                                    .fill(slice.id == "free" ? palette.secondary.opacity(0.35) : Color.orange)
                                    .frame(width: geo.size.width * fraction(slice.tokens))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("model: \(model.contextBreakdown.model)")
                Text("session: \(model.contextBreakdown.sessionID.isEmpty ? "—" : model.contextBreakdown.sessionID)")
                Text("turns: \(model.contextBreakdown.turnCount)")
                Text("tool calls: \(model.contextBreakdown.toolCallCount)")
                Text("skills: \(model.contextBreakdown.skillCount) · mcp: \(model.contextBreakdown.mcpCount)")
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .textSelection(.enabled)
        }
    }

    private func title(for slice: ContextSlice) -> String {
        switch slice.id {
        case "messages": return l10n.t("Messages", "消息")
        case "reasoning": return l10n.t("Reasoning", "推理")
        case "tools": return l10n.t("Tools", "工具")
        case "other": return l10n.t("System / overhead", "系统 / 开销")
        case "free": return l10n.t("Free", "剩余")
        default: return slice.title
        }
    }

    private func fraction(_ tokens: Int) -> CGFloat {
        let total = max(model.contextBreakdown.window, 1)
        return CGFloat(min(max(tokens, 0), total)) / CGFloat(total)
    }
}

struct MemorySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showMemory = false }) {
            HStack {
                Text(l10n.t("Memory files", "记忆文件"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Toggle(l10n.t("Memory", "记忆"), isOn: Binding(
                    get: { model.grokConfig.memoryEnabled },
                    set: { value in
                        try? model.configStore.set(section: "memory", key: "enabled", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                ))
                .toggleStyle(.switch)
            }
            Text(l10n.t("Markdown under ~/.grok/memory. Open a file to preview or edit.", "文件在 ~/.grok/memory。点开可预览或编辑。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            if model.memoryFiles.isEmpty {
                Text(l10n.t("No memory files yet. Turn memory on, then /remember or /flush.", "还没有记忆文件。打开记忆后用 /remember 或 /flush。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.memoryFiles) { file in
                            Button {
                                model.openMemoryFile(file)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(file.scope)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 280)
            }
            HStack {
                Button(l10n.t("Open folder", "打开文件夹")) {
                    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/memory")
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Spacer()
            }
        }
        .onAppear { model.refreshMemoryFiles() }
    }
}

struct WorktreeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showWorktrees = false }) {
            Text(l10n.t("Worktrees", "Worktree"))
                .font(.system(size: 16, weight: .semibold))
            Text(l10n.t("Isolated checkouts for this repo. Opening one starts a new session there.", "当前仓库的隔离 checkout。打开会在那个目录开新会话。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                TextField(l10n.t("branch name", "分支名"), text: $model.newWorktreeName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                Button(l10n.t("Create", "创建")) { model.createWorktree() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.newWorktreeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.worktrees.isEmpty {
                Text(l10n.t("No worktrees yet.", "还没有 worktree。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.worktrees) { tree in
                            HStack {
                                Button {
                                    model.openWorktree(tree)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tree.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text([tree.branch, tree.path].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    model.removeWorktree(tree)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(height: 240)
            }
        }
        .onAppear { model.refreshWorktrees() }
    }
}

struct PluginTrustSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 480, onDismiss: { model.pluginPending = nil }) {
            Text(l10n.t("Trust this plugin?", "信任这个插件？"))
                .font(.system(size: 16, weight: .semibold))
            if let plugin = model.pluginPending {
                Text(plugin.name)
                    .font(.system(size: 14, weight: .medium))
                if !plugin.detail.isEmpty {
                    Text(plugin.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Text(l10n.t(
                    "Installing enables its skills, MCP servers, and hooks. Only install plugins you trust.",
                    "安装后会启用它的技能、MCP 和钩子。只装你信任的来源。"
                ))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            }
            HStack {
                Spacer()
                Button(l10n.t("Cancel", "取消")) { model.pluginPending = nil }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.t("Trust & install", "信任并安装")) { model.installPendingPlugin() }
                    .buttonStyle(GrokPrimaryButtonStyle())
            }
        }
    }
}
