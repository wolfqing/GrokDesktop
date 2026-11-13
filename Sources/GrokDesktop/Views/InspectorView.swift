import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var planNote = ""
    @State private var hoveredPane: InspectorPane?
    @FocusState private var asideFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(palette.hairline).frame(height: 1)

            if let preview = model.previewedFile {
                FilePreviewPane(url: preview)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, model.inspectorDetailsVisible ? 10 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showsDetails {
                if model.previewedFile != nil {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    detailsHeader
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let story = liveStory {
                            inspectorCard {
                                turnSection(story)
                            }
                        }
                        if showsContext, model.inspectorPaneVisible(.context) {
                            inspectorPaneCard(.context) {
                                contextSection
                            }
                        }
                        if showsWork, model.inspectorPaneVisible(.work) {
                            inspectorPaneCard(.work) {
                                workSection
                            }
                        }
                        if showsTerminals, model.inspectorPaneVisible(.terminals) {
                            inspectorPaneCard(.terminals) {
                                terminalsSection
                            }
                        }
                        if showsChanges, model.inspectorPaneVisible(.changes) {
                            inspectorPaneCard(.changes) {
                                changesSection
                            }
                        }
                        if showsHooks, model.inspectorPaneVisible(.hooks) {
                            inspectorPaneCard(.hooks) {
                                hooksSection
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: model.previewedFile == nil ? .infinity : 280)
            } else if model.previewedFile == nil {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.tertiary)
                    Text(l10n.t("Session details show up here.", "会话状态、任务和变更会显示在这里。"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.inspectorPaneVisible(.aside) {
                Rectangle().fill(palette.hairline).frame(height: 1)
                steerPanel
            }
            if model.inspectorPaneVisible(.shell) {
                SidebarTerminalPane()
            }
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

    private func inspectorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grokCard(cornerRadius: 11)
    }

    private func inspectorPaneCard<Content: View>(_ pane: InspectorPane, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grokCard(cornerRadius: 11)
        .onHover { hovering in
            if hovering {
                hoveredPane = pane
            } else if hoveredPane == pane {
                hoveredPane = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l10n.inspector)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer(minLength: 4)
            if model.previewedFile != nil {
                Button {
                    model.inspectorDetailsVisible.toggle()
                } label: {
                    Text(model.inspectorDetailsVisible
                         ? l10n.t("Hide details", "隐藏详情")
                         : l10n.t("Details", "详情"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .grokHover(cornerRadius: 6)
                }
                .buttonStyle(.plain)
            }
            InspectorPanelsMenu()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7.5)
    }

    private var detailsHeader: some View {
        HStack {
            Text(l10n.t("Context and tasks", "上下文和任务"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Spacer()
            GrokIconButton(
                systemImage: "xmark",
                size: 20,
                iconSize: 9.5,
                cornerRadius: 5,
                helpText: l10n.t("Hide details", "隐藏详情")
            ) {
                model.inspectorDetailsVisible = false
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
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
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.tertiary)
            }
            if !asideTurns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
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
                        .foregroundStyle(canSendAside ? palette.sendGlyph : palette.tertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            canSendAside ? palette.send : palette.chip,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendAside)
                .help(l10n.t("Send aside (⌘⇧B)", "发送旁问 (⌘⇧B)"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .grokFieldChrome(cornerRadius: 12, focused: asideFocused)
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
                    RunningStatusIcon(active: true, idleSystemImage: "ellipsis", color: palette.warning, size: 10)
                    Text(l10n.t("Waiting for a side answer", "等旁问回复"))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
            } else if !turn.answer.isEmpty {
                Text(turn.answer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(8.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private func turnSection(_ story: TurnStory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.t("This turn", "本轮"))
                    .font(.system(size: 11.5, weight: .semibold))
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
                    color: palette.warning,
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
            paneHeader(.terminals, title: l10n.t("Agent commands", "代理命令")) { EmptyView() }
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
                    idleSystemImage: terminal.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: terminal.running ? palette.warning : (terminal.exitCode == 0 ? palette.success : palette.danger),
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
                    .foregroundStyle(palette.warning)
                } else if let code = terminal.exitCode {
                    Text("\(code)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(code == 0 ? palette.tertiary : palette.danger)
                }
            }
            if !terminal.preview.isEmpty {
                Text(terminal.preview)
                    .font(.system(size: 10.5, design: .monospaced))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .grokHover(cornerRadius: 5)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline) {
                if model.displayedContextWindow > 0 {
                    Text("\(model.displayedContextPercent)%")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Spacer()
                }
                Text(model.contextRatioLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                if model.displayedContextWindow == 0 {
                    Spacer()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.chip)
                    Capsule()
                        .fill(model.displayedContextPercent >= 85 ? palette.danger : palette.warning)
                        .frame(width: geo.size.width * CGFloat(min(max(model.displayedContextPercent, 0), 100)) / 100)
                        .animation(.easeOut(duration: 0.2), value: model.displayedContextPercent)
                }
            }
            .frame(height: 5)
            if let text = model.contextWindowNoteText {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if showsConnection {
                    connectionLine
                }
                Spacer(minLength: 0)
                if !model.client.items.isEmpty {
                    Button {
                        Task { await model.client.compact() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.compress.vertical")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(l10n.t("Compact", "压缩"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .grokHover(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !model.client.checkpoints.isEmpty {
                Rectangle().fill(palette.hairline).frame(height: 1).padding(.vertical, 2)
                Text(l10n.t("Checkpoints", "检查点"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
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
                        if point.promptIndex != nil {
                            Button(l10n.t("Back to here", "回到这里")) {
                                model.rewindToCheckpoint(point)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.warning)
                            .help(point.promptIndex.map {
                                l10n.t("Rewind to turn \($0 + 1)", "退回到第 \($0 + 1) 轮")
                            } ?? "")
                        }
                    }
                }
            }
        }
    }

    private var connectionLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(palette.warning)
                .frame(width: 5.5, height: 5.5)
            Text(connectionLabel)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
    }

    private var connectionLabel: String {
        switch model.client.state {
        case .idle: return l10n.t("Idle", "空闲")
        case .connecting: return l10n.t("Connecting…", "正在连接…")
        case .initialized: return l10n.t("Agent initialized", "已握手")
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
            paneHeader(.work, title: planIsChecklist ? l10n.t("Plan", "计划") : l10n.tasks) {
                HStack(spacing: 6) {
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
                        .foregroundStyle(palette.warning)
                        .disabled(model.client.isStopping)
                    }
                }
            }
            if checklistProgress.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.chip)
                        Capsule()
                            .fill(checklistProgress.done == checklistProgress.total ? palette.success : palette.warning)
                            .frame(width: geo.size.width * CGFloat(checklistProgress.done) / CGFloat(max(checklistProgress.total, 1)))
                            .animation(.easeOut(duration: 0.2), value: checklistProgress.done)
                    }
                }
                .frame(height: 5)
            }
            if model.client.mode == .plan, checklist.isEmpty, !keepsPlan {
                Text(l10n.t("No plan yet.", "还没有计划。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            ForEach(checklist, id: \.id) { row in
                let isDone = row.status == "completed" || row.status == "cancelled"
                HStack(alignment: .top, spacing: 7) {
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
                            .foregroundStyle(isDone ? palette.secondary : palette.text)
                            .strikethrough(isDone)
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
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.tertiary)
                    }
                }
            }
            if PlanSurface.listsPlanBesideTodos(
                todoCount: model.client.todos.count,
                entryCount: model.client.planEntries.count
            ) {
                Text(l10n.t("Plan", "计划"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(model.client.planEntries) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: todoIcon(entry.status))
                            .font(.system(size: 12))
                            .foregroundStyle(todoColor(entry.status))
                            .padding(.top, 2)
                        Text(entry.content)
                            .font(.system(size: 12))
                            .strikethrough(entry.status == "completed" || entry.status == "cancelled")
                    }
                }
            }
            if !extraPlanMarkdown.isEmpty {
                Text(extraPlanMarkdown)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            if PlanSurface.showsApprove(modeIsPlan: model.client.mode == .plan) {
                TextField(l10n.t("Request changes…", "打回意见…"), text: $planNote)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .grokFieldChrome(cornerRadius: 8)
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, checklist.isEmpty ? 0 : 4)
                ForEach(liveWorkItems) { item in
                    liveWorkRow(item)
                }
            }
            if !model.client.scheduledTasks.isEmpty {
                Text(l10n.t("Loops", "循环任务"))
                    .font(.system(size: 11, weight: .semibold))
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
                                .foregroundStyle(palette.tertiary)
                        }
                        Spacer()
                        Button(l10n.stop) {
                            model.cancelScheduledTask(task)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.warning)
                    }
                }
            }
            if !finishedSubagents.isEmpty {
                Text(l10n.subagents)
                    .font(.system(size: 11, weight: .semibold))
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
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.tertiary)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .grokHover(cornerRadius: 7)
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
            RunningStatusIcon(active: true, idleSystemImage: "circle", color: palette.warning, size: 12)
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
                        .foregroundStyle(palette.warning)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
        }
        if let agent = item.subagent {
            Button {
                model.openSubagent(agent)
            } label: {
                row.padding(6).grokHover(cornerRadius: 7)
            }
            .buttonStyle(.plain)
        } else if let sessionID = item.sessionID {
            Button {
                _ = model.client.focusIfLoaded(sessionID)
            } label: {
                row.padding(6).grokHover(cornerRadius: 7)
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
            || keepsPlan
            || !liveWorkItems.isEmpty
            || model.client.mode == .plan
            || !model.client.scheduledTasks.isEmpty
            || !finishedSubagents.isEmpty
    }

    private var keepsPlan: Bool {
        PlanSurface.keepsBody(entryCount: model.client.planEntries.count, markdown: model.client.planMarkdown)
    }

    private var planIsChecklist: Bool {
        model.client.mode == .plan || (model.client.todos.isEmpty && !model.client.planEntries.isEmpty)
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
                                .font(.system(size: 10.5))
                                .foregroundStyle(event.blocked ? palette.warning : palette.secondary)
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
                            .font(.system(size: 10.5))
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
        let listed = Set((checklist.map(\.content) + model.client.planEntries.map(\.content)).map { $0.lowercased() })
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
        case "completed": return palette.success
        case "in_progress": return palette.warning
        case "cancelled": return palette.tertiary
        default: return palette.tertiary
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
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.tertiary)
                    Text(model.workspace.branch ?? "HEAD")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                    Spacer()
                    Text("+\(model.workspace.insertions)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.success)
                    Text("-\(model.workspace.deletions)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.danger)
                }
            }
            if !model.client.gitStatusText.isEmpty {
                Text(model.client.gitStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
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
                ChangeNoteField(
                    sessionID: model.client.sessionID ?? "",
                    path: "",
                    excerpt: String(model.client.gitDiffText.prefix(DiffNote.excerptLimit)),
                    asDiff: DiffNote.looksLikeDiff(model.client.gitDiffText)
                )
            }
            if model.client.hunks.isEmpty && scannedDiffs.isEmpty && model.client.gitDiffText.isEmpty {
                Text(l10n.t("No session diffs yet.", "这一轮还没有 diff。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else if !model.client.hunks.isEmpty, scannedDiffs.isEmpty {
                ForEach(model.client.hunks) { hunk in
                    let url = ChatLinkDetector.resolve(hunk.path, baseDirectory: model.client.workingDirectory)?.url
                        ?? URL(fileURLWithPath: hunk.path)
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            model.previewFile(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.tertiary)
                                Text(hunk.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.text)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(hunk.added)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.success)
                                Text("-\(hunk.removed)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.danger)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .grokHover(cornerRadius: 7)
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(hunk.path)
                        .contextMenu { ChatLinkContextButtons(url: url) }
                        ChangeNoteField(
                            sessionID: model.client.sessionID ?? "",
                            path: hunk.path,
                            excerpt: DiffNote.countLine(added: hunk.added, removed: hunk.removed),
                            asDiff: false
                        )
                    }
                }
            }
        }
    }

    private var scannedDiffs: [DiffFile] {
        DiffScan.parse(model.client.gitDiffText)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }

    private func paneHeader<Extra: View>(_ pane: InspectorPane, title: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(spacing: 6) {
            sectionTitle(title)
            Spacer(minLength: 4)
            extra()
            paneClose(pane)
                .opacity(hoveredPane == pane ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hoveredPane == pane)
        }
    }

    private func paneClose(_ pane: InspectorPane) -> some View {
        GrokIconButton(
            systemImage: "xmark",
            size: 18,
            iconSize: 8.5,
            cornerRadius: 5,
            helpText: l10n.t("Hide this section", "关闭这个区块")
        ) {
            model.hideInspectorPane(pane)
        }
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

struct InspectorPanelsMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(InspectorPane.allCases) { pane in
                Toggle(
                    pane.title(chinese: l10n.language == .chinese),
                    isOn: Binding(
                        get: { model.inspectorPaneVisible(pane) },
                        set: { model.setInspectorPane(pane, visible: $0) }
                    )
                )
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? palette.text : palette.secondary)
                .frame(width: 26, height: 26)
                .background(
                    hovering ? palette.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(l10n.t("Open or close sidebar tools", "打开或关闭右边栏里的功能"))
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
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(palette.tertiary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                Button {
                    model.previewFile(url)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.tertiary)
                        Text(file.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .grokHover(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help(file.path)
                .contextMenu { ChatLinkContextButtons(url: url) }

                Spacer()
                Text("+\(file.added)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.success)
                Text("-\(file.removed)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.danger)
            }
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
                                .padding(.vertical, 1.5)
                                .background(background(for: line.kind), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    if file.lines.count > 40 {
                        Text("+\(file.lines.count - 40)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(4)
                .background(palette.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                ChangeNoteField(
                    sessionID: model.client.sessionID ?? "",
                    path: file.path,
                    excerpt: DiffNote.excerpt(from: file),
                    asDiff: true
                )
            }
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return palette.success
        case .removed: return palette.danger
        case .header: return palette.secondary
        case .meta, .context: return palette.text
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return palette.success.opacity(0.12)
        case .removed: return palette.danger.opacity(0.12)
        default: return .clear
        }
    }
}

struct ChangeNoteField: View {
    let sessionID: String
    let path: String
    let excerpt: String
    var asDiff: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(l10n.t("Comment on this change…", "对这里写一句…"), text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($focused)
                .onSubmit(send)
            Button(l10n.t("Send", "发送"), action: send)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(canSend ? palette.text : palette.tertiary)
                .disabled(!canSend)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .grokFieldChrome(cornerRadius: 8, focused: focused)
    }

    private var canSend: Bool {
        !sessionID.isEmpty && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, !trimmed.isEmpty else { return }
        note = ""
        model.commentOnChange(sessionID: sessionID, path: path, excerpt: excerpt, note: trimmed, asDiff: asDiff)
    }
}
