import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var planNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l10n.inspector)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.showInspector = false
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.inspector)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(palette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextSection
                    tasksSection
                    planSection
                    changesSection
                    timelineSection
                    workflowsSection
                    personasSection
                    docsSection
                    subagentSection
                }
                .padding(14)
            }
        }
        .background(palette.sidebar)
        .onAppear {
            model.refreshWorkspace()
            model.client.refreshPlanArtifacts()
            Task { await model.client.refreshGit() }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Context", "上下文"))
            HStack {
                Text("\(model.workspace.contextPercent)%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
                Text(l10n.sessionContext)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.chip)
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(min(max(model.workspace.contextPercent, 0), 100)) / 100)
                }
            }
            .frame(height: 6)
            Text(model.client.workingDirectory.path)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
            connectionLine
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

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(l10n.tasks)
                Spacer()
                if todoProgress.total > 0 {
                    Text("\(todoProgress.done)/\(todoProgress.total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
            }
            if todoProgress.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.chip)
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(todoProgress.done) / CGFloat(max(todoProgress.total, 1)))
                    }
                }
                .frame(height: 6)
            }
            if model.client.todos.isEmpty && model.client.tasks.isEmpty {
                Text(l10n.noTasks)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            ForEach(model.client.todos) { todo in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: todoIcon(todo.status))
                        .font(.system(size: 11))
                        .foregroundStyle(todoColor(todo.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todo.content)
                            .font(.system(size: 12))
                            .strikethrough(todo.isDone || todo.isCancelled)
                        Text(todoStatusLabel(todo.status))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
            if !model.client.tasks.isEmpty {
                Text(l10n.backgroundTasks)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                ForEach(Array(model.client.tasks.suffix(12))) { task in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: task.isRunning ? "circle.dotted" : "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(task.isRunning ? Color.orange : palette.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(task.isRunning ? l10n.running : l10n.completed)
                                if let elapsed = task.elapsed {
                                    Text(elapsedLabel(elapsed))
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
        }
    }

    private var todoProgress: (done: Int, total: Int) {
        PromptTimestamp.progress(for: model.client.todos)
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

    private func elapsedLabel(_ value: TimeInterval) -> String {
        if value < 60 { return String(format: "%.0fs", value) }
        if value < 3600 { return String(format: "%.0fm", value / 60) }
        return String(format: "%.1fh", value / 3600)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Plan")
            if model.client.planEntries.isEmpty && model.client.planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(l10n.t("No plan.md yet. You can still approve, request changes, or quit plan mode.", "还没有 plan.md。仍可批准、打回或退出 Plan。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(model.client.planEntries) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: entry.status == "completed" ? "checkmark.circle" : (entry.status == "in_progress" ? "circle.dotted" : "circle"))
                            .font(.system(size: 11))
                        Text(entry.content)
                            .font(.system(size: 12))
                    }
                }
                if !model.client.planMarkdown.isEmpty {
                    Text(model.client.planMarkdown)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .textSelection(.enabled)
                        .lineLimit(16)
                }
            }
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
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.changes)
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
            if !model.client.gitDiffText.isEmpty {
                Text(model.client.gitDiffText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(16)
            }
            if model.client.hunks.isEmpty && model.client.gitDiffText.isEmpty {
                Text(l10n.t("No session diffs yet.", "这一轮还没有 diff。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else if !model.client.hunks.isEmpty {
                ForEach(model.client.hunks) { hunk in
                    HStack {
                        Text(hunk.name)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(hunk.added)")
                            .foregroundStyle(.green)
                        Text("-\(hunk.removed)")
                            .foregroundStyle(.red)
                    }
                    .font(.system(size: 12))
                    .help(hunk.path)
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Timeline", "时间线"))
            let users = model.client.items.compactMap { item -> String? in
                if case .user(_, let text) = item { return text }
                return nil
            }
            if users.isEmpty {
                Text(l10n.t("No turns yet.", "还没有回合。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(Array(users.enumerated()), id: \.offset) { index, text in
                    Text("\(index + 1). \(text)")
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
            }
        }
    }

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Workflows", "工作流"))
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
            sectionTitle(l10n.t("Agents / personas", "Agent / 人设"))
            if model.personas.isEmpty {
                Text(l10n.t("None on disk.", "磁盘上没有人设。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(model.personas.prefix(8), id: \.self) { name in
                    Button {
                        model.destination = .chat
                        model.draft = "/agents \(name) "
                    } label: {
                        Text(name).font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var docsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Docs", "文档"))
            Button("docs.x.ai/build") { model.openDocs() }
                .buttonStyle(GrokSecondaryButtonStyle())
            Button("CHANGELOG") { model.openChangelog() }
                .buttonStyle(GrokSecondaryButtonStyle())
        }
    }

    private var subagentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.subagents)
            HStack {
                Text("\(model.client.runningTools) \(l10n.running)")
                Spacer()
                Text("\(model.client.finishedTools) \(l10n.completed)")
                    .foregroundStyle(palette.secondary)
            }
            .font(.system(size: 13))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }
}
