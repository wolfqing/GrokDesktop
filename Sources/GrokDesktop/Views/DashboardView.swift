import GrokDesktopCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var dispatchDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: l10n.liveAgents,
                subtitle: l10n.t("Dispatch work, then handle anything that is waiting.", "派活，并处理正在等你的会话。")
            )

            dispatchBar

            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("Nothing is running.", "现在没有进行中的任务。"))
                        .font(.system(size: 15, weight: .medium))
                    Text(l10n.t("Type a job above to start a new agent.", "在上面输入任务，派一个新 agent。"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { row in
                            card(row)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
        .onAppear { model.noteDashboardVisible() }
    }

    private var rows: [DashboardRow] {
        var next: [DashboardRow] = model.visiblePendingDispatches.map { .pending($0) }
        next += model.client.liveWorkspaces.map { .live($0) }
        let liveIDs = Set(model.client.liveWorkspaces.map(\.id))
        next += model.unseenTurns.filter { !liveIDs.contains($0.id) }.map { .unseen($0) }
        return next.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.stamp > rhs.stamp
        }
    }

    private var dispatchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    l10n.t("Dispatch a new agent…", "派一个新任务…"),
                    text: $dispatchDraft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .onSubmit(dispatch)

                Button(action: dispatch) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canDispatch ? palette.sendGlyph : palette.secondary)
                        .frame(width: 30, height: 30)
                        .background(canDispatch ? palette.send : palette.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canDispatch)
                .help(l10n.t("Dispatch", "派活"))
            }

            Menu {
                ForEach(model.dispatchProjects) { project in
                    Button {
                        model.setDispatchDirectory(URL(fileURLWithPath: project.path))
                    } label: {
                        if model.isCurrentProject(project) {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
                Divider()
                Button(l10n.t("Choose Folder…", "选择文件夹…")) {
                    model.chooseDispatchDirectory()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(model.client.workingDirectory.lastPathComponent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(model.client.workingDirectory.path)
        }
        .padding(14)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private var canDispatch: Bool {
        !dispatchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dispatch() {
        let text = dispatchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dispatchDraft = ""
        model.dispatchWork(text)
    }

    @ViewBuilder
    private func card(_ row: DashboardRow) -> some View {
        switch row {
        case .pending(let pending):
            pendingCard(pending)
        case .live(let workspace):
            liveCard(workspace)
        case .unseen(let turn):
            unseenCard(turn)
        }
    }

    private func pendingCard(_ pending: PendingDispatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine(
                active: pending.error == nil,
                symbol: pending.error == nil ? "circle" : "exclamationmark.circle",
                tint: pending.error == nil ? palette.secondary : .orange,
                title: pending.error == nil
                    ? l10n.t("Starting…", "正在开始…")
                    : l10n.t("Didn't start", "没发出去")
            )
            promptLine(pending.text)
            repoLine(placeLine(folder: pending.cwdName, isolated: pending.isolated), path: pending.cwd)
            if let error = pending.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(3)
                Button(l10n.t("Dismiss", "关掉")) { model.dismissDispatch(pending.id) }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func liveCard(_ workspace: SessionWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.openDashboardItem(workspace.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    statusLine(
                        active: workspace.isTurnRunning || workspace.tasks.contains(where: \.isRunning),
                        symbol: workspace.permission != nil || workspace.userQuestion != nil
                            ? "exclamationmark.circle"
                            : "checkmark.circle",
                        tint: workspace.permission != nil || workspace.userQuestion != nil ? .orange : palette.secondary,
                        title: statusText(workspace),
                        trailing: workspace.mode.title(chinese: model.language.resolved() == .chinese)
                    )
                    promptLine(headline(workspace))
                    repoLine(
                        placeLine(folder: workspace.cwd.lastPathComponent, isolated: workspace.isolatedCopy),
                        path: workspace.cwd.path
                    )
                    if !workspace.subagents.isEmpty {
                        Text("\(workspace.subagents.filter(\.isRunning).count)/\(workspace.subagents.count) \(l10n.subagents)")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                    HStack {
                        Text("\(workspace.runningTools) \(l10n.running)")
                        Text("\(workspace.finishedTools) \(l10n.completed)")
                            .foregroundStyle(palette.secondary)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(palette.text)
                }
            }
            .buttonStyle(.plain)

            if let question = workspace.userQuestion {
                QuestionCard(request: question, sessionID: workspace.id, inset: false)
            } else if let permission = workspace.permission {
                PermissionBar(request: permission, sessionID: workspace.id, inset: false)
            }

            if workspace.isLive {
                Button(l10n.stop) { model.client.stopWork(sessionID: workspace.id) }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func unseenCard(_ turn: UnseenTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.openDashboardItem(turn.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    statusLine(
                        active: false,
                        symbol: turn.failed ? "exclamationmark.circle" : "checkmark.circle",
                        tint: turn.failed ? .orange : palette.secondary,
                        title: turn.failed
                            ? l10n.t("Failed, not opened", "出错了，还没看")
                            : l10n.t("Finished, not opened", "跑完了，还没看")
                    )
                    promptLine(turn.prompt.isEmpty ? turn.cwdName : turn.prompt)
                    repoLine(
                        turn.cardLine(chinese: model.language.resolved() == .chinese),
                        path: turn.cwd
                    )
                }
            }
            .buttonStyle(.plain)
            ForEach(model.unseenHunks[turn.id] ?? []) { hunk in
                ChangeNoteField(
                    sessionID: turn.id,
                    path: hunk.path,
                    excerpt: DiffNote.countLine(added: hunk.added, removed: hunk.removed),
                    asDiff: false
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func placeLine(folder: String, isolated: Bool) -> String {
        DispatchIsolation.line(
            folder: folder,
            place: isolated ? .isolatedCopy : .currentDirectory,
            chinese: model.language.resolved() == .chinese
        )
    }

    private func statusLine(
        active: Bool,
        symbol: String,
        tint: Color,
        title: String,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            RunningStatusIcon(active: active, idleSystemImage: symbol, color: tint, size: 12)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func promptLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func repoLine(_ name: String, path: String) -> some View {
        Text(name)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
            .help(path)
    }

    private func headline(_ workspace: SessionWorkspace) -> String {
        let prompt = workspace.latestUserPrompt
        if !prompt.isEmpty { return prompt }
        if !workspace.title.isEmpty { return workspace.title }
        return workspace.cwd.lastPathComponent
    }

    private func statusText(_ workspace: SessionWorkspace) -> String {
        if workspace.userQuestion != nil { return l10n.t("Waiting for an answer", "等待回答") }
        if workspace.permission != nil { return l10n.t("Needs approval", "等待批准") }
        if workspace.isTurnRunning { return l10n.running }
        if workspace.tasks.contains(where: \.isRunning) || workspace.subagents.contains(where: \.isRunning) {
            return l10n.t("Background work", "后台还在跑")
        }
        if !workspace.promptQueue.isEmpty { return l10n.t("Queued", "排队中") }
        return l10n.t("Awaiting input", "等待输入")
    }
}

private enum DashboardRow: Identifiable {
    case pending(PendingDispatch)
    case live(SessionWorkspace)
    case unseen(UnseenTurn)

    var id: String {
        switch self {
        case .pending(let item): return "pending-\(item.id)"
        case .live(let workspace): return "live-\(workspace.id)"
        case .unseen(let turn): return "unseen-\(turn.id)"
        }
    }

    var rank: Int {
        switch self {
        case .pending(let item):
            return item.error == nil ? 3 : 2
        case .live(let workspace):
            if workspace.userQuestion != nil { return 0 }
            if workspace.permission != nil { return 1 }
            return 3
        case .unseen:
            return 2
        }
    }

    var stamp: TimeInterval {
        switch self {
        case .pending:
            return Date.distantFuture.timeIntervalSince1970
        case .live:
            return 0
        case .unseen(let turn):
            return turn.finishedAt.timeIntervalSince1970
        }
    }
}
