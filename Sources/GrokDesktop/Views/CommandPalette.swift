import GrokDesktopCore
import SwiftUI

struct CommandItem: Identifiable {
    var id: String { command }
    var command: String
    var title: String
    var detail: String
    var icon: String
    var section: String
}

private struct SuggestHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ComposerSuggestChrome<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SuggestHeightKey.self, value: geo.size.height)
                }
            )
        }
        .scrollIndicators(.visible)
        .onPreferenceChange(SuggestHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 1), 320))
        .background(palette.popover)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
    }
}

struct SuggestRow: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    var detail: String = ""
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(palette.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                selected ? palette.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

struct SuggestSection: View {
    @Environment(\.palette) private var palette
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    var embedded = false

    @State private var hovered: String?

    var body: some View {
        let list = ComposerSuggestChrome {
            ForEach(grouped, id: \.title) { group in
                SuggestSection(title: group.title)
                ForEach(group.items) { item in
                    SuggestRow(
                        icon: item.icon,
                        title: item.title,
                        detail: item.detail,
                        selected: hovered == item.id
                    ) {
                        model.handleCommand(item.command)
                        model.draft = ""
                    }
                    .onHover { hovering in
                        hovered = hovering ? item.id : (hovered == item.id ? nil : hovered)
                    }
                }
            }
        }

        if embedded {
            list
        } else {
            ZStack {
                palette.overlay
                    .ignoresSafeArea()
                    .onTapGesture { model.showPalette = false }
                list
                    .frame(width: 520)
            }
        }
    }

    private var grouped: [(title: String, items: [CommandItem])] {
        let query = model.draft.lowercased()
        let items = commands.filter { item in
            if query.count <= 1 { return true }
            return item.command.lowercased().contains(query)
                || item.title.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
        }
        var result: [(title: String, items: [CommandItem])] = []
        for section in [l10n.t("Session", "会话"), l10n.t("App", "应用"), l10n.t("Account", "账号"), l10n.t("Skills", "技能")] {
            let rows = items.filter { $0.section == section }
            if !rows.isEmpty {
                result.append((section, rows))
            }
        }
        return result
    }

    private var commands: [CommandItem] {
        var rows: [CommandItem] = [
            .init(command: "/new", title: l10n.newChat, detail: l10n.t("Start a new conversation", "开始新对话"), icon: "plus.circle", section: l10n.t("Session", "会话")),
            .init(command: "/resume", title: l10n.t("Resume", "恢复会话"), detail: l10n.t("Open a previous session", "打开之前的会话"), icon: "clock.arrow.circlepath", section: l10n.t("Session", "会话")),
            .init(command: "/plan", title: l10n.t("Plan mode", "计划模式"), detail: l10n.t("Switch into Plan mode", "切换到 Plan 模式"), icon: "point.topleft.down.to.point.bottomright.curvepath", section: l10n.t("Session", "会话")),
            .init(command: "/compact", title: l10n.t("Compact", "压缩"), detail: l10n.t("Compact this conversation", "压缩当前对话上下文"), icon: "rectangle.compress.vertical", section: l10n.t("Session", "会话")),
            .init(command: "/rewind", title: l10n.t("Rewind", "回退"), detail: l10n.t("Undo the last turn", "回退上一轮"), icon: "arrow.uturn.backward", section: l10n.t("Session", "会话")),
            .init(command: "/jump", title: l10n.t("Jump to latest", "跳到最新"), detail: l10n.t("Scroll to the newest message", "滚到最新消息"), icon: "arrow.down.to.line", section: l10n.t("Session", "会话")),
            .init(command: "/fork", title: l10n.t("Fork", "分叉"), detail: l10n.t("Continue in a new session", "在新会话中继续"), icon: "arrow.triangle.branch", section: l10n.t("Session", "会话")),
            .init(command: "/copy", title: l10n.t("Copy last reply", "复制上一条回复"), detail: l10n.t("Copy the latest Grok reply", "复制最新回复"), icon: "square.on.square", section: l10n.t("Session", "会话")),
            .init(command: "/rename", title: l10n.t("Rename", "重命名"), detail: l10n.t("Rename this session", "重命名当前会话"), icon: "pencil", section: l10n.t("Session", "会话")),
            .init(command: "/export", title: l10n.t("Export", "导出"), detail: l10n.t("Export this session", "导出会话"), icon: "square.and.arrow.up", section: l10n.t("Session", "会话")),
            .init(command: "/delete", title: l10n.t("Delete", "删除"), detail: l10n.t("Delete this session", "删除当前会话"), icon: "trash", section: l10n.t("Session", "会话")),
            .init(command: "/usage", title: l10n.usage, detail: l10n.t("Open usage and billing", "打开用量和账单"), icon: "chart.bar", section: l10n.t("App", "应用")),
            .init(command: "/settings", title: l10n.settings, detail: l10n.t("Open settings", "打开设置"), icon: "gearshape", section: l10n.t("App", "应用")),
            .init(command: "/dashboard", title: l10n.liveAgents, detail: l10n.t("Show live agents", "查看进行中的任务"), icon: "rectangle.3.group", section: l10n.t("App", "应用")),
            .init(command: "/imagine", title: l10n.imagine, detail: l10n.t("Generate an image", "生成图片"), icon: "photo", section: l10n.t("App", "应用")),
            .init(command: "/context", title: l10n.t("Session info", "会话信息"), detail: l10n.t("Show context and model", "显示上下文和模型"), icon: "info.circle", section: l10n.t("App", "应用")),
            .init(command: "/docs", title: l10n.t("Docs", "文档"), detail: l10n.t("Open Grok Build docs", "打开 Grok Build 文档"), icon: "book", section: l10n.t("App", "应用")),
            .init(command: "/changelog", title: "CHANGELOG", detail: l10n.t("Open the changelog", "打开更新日志"), icon: "list.bullet.rectangle", section: l10n.t("App", "应用")),
            .init(command: "/home", title: l10n.t("Home", "首页"), detail: l10n.t("Back to the empty chat", "回到空白对话"), icon: "house", section: l10n.t("App", "应用")),
            .init(command: "/feedback", title: l10n.t("Feedback", "反馈"), detail: l10n.t("Send feedback about this chat", "发送关于此对话的反馈"), icon: "text.bubble", section: l10n.t("App", "应用")),
            .init(command: "/login", title: l10n.loginGrok, detail: l10n.t("Sign in to grok.com", "登录 grok.com"), icon: "person.crop.circle", section: l10n.t("Account", "账号")),
            .init(command: "/logout", title: l10n.t("Sign out", "退出登录"), detail: l10n.t("Sign out of this machine", "退出本机登录"), icon: "rectangle.portrait.and.arrow.right", section: l10n.t("Account", "账号")),
            .init(command: "/quit", title: l10n.t("Quit", "退出"), detail: l10n.t("Quit Grok Desktop", "退出 Grok Desktop"), icon: "xmark.circle", section: l10n.t("Account", "账号"))
        ]
        rows.append(contentsOf: model.skills.prefix(20).map {
            CommandItem(
                command: "/\($0.slug)",
                title: $0.title,
                detail: $0.slug,
                icon: "sparkles",
                section: l10n.t("Skills", "技能")
            )
        })
        return rows
    }
}
