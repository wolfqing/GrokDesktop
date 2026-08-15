import GrokDesktopCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: l10n.liveAgents,
                subtitle: l10n.t("Only work that is running right now.", "只看此刻还在跑的任务。")
            ) {
                Button(l10n.newChat) { model.startNewSession() }
                    .buttonStyle(GrokPrimaryButtonStyle())
            }

            if model.client.liveWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("Nothing is running.", "现在没有进行中的任务。"))
                        .font(.system(size: 15, weight: .medium))
                    Text(l10n.t("Start a chat when you want to dispatch work.", "要派活时，开一个新对话就行。"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.top, 8)
            } else {
                ForEach(model.client.liveWorkspaces) { workspace in
                    liveCard(workspace)
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }

    private func liveCard(_ workspace: SessionWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RunningStatusIcon(
                    active: workspace.isTurnRunning || workspace.tasks.contains(where: \.isRunning),
                    idleSystemImage: workspace.permission != nil ? "exclamationmark.circle" : "checkmark.circle",
                    color: workspace.permission != nil ? .orange : palette.secondary,
                    size: 12
                )
                Text(statusText(workspace))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(workspace.mode.title(chinese: model.language.resolved() == .chinese))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            Text(workspace.cwd.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .help(workspace.cwd.path)
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
                Button(l10n.t("Open", "打开")) {
                    _ = model.client.focusIfLoaded(workspace.id)
                    model.destination = .chat
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                if workspace.isTurnRunning || workspace.todos.contains(where: \.isActive) || workspace.tasks.contains(where: \.isRunning) {
                    Button(l10n.stop) { model.client.stopWork(sessionID: workspace.id) }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            .font(.system(size: 13))
        }
        .padding(16)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
