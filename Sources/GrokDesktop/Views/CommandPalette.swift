import GrokDesktopCore
import SwiftUI

struct CommandItem: Identifiable {
    var id: String
    var command: String
    var title: String
    var detail: String
    var icon: String
    var section: String
    var insertsIntoDraft = false

    init(
        id: String? = nil,
        command: String,
        title: String,
        detail: String,
        icon: String,
        section: String,
        insertsIntoDraft: Bool = false
    ) {
        self.id = id ?? command
        self.command = command
        self.title = title
        self.detail = detail
        self.icon = icon
        self.section = section
        self.insertsIntoDraft = insertsIntoDraft
    }
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
                        if item.insertsIntoDraft {
                            model.insertSlashPrompt(item.command)
                        } else {
                            model.handleCommand(item.command)
                            model.draft = ""
                        }
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
        for section in [
            l10n.t("Session", "会话"),
            l10n.t("Mode", "模式"),
            l10n.t("Memory", "记忆"),
            l10n.t("Media", "媒体"),
            l10n.t("App", "应用"),
            l10n.t("Account", "账号"),
            l10n.t("Skills", "技能")
        ] {
            let rows = items.filter { $0.section == section }
            if !rows.isEmpty {
                result.append((section, rows))
            }
        }
        return result
    }

    private var commands: [CommandItem] {
        let session = l10n.t("Session", "会话")
        let mode = l10n.t("Mode", "模式")
        let memory = l10n.t("Memory", "记忆")
        let media = l10n.t("Media", "媒体")
        let app = l10n.t("App", "应用")
        let account = l10n.t("Account", "账号")
        let skills = l10n.t("Skills", "技能")
        var rows: [CommandItem] = [
            .init(command: "/new", title: l10n.newChat, detail: l10n.t("Start a new conversation", "开始新对话"), icon: "plus.circle", section: session),
            .init(command: "/resume", title: l10n.t("Resume", "恢复会话"), detail: l10n.t("Open a previous session", "打开之前的会话"), icon: "clock.arrow.circlepath", section: session),
            .init(command: "/continue", title: l10n.t("Continue", "继续上次"), detail: l10n.t("Resume the last chat in this folder", "继续这个文件夹最近一次会话"), icon: "arrow.uturn.forward", section: session),
            .init(command: "/history", title: l10n.t("History", "提示词历史"), detail: l10n.t("Search earlier prompts", "搜索之前发过的提示词"), icon: "clock", section: session),
            .init(command: "/plan", title: l10n.t("Plan mode", "计划模式"), detail: l10n.t("Switch into Plan mode", "切换到计划模式"), icon: "point.topleft.down.to.point.bottomright.curvepath", section: session),
            .init(command: "/view-plan", title: l10n.t("View plan", "查看计划"), detail: l10n.t("Open the saved plan", "打开当前计划"), icon: "list.bullet.rectangle", section: session),
            .init(command: "/compact", title: l10n.t("Compact", "压缩"), detail: l10n.t("Compact this conversation", "压缩当前对话上下文"), icon: "rectangle.compress.vertical", section: session),
            .init(command: "/rewind", title: l10n.t("Rewind", "回退"), detail: l10n.t("Undo the last turn", "回退上一轮"), icon: "arrow.uturn.backward", section: session),
            .init(command: "/jump", title: l10n.t("Jump to latest", "跳到最新"), detail: l10n.t("Scroll to the newest message", "滚到最新消息"), icon: "arrow.down.to.line", section: session),
            .init(command: "/fork", title: l10n.t("Fork", "分叉"), detail: l10n.t("Continue in a new session", "在新会话中继续"), icon: "arrow.triangle.branch", section: session),
            .init(command: "/copy", title: l10n.t("Copy last reply", "复制上一条回复"), detail: l10n.t("Copy the latest Grok reply", "复制最新回复"), icon: "square.on.square", section: session),
            .init(command: "/rename", title: l10n.t("Rename", "重命名"), detail: l10n.t("Rename this session", "重命名当前会话"), icon: "pencil", section: session),
            .init(command: "/export", title: l10n.t("Export", "导出"), detail: l10n.t("Export this session", "导出会话"), icon: "square.and.arrow.up", section: session),
            .init(command: "/delete", title: l10n.t("Delete", "删除"), detail: l10n.t("Delete this session", "删除当前会话"), icon: "trash", section: session),
            .init(command: "/model", title: l10n.t("Model", "模型"), detail: l10n.t("Switch model, optionally with effort", "切换模型，可带推理强度"), icon: "cpu", section: mode, insertsIntoDraft: true),
            .init(command: "/effort", title: l10n.t("Effort", "推理强度"), detail: l10n.t("low / medium / high / xhigh", "低 / 中 / 高 / 极高"), icon: "gauge", section: mode, insertsIntoDraft: true),
            .init(command: "/always-approve", title: l10n.t("Always approve", "全权"), detail: l10n.t("Toggle skip-all-permissions", "切换为不再询问"), icon: "checkmark.shield", section: mode),
            .init(command: "/auto", title: l10n.t("Auto", "自动"), detail: l10n.t("Toggle classifier approvals", "切换自动批准安全操作"), icon: "bolt.shield", section: mode),
            .init(command: "/multiline", title: l10n.t("Multiline", "多行输入"), detail: l10n.t("Enter inserts a newline", "Enter 换行，⌘Enter 发送"), icon: "text.alignleft", section: mode),
            .init(command: "/compact-mode", title: l10n.t("Compact display", "紧凑显示"), detail: l10n.t("Toggle tighter chat spacing", "切换更紧的对话间距"), icon: "rectangle.compress.vertical", section: mode),
            .init(command: "/timestamps", title: l10n.t("Timestamps", "时间戳"), detail: l10n.t("Show or hide message times", "显示或隐藏消息时间"), icon: "clock.badge", section: mode),
            .init(command: "/theme", title: l10n.t("Theme", "主题"), detail: l10n.t("Cycle light / dark / system", "在浅色 / 深色 / 系统间切换"), icon: "circle.lefthalf.filled", section: mode),
            .init(command: "/memory", title: l10n.t("Memory", "记忆"), detail: l10n.t("Browse or toggle memory", "查看或开关记忆"), icon: "brain", section: memory),
            .init(command: "/remember", title: l10n.t("Remember", "记住"), detail: l10n.t("Save a note to memory now", "立刻把一条笔记写入记忆"), icon: "bookmark", section: memory, insertsIntoDraft: true),
            .init(command: "/flush", title: l10n.t("Flush", "写入记忆"), detail: l10n.t("Summarize this session into memory", "把当前会话总结进记忆"), icon: "arrow.down.to.line", section: memory),
            .init(command: "/dream", title: l10n.t("Dream", "整理记忆"), detail: l10n.t("Consolidate memory topics", "合并整理记忆主题"), icon: "moon.stars", section: memory),
            .init(command: "/imagine", title: l10n.imagine, detail: l10n.t("Generate an image", "生成图片"), icon: "photo", section: media, insertsIntoDraft: true),
            .init(command: "/imagine-video", title: l10n.t("Imagine video", "生成视频"), detail: l10n.t("Generate a video", "生成视频"), icon: "video", section: media, insertsIntoDraft: true),
            .init(command: "/loop", title: l10n.t("Loop", "循环"), detail: l10n.t("Run a prompt on an interval", "按间隔重复执行提示词"), icon: "repeat", section: media, insertsIntoDraft: true),
            .init(command: "/goal", title: l10n.t("Goal", "目标"), detail: l10n.t("Set or manage an autonomous goal", "设置或管理自主目标"), icon: "flag", section: media, insertsIntoDraft: true),
            .init(command: "/deep-research", title: l10n.t("Deep research", "深度研究"), detail: l10n.t("Start a background research run", "启动后台研究工作流"), icon: "globe", section: media, insertsIntoDraft: true),
            .init(command: "/btw", title: l10n.t("By the way", "顺便问"), detail: l10n.t("Ask a side question", "发一条不打断当前任务的旁问"), icon: "text.bubble", section: media, insertsIntoDraft: true),
            .init(command: "/workflow", title: l10n.t("Workflow", "工作流"), detail: l10n.t("Launch or control a saved workflow", "启动或管理已保存工作流"), icon: "arrow.triangle.branch", section: media, insertsIntoDraft: true),
            .init(command: "/usage", title: l10n.usage, detail: l10n.t("Open usage and billing", "打开用量和账单"), icon: "chart.bar", section: app),
            .init(command: "/settings", title: l10n.settings, detail: l10n.t("Open settings", "打开设置"), icon: "gearshape", section: app),
            .init(command: "/dashboard", title: l10n.liveAgents, detail: l10n.t("Show live agents", "查看进行中的任务"), icon: "rectangle.3.group", section: app),
            .init(command: "/context", title: l10n.t("Session info", "会话信息"), detail: l10n.t("Show context and model", "显示上下文和模型"), icon: "info.circle", section: app),
            .init(command: "/docs", title: l10n.t("Docs", "文档"), detail: l10n.t("Browse local How-to guides", "浏览本机使用指南"), icon: "book", section: app),
            .init(command: "/tutorial", title: l10n.t("Tutorial", "教程"), detail: l10n.t("Open the onboarding topics", "打开入门主题"), icon: "lightbulb", section: app),
            .init(command: "/shortcuts", title: l10n.t("Shortcuts", "快捷键"), detail: l10n.t("Show desktop key bindings", "显示桌面快捷键"), icon: "keyboard", section: app),
            .init(command: "/doctor", title: l10n.t("Doctor", "诊断"), detail: l10n.t("Run grok doctor", "运行 grok doctor"), icon: "stethoscope", section: app),
            .init(command: "/inspect", title: l10n.t("Inspect", "检查配置"), detail: l10n.t("Show discovered grok config", "显示当前目录发现的配置"), icon: "magnifyingglass", section: app),
            .init(command: "/du", title: l10n.t("Disk usage", "磁盘占用"), detail: l10n.t("Show ~/.grok disk use", "查看 ~/.grok 占用"), icon: "internaldrive", section: app),
            .init(command: "/models", title: l10n.t("Models list", "模型列表"), detail: l10n.t("List grok models", "列出 grok 模型"), icon: "square.stack.3d.up", section: app),
            .init(command: "/worktree", title: l10n.t("Worktrees", "Worktree"), detail: l10n.t("List tracked git worktrees", "列出已跟踪的 git worktree"), icon: "leaf", section: app),
            .init(command: "/update", title: l10n.t("Update", "检查更新"), detail: l10n.t("Check the grok CLI for updates", "检查 grok CLI 更新"), icon: "arrow.down.circle", section: app),
            .init(command: "/skills", title: l10n.skills, detail: l10n.t("Open installed skills", "打开已安装技能"), icon: "sparkles", section: app),
            .init(command: "/plugins", title: l10n.t("Plugins", "插件"), detail: l10n.t("Open extensions", "打开扩展"), icon: "puzzlepiece.extension", section: app),
            .init(command: "/hooks", title: l10n.t("Hooks", "Hooks"), detail: l10n.t("Open hooks in settings", "在设置里查看 hooks"), icon: "link", section: app),
            .init(command: "/mcps", title: l10n.t("MCP servers", "MCP"), detail: l10n.t("Manage MCP servers", "管理 MCP 服务器"), icon: "server.rack", section: app),
            .init(command: "/workflows", title: l10n.t("Workflows", "工作流"), detail: l10n.t("Open saved workflows", "打开已保存工作流"), icon: "arrow.triangle.swap", section: app),
            .init(command: "/import-claude", title: l10n.t("Import Claude", "导入 Claude"), detail: l10n.t("Bring over ~/.claude settings", "导入 ~/.claude 设置"), icon: "square.and.arrow.down.on.square", section: app),
            .init(command: "/changelog", title: "CHANGELOG", detail: l10n.t("Open the changelog", "打开更新日志"), icon: "list.bullet.rectangle", section: app),
            .init(command: "/home", title: l10n.t("Home", "首页"), detail: l10n.t("Back to the empty chat", "回到空白对话"), icon: "house", section: app),
            .init(command: "/feedback", title: l10n.t("Feedback", "反馈"), detail: l10n.t("Send feedback about this chat", "发送关于此对话的反馈"), icon: "text.bubble", section: app),
            .init(command: "/privacy", title: l10n.t("Privacy", "隐私"), detail: l10n.t("Open coding-data settings", "打开训练与留存设置"), icon: "hand.raised", section: account),
            .init(command: "/login", title: l10n.loginGrok, detail: l10n.t("Sign in to grok.com", "登录 grok.com"), icon: "person.crop.circle", section: account),
            .init(command: "/logout", title: l10n.t("Sign out", "退出登录"), detail: l10n.t("Sign out of this machine", "退出本机登录"), icon: "rectangle.portrait.and.arrow.right", section: account),
            .init(command: "/quit", title: l10n.t("Quit", "退出"), detail: l10n.t("Quit Grok Desktop", "退出 Grok Desktop"), icon: "xmark.circle", section: account)
        ]
        rows.append(contentsOf: model.skills.prefix(20).map {
            CommandItem(
                id: "skill:\($0.slug)",
                command: "/\($0.slug)",
                title: $0.title,
                detail: $0.slug,
                icon: "sparkles",
                section: skills,
                insertsIntoDraft: true
            )
        })
        return rows
    }
}
