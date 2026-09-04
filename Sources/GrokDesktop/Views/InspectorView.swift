import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var planNote = ""
    @FocusState private var asideFocused: Bool

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
                        if showsContext, model.inspectorPaneVisible(.context) {
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
                        if showsHooks, model.inspectorPaneVisible(.hooks) {
                            hooksSection
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: model.previewedFile == nil ? .infinity : 280)
            } else if model.previewedFile == nil {
                Spacer(minLength: 0)
            }

            Divider().overlay(palette.hairline)
            steerPanel
        }
        .background(palette.sidebar)
        .onAppear {
            model.refreshWorkspace()
            model.client.refreshPlanArtifacts()
            Task { await model.client.refreshGit() }
        }
        .onChange(of: model.client.isTurnRunning) { wasRunning, running in
            if wasRunning, !running {
                model.refreshWorkspace()
            }
        }
        .onChange(of: model.focusAsideComposer) { _, focus in
            if focus {
                asideFocused = true
                model.focusAsideComposer = false
            }
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
            || (showsContext && model.inspectorPaneVisible(.context))
            || (showsWork && model.inspectorPaneVisible(.work))
            || (showsTerminals && model.inspectorPaneVisible(.terminals))
            || (showsChanges && model.inspectorPaneVisible(.changes))
            || (showsHooks && model.inspectorPaneVisible(.hooks))
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

    private var showsContext: Bool {
        model.displayedContextUsed > 0
            || !model.client.items.isEmpty
            || showsConnection
    }

    private var asideTurns: [AsideTurn] {
        SessionFold.asideTurns(items: model.client.items, queued: model.client.promptQueue)
    }

    private var steerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                Text(l10n.t("By the way", "顺便问"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(l10n.t("Won't interrupt", "不打断当前任务"))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
            if !asideTurns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(asideTurns.suffix(4)) { turn in
                        asideTurnRow(turn)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    l10n.t("Steer this turn…", "顺便说一句…"),
                    text: $model.asideDraft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...4)
                .focused($asideFocused)
                .onSubmit { model.sendAside() }
                Button {
                    model.sendAside()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(canSendAside ? palette.sendGlyph : palette.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            canSendAside ? palette.send : palette.chip,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendAside)
                .help(l10n.t("Send aside", "发送旁问"))
            }
            .padding(8)
            .background(palette.input, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSendAside: Bool {
        !model.asideDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func asideTurnRow(_ turn: AsideTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(turn.question)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if turn.queued {
                Text(l10n.t("Queued — sends after this turn", "排队中 — 本轮结束后发送"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            } else if turn.pending, turn.answer.isEmpty {
                HStack(spacing: 6) {
                    RunningStatusIcon(active: true, idleSystemImage: "ellipsis", color: .orange, size: 10)
                    Text(l10n.t("Waiting for a side answer", "等旁问回复"))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
            } else if !turn.answer.isEmpty {
                Text(turn.answer)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            Button {
                Task { await model.client.compact() }
            } label: {
                Text(l10n.t("Compact now", "立即压缩"))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondary)
            if !model.client.checkpoints.isEmpty {
                Text(l10n.t("Checkpoints", "检查点"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(model.client.checkpoints.prefix(6)) { point in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(point.createdAt.map { RelativeTime.format($0, chinese: l10n.language == .chinese) } ?? point.id)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            if point.tokensBefore > 0 || point.tokensAfter > 0 {
                                Text("\(compactTokens(point.tokensBefore)) → \(compactTokens(point.tokensAfter))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.secondary)
                            }
                        }
                        if !point.recap.isEmpty {
                            Text(point.recap)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(3)
                        }
                    }
                }
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
            if !liveWorkItems.isEmpty {
                Text(l10n.t("Now", "进行中"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, checklist.isEmpty ? 0 : 4)
                ForEach(liveWorkItems) { item in
                    liveWorkRow(item)
                }
            }
            if !model.client.scheduledTasks.isEmpty {
                Text(l10n.t("Loops", "循环任务"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(model.client.scheduledTasks) { task in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            Text(task.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        Button(l10n.stop) {
                            model.cancelScheduledTask(task)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    }
                }
            }
            if !finishedSubagents.isEmpty {
                Text(l10n.subagents)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(finishedSubagents) { agent in
                    Button {
                        model.openSubagent(agent)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.detail.isEmpty ? agent.type : agent.detail)
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                                Text([agent.isolation, agent.status].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct LiveWorkItem: Identifiable {
        var id: String
        var title: String
        var detail: String
        var start: Date?
        var end: Date? = nil
        var duration: TimeInterval? = nil
        var sessionID: String? = nil
        var taskID: String? = nil
        var subagent: AgentSubagent? = nil
    }

    private var liveWorkItems: [LiveWorkItem] {
        let checklistTitles = Set(checklist.map { $0.content.lowercased() })
        var items: [LiveWorkItem] = []
        var seen = Set<String>()
        func add(_ item: LiveWorkItem) {
            let key = item.title.lowercased()
            guard seen.insert(key).inserted else { return }
            items.append(item)
        }
        for task in model.client.tasks where task.isRunning {
            if checklistTitles.contains(task.title.lowercased()) { continue }
            add(LiveWorkItem(
                id: "task-\(task.id)",
                title: task.title,
                detail: l10n.running,
                start: task.startedAt,
                end: task.endedAt,
                taskID: task.id
            ))
        }
        for agent in model.client.subagents where agent.isRunning {
            add(LiveWorkItem(
                id: "sub-\(agent.id)",
                title: agent.detail.isEmpty ? agent.type : agent.detail,
                detail: agent.isolation.isEmpty ? l10n.running : agent.isolation,
                start: agent.startedAt,
                duration: agent.elapsed,
                sessionID: agent.childSessionId.isEmpty ? agent.id : agent.childSessionId,
                subagent: agent
            ))
        }
        for row in model.client.backgroundLiveTasks {
            add(LiveWorkItem(
                id: "bg-\(row.sessionID)-\(row.task.id)",
                title: row.task.title,
                detail: row.title,
                start: row.task.startedAt,
                end: row.task.endedAt,
                sessionID: row.sessionID
            ))
        }
        return items
    }

    @ViewBuilder
    private func liveWorkRow(_ item: LiveWorkItem) -> some View {
        let row = HStack(alignment: .top, spacing: 6) {
            RunningStatusIcon(active: true, idleSystemImage: "circle", color: .orange, size: 12)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.detail)
                    ElapsedDurationText(
                        start: item.start,
                        end: item.end,
                        duration: item.duration,
                        running: true,
                        worked: false
                    )
                    if let taskID = item.taskID {
                        Button(l10n.stop) {
                            model.client.killTask(taskID)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
            }
        }
        if let agent = item.subagent {
            Button {
                model.openSubagent(agent)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else if let sessionID = item.sessionID {
            Button {
                _ = model.client.focusIfLoaded(sessionID)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var finishedSubagents: [AgentSubagent] {
        model.client.subagents.filter { !$0.isRunning }
    }

    private var showsWork: Bool {
        !checklist.isEmpty
            || !liveWorkItems.isEmpty
            || model.client.mode == .plan
            || !model.client.scheduledTasks.isEmpty
            || !finishedSubagents.isEmpty
    }

    private var showsHooks: Bool {
        !model.client.hookEvents.isEmpty || !model.hookDefinitions.isEmpty
    }

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(.hooks, title: l10n.t("Hooks", "钩子")) {
                EmptyView()
            }
            if !model.client.hookEvents.isEmpty {
                ForEach(model.client.hookEvents.prefix(12)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.event)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(event.blocked ? l10n.t("blocked", "已拦截") : l10n.t("ran", "已运行"))
                                .font(.system(size: 10))
                                .foregroundStyle(event.blocked ? Color.orange : palette.secondary)
                        }
                        if !event.command.isEmpty {
                            Text(event.command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                ForEach(model.hookDefinitions.prefix(12)) { hook in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hook.title)
                            .font(.system(size: 12, weight: .medium))
                        Text([hook.sourceKind, hook.pluginName, hook.matcher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
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
