import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var commands: [(String, String)] {
        var rows = [
            ("/new", l10n.newChat),
            ("/resume", l10n.t("Resume session", "恢复会话")),
            ("/settings", l10n.settings),
            ("/dashboard", l10n.liveAgents),
            ("/plan", l10n.t("Enter Plan mode", "进入 Plan 模式")),
            ("/jump", l10n.t("Jump to latest", "跳到最新")),
            ("/rewind", l10n.t("Rewind last turn", "回退上一轮")),
            ("/compact", l10n.t("Compact context", "压缩上下文")),
            ("/feedback", l10n.t("Feedback", "反馈")),
            ("/login", l10n.loginGrok),
            ("/logout", l10n.t("Sign out", "退出登录")),
            ("/rename", l10n.t("Rename session", "重命名会话")),
            ("/delete", l10n.t("Delete session", "删除会话")),
            ("/export", l10n.t("Export session", "导出会话")),
            ("/copy", l10n.t("Copy last reply", "复制上一条回复")),
            ("/fork", l10n.t("Fork session", "分叉会话")),
            ("/imagine", l10n.imagine),
            ("/context", l10n.t("Session info", "会话信息")),
            ("/docs", l10n.t("Docs", "文档")),
            ("/changelog", "CHANGELOG"),
            ("/usage", l10n.usage),
            ("/home", l10n.t("Home", "回到首页")),
            ("/quit", l10n.t("Quit", "退出"))
        ]
        rows.append(contentsOf: model.skills.prefix(12).map { ("/\($0.slug)", $0.title) })
        return rows
    }

    var body: some View {
        ZStack {
            palette.overlay
                .ignoresSafeArea()
                .onTapGesture { model.showPalette = false }

            VStack(alignment: .leading, spacing: 0) {
                Text(l10n.t("Commands", "命令"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(12)
                ForEach(filtered, id: \.0) { command in
                    Button {
                        model.handleCommand(command.0)
                        model.draft = ""
                    } label: {
                        HStack {
                            Text(command.0)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                            Spacer()
                            Text(command.1)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 420)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
            .offset(y: 120)
        }
    }

    private var filtered: [(String, String)] {
        let query = model.draft.lowercased()
        if query.count <= 1 { return commands }
        return commands.filter { $0.0.contains(query) || $0.1.localizedCaseInsensitiveContains(query) }
    }
}
