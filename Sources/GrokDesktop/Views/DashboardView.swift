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

            if roster.isEmpty {
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
                        ForEach(roster) { workspace in
                            liveCard(workspace)
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
    }

    private var roster: [SessionWorkspace] {
        model.client.liveWorkspaces.sorted { rank($0) < rank($1) }
    }

    private var dispatchBar: some View {
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

    private func liveCard(_ workspace: SessionWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RunningStatusIcon(
                    active: workspace.isTurnRunning || workspace.tasks.contains(where: \.isRunning),
                    idleSystemImage: workspace.permission != nil || workspace.userQuestion != nil
                        ? "exclamationmark.circle"
                        : "checkmark.circle",
                    color: workspace.permission != nil || workspace.userQuestion != nil ? .orange : palette.secondary,
                    size: 12
                )
                Text(statusText(workspace))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(workspace.mode.title(chinese: model.language.resolved() == .chinese))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            Text(workspace.title.isEmpty ? workspace.cwd.lastPathComponent : workspace.title)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
            Text(workspace.cwd.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .help(workspace.cwd.path)
            if !workspace.subagents.isEmpty {
                Text("\(workspace.subagents.filter(\.isRunning).count)/\(workspace.subagents.count) \(l10n.subagents)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }

            if let question = workspace.userQuestion {
                QuestionCard(request: question, sessionID: workspace.id, inset: false)
            } else if let permission = workspace.permission {
                PermissionBar(request: permission, sessionID: workspace.id, inset: false)
            }

            HStack {
                Text("\(workspace.runningTools) \(l10n.running)")
                Text("\(workspace.finishedTools) \(l10n.completed)")
                    .foregroundStyle(palette.secondary)
                Spacer()
                Button(l10n.t("Open", "打开")) {
                    _ = model.client.focusIfLoaded(workspace.id)
                    model.destination = .build
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                if workspace.isLive {
                    Button(l10n.stop) { model.client.stopWork(sessionID: workspace.id) }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            .font(.system(size: 13))
        }
        .padding(16)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rank(_ workspace: SessionWorkspace) -> Int {
        if workspace.userQuestion != nil { return 0 }
        if workspace.permission != nil { return 1 }
        if workspace.isTurnRunning { return 2 }
        return 3
    }

    private func statusText(_ workspace: SessionWorkspace) -> String {
        if workspace.permission != nil { return l10n.t("Needs approval", "等待批准") }
        if workspace.userQuestion != nil { return l10n.t("Waiting for an answer", "等待回答") }
        if workspace.isTurnRunning { return l10n.running }
        if workspace.tasks.contains(where: \.isRunning) || workspace.subagents.contains(where: \.isRunning) {
            return l10n.t("Background work", "后台还在跑")
        }
        if !workspace.promptQueue.isEmpty { return l10n.t("Queued", "排队中") }
        return l10n.t("Awaiting input", "等待输入")
    }
}
