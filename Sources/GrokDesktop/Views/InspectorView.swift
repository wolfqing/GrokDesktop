import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var planNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(palette.hairline)

            if let preview = model.previewedFile {
                FilePreviewPane(url: preview)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, model.inspectorDetailsVisible ? 10 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showsDetails {
                if model.previewedFile != nil {
                    Divider().overlay(palette.hairline)
                    detailsHeader
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let story = liveStory {
                            turnSection(story)
                        }
                        if model.inspectorPaneVisible(.context) {
                            contextSection
                        }
                        if showsWork, model.inspectorPaneVisible(.work) {
                            workSection
                        }
                        if showsTerminals, model.inspectorPaneVisible(.terminals) {
                            terminalsSection
                        }
                        if showsChanges, model.inspectorPaneVisible(.changes) {
                            changesSection
                        }
                        if !model.officialWorkflows.isEmpty, model.inspectorPaneVisible(.workflows) {
                            workflowsSection
                        }
                        if !model.personas.isEmpty, model.inspectorPaneVisible(.personas) {
                            personasSection
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: model.previewedFile == nil ? .infinity : 280)
            }
        }
        .background(palette.sidebar)
        .onAppear {
            model.refreshWorkspace()
            model.client.refreshPlanArtifacts()
            Task { await model.client.refreshGit() }
        }
        .onChange(of: model.client.items.count) { _, _ in
            model.refreshWorkspace()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l10n.inspector)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            if !model.hiddenInspectorPaneList.isEmpty {
                Menu {
                    ForEach(model.hiddenInspectorPaneList) { pane in
                        Button(pane.title(chinese: l10n.language == .chinese)) {
                            model.showInspectorPane(pane)
                        }
                    }
                    Divider()
                    Button(l10n.t("Show all", "全部显示")) {
                        model.showAllInspectorPanes()
                    }
                } label: {
                    Text(l10n.t("Sections", "区块"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if model.previewedFile != nil {
                Button {
                    model.inspectorDetailsVisible.toggle()
                } label: {
                    Text(model.inspectorDetailsVisible
                         ? l10n.t("Hide details", "隐藏详情")
                         : l10n.t("Details", "详情"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var detailsHeader: some View {
        HStack {
            Text(l10n.t("Context and tasks", "上下文和任务"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer()
            Button {
                model.inspectorDetailsVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t("Hide details", "隐藏详情"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var showsDetails: Bool {
        (model.previewedFile == nil || model.inspectorDetailsVisible) && hasVisiblePanes
    }

    private var hasVisiblePanes: Bool {
        liveStory != nil
            || model.inspectorPaneVisible(.context)
            || (showsWork && model.inspectorPaneVisible(.work))
            || (showsTerminals && model.inspectorPaneVisible(.terminals))
            || (showsChanges && model.inspectorPaneVisible(.changes))
            || (!model.officialWorkflows.isEmpty && model.inspectorPaneVisible(.workflows))
            || (!model.personas.isEmpty && model.inspectorPaneVisible(.personas))
    }

    private var liveStory: TurnStory? {
        TurnNarrative.story(
            items: model.client.items,
            todos: model.client.todos,
            hunks: model.client.hunks,
            chinese: model.language.resolved() == .chinese,
            running: model.client.isTurnRunning,
            stopping: model.client.isStopping
        )
    }

    private var showsTerminals: Bool {
        !model.client.terminals.isEmpty
    }

    private func turnSection(_ story: TurnStory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.t("This turn", "本轮"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if story.total > 0 {
                    Text("\(story.done)/\(story.total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                RunningStatusIcon(
                    active: story.phase == .working,
                    idleSystemImage: "pause.circle",
                    color: .orange,
                    size: 11
                )
                .padding(.top, 2)
                Text(story.step)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next = story.nextStep, !next.isEmpty {
                Text(l10n.t("Next: \(next)", "下一步：\(next)"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var terminalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.terminals, title: l10n.t("Terminals", "终端")) { EmptyView() }
            ForEach(model.client.terminals) { terminal in
                terminalRow(terminal)
            }
        }
    }

    private func terminalRow(_ terminal: TerminalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                RunningStatusIcon(
                    active: terminal.running,
                    idleSystemImage: terminal.exitCode == 0 ? "checkmark" : "xmark",
                    color: terminal.running ? .orange : palette.secondary,
                    size: 11
                )
                .padding(.top, 2)
                Text(terminal.command)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if terminal.running {
                    Button(l10n.stop) {
                        model.client.killTerminal(terminal.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                } else if let code = terminal.exitCode {
                    Text("\(code)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
            }
            if !terminal.preview.isEmpty {
                Text(terminal.preview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.context, title: l10n.t("Context", "上下文")) {
                Button {
                    model.refreshContextBreakdown()
                    model.showContextSheet = true
                } label: {
                    Text(l10n.t("Details", "明细"))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.displayedContextPercent)%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(compactTokens(model.displayedContextUsed)) / \(compactTokens(model.displayedContextWindow))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.chip)
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(min(max(model.displayedContextPercent, 0), 100)) / 100)
                }
            }
            .frame(height: 6)
            Button {
                model.chooseWorkingDirectory()
            } label: {
                Text(model.client.workingDirectory.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(model.client.workingDirectory.path)
            if showsConnection {
                connectionLine
            }
        }
    }

    private var connectionLine: some View {
        Text(connectionLabel)
            .font(.system(size: 11))
            .foregroundStyle(palette.secondary)
    }

    private var connectionLabel: String {
        switch model.client.state {
        case .idle: return l10n.t("Idle", "空闲")
        case .connecting: return l10n.t("Connecting…", "正在连接…")
        case .initialized: return l10n.t("Agent initialized, no session", "已握手，尚未建会话")
        case .ready: return l10n.t("Session ready", "会话就绪")
        case .failed(let message): return message
        }
    }

    private var showsConnection: Bool {
        switch model.client.state {
        case .connecting, .initialized, .failed:
            return true
        default:
            return false
        }
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(model.client.mode == .plan ? l10n.t("Plan", "计划") : l10n.tasks)
                Spacer()
                if checklistProgress.total > 0 {
                    Text("\(checklistProgress.done)/\(checklistProgress.total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                if model.client.hasActiveWork {
                    Button(model.client.isStopping ? l10n.stopping : l10n.stop) {
                        if !model.client.isStopping { model.client.stopWork() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .disabled(model.client.isStopping)
                }
                paneClose(.work)
            }
            if checklistProgress.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.chip)
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(checklistProgress.done) / CGFloat(max(checklistProgress.total, 1)))
                    }
                }
                .frame(height: 6)
            }
            if checklist.isEmpty, model.client.mode == .plan {
                Text(l10n.t("No plan yet.", "还没有计划。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            ForEach(checklist, id: \.id) { row in
                HStack(alignment: .top, spacing: 6) {
                    RunningStatusIcon(
                        active: model.client.isTurnRunning && (row.status == "in_progress" || row.status == "running"),
                        idleSystemImage: todoIcon(row.status),
                        color: todoColor(row.status),
                        size: 12
                    )
                    .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.content)
                            .font(.system(size: 12))
                            .strikethrough(row.status == "completed" || row.status == "cancelled")
                        HStack(spacing: 6) {
                            Text(todoStatusLabel(row.status))
                            if let todo = model.client.todos.first(where: { $0.id == row.id }) {
                                ElapsedDurationText(
                                    start: todo.startedAt,
                                    end: todo.endedAt,
                                    running: todo.isActive && model.client.isTurnRunning,
                                    worked: todo.isDone || todo.isCancelled
                                )
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondary)
                    }
                }
            }
            if model.client.mode == .plan, !extraPlanMarkdown.isEmpty {
                Text(extraPlanMarkdown)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            if model.client.mode == .plan {
                TextField(l10n.t("Request changes…", "打回意见…"), text: $planNote)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) {
                    Button(l10n.t("Approve", "批准")) {
                        Task { await model.client.approvePlan() }
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    Button(l10n.t("Revise", "打回")) {
                        Task { await model.client.requestPlanChanges(planNote) }
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    Button(l10n.t("Quit plan", "退出 Plan")) {
                        model.client.quitPlan()
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            let liveTasks = model.client.tasks.filter(\.isRunning)
            let finishedTasks = model.client.tasks.filter { !$0.isRunning }
            if !liveTasks.isEmpty {
                Text(l10n.t("Live tasks", "进行中的任务"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(liveTasks) { task in
                    taskRow(task)
                }
            }
            if !model.client.backgroundLiveTasks.isEmpty {
                Text(l10n.t("Other sessions", "其他会话"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(model.client.backgroundLiveTasks, id: \.task.id) { row in
                    Button {
                        _ = model.client.focusIfLoaded(row.sessionID)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.task.title)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(row.title)
                                ElapsedDurationText(
                                    start: row.task.startedAt,
                                    end: row.task.endedAt,
                                    running: row.task.isRunning,
                                    worked: !row.task.isRunning
                                )
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !model.client.subagents.isEmpty {
                Text(l10n.subagents)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(model.client.subagents) { agent in
                    HStack(alignment: .top, spacing: 6) {
                        RunningStatusIcon(
                            active: agent.isRunning,
                            idleSystemImage: agent.status == "cancelled" ? "xmark.circle" : "checkmark.circle",
                            color: agent.isRunning ? Color.orange : palette.secondary,
                            size: 12
                        )
                        .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.detail.isEmpty ? agent.type : agent.detail)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(agent.isRunning ? l10n.running : l10n.completed)
                                ElapsedDurationText(
                                    start: agent.startedAt,
                                    end: nil,
                                    duration: agent.elapsed,
                                    running: agent.isRunning,
                                    worked: !agent.isRunning
                                )
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
            if !finishedTasks.isEmpty {
                Text(l10n.backgroundTasks)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(Array(finishedTasks.suffix(8))) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RunningStatusIcon(
                active: task.isRunning,
                idleSystemImage: task.status == "cancelled" ? "xmark.circle" : "checkmark.circle",
                color: task.isRunning ? Color.orange : palette.secondary,
                size: 12
            )
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(task.isRunning ? l10n.running : (task.status == "cancelled" ? l10n.t("Cancelled", "已取消") : l10n.completed))
                    ElapsedDurationText(
                        start: task.startedAt,
                        end: task.endedAt,
                        running: task.isRunning,
                        worked: !task.isRunning
                    )
                    if task.isRunning {
                        Button(l10n.stop) {
                            model.client.killTask(task.id)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
            }
        }
    }

    private var showsWork: Bool {
        !checklist.isEmpty
            || !model.client.tasks.isEmpty
            || !model.client.subagents.isEmpty
            || !model.client.backgroundLiveTasks.isEmpty
            || model.client.mode == .plan
    }

    private var checklist: [(id: String, content: String, status: String)] {
        if !model.client.todos.isEmpty {
            return model.client.todos.map { ($0.id, $0.content, $0.status) }
        }
        return model.client.planEntries.map { ($0.id, $0.content, $0.status) }
    }

    private var checklistProgress: (done: Int, total: Int) {
        let total = checklist.count
        let done = checklist.filter { $0.status == "completed" }.count
        return (done, total)
    }

    private var extraPlanMarkdown: String {
        let text = model.client.planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let listed = Set(checklist.map { $0.content.lowercased() })
        if listed.contains(where: { text.lowercased().contains($0) }), text.count < 400 {
            return ""
        }
        return text
    }

    private func todoIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.dotted"
        case "cancelled": return "xmark.circle"
        default: return "circle"
        }
    }

    private func todoColor(_ status: String) -> Color {
        switch status {
        case "completed": return .green
        case "in_progress": return .orange
        case "cancelled": return palette.secondary
        default: return palette.secondary
        }
    }

    private func todoStatusLabel(_ status: String) -> String {
        switch status {
        case "completed": return l10n.completed
        case "in_progress": return l10n.running
        case "cancelled": return l10n.t("Cancelled", "已取消")
        default: return l10n.t("Pending", "待办")
        }
    }

    private var showsChanges: Bool {
        !model.client.hunks.isEmpty
            || !model.client.gitDiffText.isEmpty
            || (model.workspace.isRepo && (model.workspace.insertions + model.workspace.deletions) > 0)
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.changes, title: l10n.changes) { EmptyView() }
            if model.workspace.isRepo {
                Text("\(model.workspace.branch ?? "HEAD")  +\(model.workspace.insertions) / -\(model.workspace.deletions)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            if !model.client.gitStatusText.isEmpty {
                Text(model.client.gitStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
            if !scannedDiffs.isEmpty {
                ForEach(scannedDiffs) { file in
                    DiffFileBlock(file: file)
                }
            } else if !model.client.gitDiffText.isEmpty {
                Text(model.client.gitDiffText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(10)
            }
            if model.client.hunks.isEmpty && scannedDiffs.isEmpty && model.client.gitDiffText.isEmpty {
                Text(l10n.t("No session diffs yet.", "这一轮还没有 diff。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else if !model.client.hunks.isEmpty, scannedDiffs.isEmpty {
                ForEach(model.client.hunks) { hunk in
                    let url = ChatLinkDetector.resolve(hunk.path, baseDirectory: model.client.workingDirectory)?.url
                        ?? URL(fileURLWithPath: hunk.path)
                    Button {
                        model.previewFile(url)
                    } label: {
                        HStack {
                            Text(hunk.name)
                                .lineLimit(1)
                                .underline()
                            Spacer()
                            Text("+\(hunk.added)")
                                .foregroundStyle(.green)
                            Text("-\(hunk.removed)")
                                .foregroundStyle(.red)
                        }
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(hunk.path)
                    .contextMenu { ChatLinkContextButtons(url: url) }
                }
            }
        }
    }

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.workflows, title: l10n.t("Workflows", "工作流")) { EmptyView() }
            if model.officialWorkflows.isEmpty {
                Button(l10n.t("Open workflows", "打开工作流")) {
                    model.destination = .automations
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            } else {
                ForEach(model.officialWorkflows.prefix(8)) { item in
                    Button {
                        model.runWorkflow(item)
                    } label: {
                        Text(item.name).font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var personasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.personas, title: l10n.t("Agents / personas", "Agent / 人设")) { EmptyView() }
            if model.personas.isEmpty {
                Text(l10n.t("None on disk.", "磁盘上没有人设。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(model.personas.prefix(8), id: \.self) { name in
                    Button {
                        model.agentsTab = 1
                        model.showAgents = true
                    } label: {
                        Text(name).font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scannedDiffs: [DiffFile] {
        DiffScan.parse(model.client.gitDiffText)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }

    private func paneHeader<Extra: View>(_ pane: InspectorPane, title: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(spacing: 6) {
            sectionTitle(title)
            Spacer(minLength: 4)
            extra()
            paneClose(pane)
        }
    }

    private func paneClose(_ pane: InspectorPane) -> some View {
        Button {
            model.hideInspectorPane(pane)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(l10n.t("Hide this section", "关闭这个区块"))
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.0fk", Double(value) / 1000)
        }
        return "\(value)"
    }
}

private struct ElapsedDurationText: View {
    let start: Date?
    var end: Date? = nil
    var duration: TimeInterval? = nil
    let running: Bool
    let worked: Bool
    @Environment(\.l10n) private var l10n

    var body: some View {
        if running, let start {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PromptTimestamp.formatElapsed(context.date.timeIntervalSince(start)))
            }
        } else if let span = duration ?? PromptTimestamp.elapsed(from: start, to: end), span > 0 || worked {
            Text(worked
                 ? l10n.t("worked \(PromptTimestamp.formatElapsed(span))", "用时 \(PromptTimestamp.formatElapsed(span))")
                 : PromptTimestamp.formatElapsed(span))
        }
    }
}

private struct DiffFileBlock: View {
    let file: DiffFile
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var expanded = true

    var body: some View {
        let url = ChatLinkDetector.resolve(file.path, baseDirectory: model.client.workingDirectory)?.url
            ?? URL(fileURLWithPath: file.path)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    DispatchQueue.main.async { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .buttonStyle(.plain)
                Button(file.name) {
                    model.previewFile(url)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .linkColor))
                .help(file.path)
                .contextMenu { ChatLinkContextButtons(url: url) }
                Spacer()
                Text("+\(file.added)")
                    .foregroundStyle(.green)
                Text("-\(file.removed)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 12))
            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(file.lines.prefix(40).enumerated()), id: \.offset) { _, line in
                        if line.kind != .meta {
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(background(for: line.kind), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    if file.lines.count > 40 {
                        Text("+\(file.lines.count - 40)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color.green
        case .removed: return Color.red
        case .header: return palette.secondary
        case .meta, .context: return palette.text
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        default: return .clear
        }
    }
}
