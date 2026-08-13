import GrokDesktopCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(l10n.liveAgents)
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button(l10n.newChat) { model.startNewSession() }
                    .buttonStyle(GrokPrimaryButtonStyle())
            }

            if model.client.liveWorkspaces.isEmpty {
                Text(l10n.t("No live agents. Start a chat to dispatch work.", "没有进行中的 agent。开一个会话开始干活。"))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 12)
            } else {
                ForEach(model.client.liveWorkspaces) { workspace in
                    liveCard(workspace)
                }
            }

            Text(l10n.history)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.filteredSessions.prefix(20)) { session in
                        Button {
                            model.open(session)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(model.client.sessionID == session.id && model.client.isLive ? Color.orange : palette.hairline)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(palette.text)
                                        .lineLimit(1)
                                    Text(session.cwd)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(session.model ?? "")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            .padding(12)
                            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }

    private func liveCard(_ workspace: SessionWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statusText(workspace))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(workspace.mode.title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            Text(workspace.cwd.path)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            HStack {
                Text("\(workspace.runningTools) \(l10n.running)")
                Text("\(workspace.finishedTools) \(l10n.completed)")
                    .foregroundStyle(palette.secondary)
                Spacer()
                Button(l10n.t("Open", "打开")) {
                    if !model.client.focusIfLoaded(workspace.id) {
                        model.destination = .chat
                    } else {
                        model.destination = .chat
                    }
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
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hairline))
    }

    private func statusText(_ workspace: SessionWorkspace) -> String {
        if workspace.permission != nil { return l10n.t("Needs approval", "等待批准") }
        if workspace.isTurnRunning { return l10n.running }
        if !workspace.promptQueue.isEmpty { return l10n.t("Queued", "排队中") }
        return l10n.t("Awaiting input", "等待输入")
    }
}
