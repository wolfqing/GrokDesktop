import AppKit
import GrokDesktopCore
import SwiftUI

private struct LatestMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var stickToLatest = true
    @State private var copiedPromptID: String?
    @State private var ignoreScrollUntil = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            header

            if let reason = model.firstRunReason, model.client.items.isEmpty {
                FirstRunView(reason: reason)
                composerBlock
            } else if model.client.items.isEmpty {
                emptyState
            } else {
                if model.client.isReconnecting {
                    Text(l10n.t("Reconnecting to grok…", "正在重新连接 grok…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                if let other = model.client.backgroundPermissions.first {
                    Button {
                        _ = model.client.focusIfLoaded(other.id)
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text(l10n.t("Another session is waiting for approval", "另一个会话在等你批准"))
                            Spacer()
                            Text(other.title.isEmpty ? String(other.id.prefix(8)) : other.title)
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.system(size: 12))
                        .padding(10)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ZStack(alignment: .bottomTrailing) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: model.compactChat ? 10 : 22) {
                                    ForEach(displayedItems) { item in
                                        messageRow(item)
                                            .id(item.id)
                                    }
                                    if let story = turnStory {
                                        turnStoryCard(story)
                                            .id("turn-story-\(story.step)-\(story.files.joined())-\(story.phase)")
                                    }
                                    Color.clear
                                        .frame(height: 1)
                                        .id("latest-anchor")
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: LatestMinYKey.self,
                                                    value: geo.frame(in: .named("chatScroll")).minY
                                                )
                                            }
                                        )
                                }
                                .frame(maxWidth: GrokTheme.contentWidth)
                                .padding(.vertical, model.compactChat ? 14 : 28)
                                .frame(maxWidth: .infinity)
                            }
                            .coordinateSpace(name: "chatScroll")
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    if model.mentionQuery != nil || model.showPalette {
                                        model.dismissComposerSuggestions()
                                    }
                                }
                            )
                            .onPreferenceChange(LatestMinYKey.self) { minY in
                                guard Date() >= ignoreScrollUntil else { return }
                                let slack: CGFloat = 56
                                if minY > viewport.size.height + slack {
                                    stickToLatest = false
                                } else if minY <= viewport.size.height + 12 {
                                    stickToLatest = true
                                }
                            }

                            if !stickToLatest {
                                Button {
                                    jumpToLatest(proxy)
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                        .frame(width: 34, height: 34)
                                        .background(palette.elevated, in: Circle())
                                        .overlay(Circle().stroke(palette.hairline))
                                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                                }
                                .buttonStyle(.plain)
                                .help(l10n.jumpToLatest)
                                .padding(.trailing, 28)
                                .padding(.bottom, 16)
                            }
                        }
                        .id(model.client.sessionID ?? "none")
                        .onAppear { pinToBottom(proxy) }
                        .onChange(of: model.client.sessionID) { _, _ in
                            pinToBottom(proxy)
                        }
                        .onChange(of: followToken) { _, _ in
                            if stickToLatest {
                                jumpToLatest(proxy)
                            }
                        }
                        .onChange(of: model.jumpTarget) { _, target in
                            if let target {
                                if target == displayedItems.last?.id {
                                    jumpToLatest(proxy)
                                } else {
                                    stickToLatest = false
                                    proxy.scrollTo(target, anchor: .center)
                                }
                                model.jumpTarget = nil
                            }
                        }
                    }
                }

                if let permission = model.client.permission {
                    PermissionBar(request: permission)
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.bottom, 8)
                }

                composerBlock
            }

            if let error = model.client.lastError, model.firstRunReason == nil, !model.client.isReconnecting {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .textSelection(.enabled)
                    Spacer()
                    Button(l10n.t("Dismiss", "关闭")) { model.client.dismissError() }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(10)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }

    private var composerBlock: some View {
        VStack(spacing: 10) {
            ComposerView()
                .frame(maxWidth: 760)
            if model.isPrivateChat {
                HStack(spacing: 6) {
                    Image(systemName: "eyeglasses")
                    Text(l10n.privateBanner)
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.chooseWorkingDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(model.client.workingDirectory.lastPathComponent)
                        .lineLimit(1)
                    if model.client.hasActiveWork {
                        RunningStatusIcon(
                            active: !model.client.isStopping,
                            idleSystemImage: "pause.circle",
                            color: .orange,
                            size: 10
                        )
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help(model.client.workingDirectory.path)

            Spacer()

            Button {
                model.isPrivateChat.toggle()
            } label: {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.isPrivateChat ? Color.blue : palette.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        model.isPrivateChat ? palette.selected : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(l10n.privateChat)

            Button {
                model.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.showInspector ? palette.text : palette.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        model.showInspector ? palette.selected : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(l10n.inspector)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        let chinese = model.language.resolved() == .chinese
        let folderSessions = model.filteredSessions.filter { $0.cwd == model.client.workingDirectory.path }
        return VStack(spacing: 16) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissComposerSuggestions() }

            GrokMark(size: 32)
            if model.isHomeDirectory {
                Text(l10n.t("Open a project to start", "打开一个项目开始工作"))
                    .font(.system(size: 20, weight: .semibold))
                Text(l10n.t("Home folder is a messy default. Pick a project first.", "当前在家目录，先选一个项目会更干净。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                Button(l10n.chooseFolder) {
                    model.chooseWorkingDirectory()
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                if !model.visibleProjects.isEmpty {
                    emptyList(title: l10n.t("Recent projects", "最近项目")) {
                        ForEach(model.visibleProjects.prefix(4)) { project in
                            Button {
                                model.openProject(project)
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(palette.secondary)
                                    Text(project.name)
                                    Spacer()
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text(model.client.workingDirectory.lastPathComponent)
                    .font(.system(size: 20, weight: .semibold))
                Text(l10n.t("Ask Grok to work in this folder.", "在这个项目里开始问。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                if !folderSessions.isEmpty {
                    emptyList(title: l10n.t("Continue here", "继续这个项目")) {
                        ForEach(folderSessions.prefix(3)) { session in
                            Button {
                                model.open(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(RelativeTime.format(session.updatedAt, chinese: chinese))
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            composerBlock

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissComposerSuggestions() }
        }
        .padding(.horizontal, 24)
    }

    private func emptyList<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            content()
        }
        .frame(maxWidth: 420)
    }

    private var displayedItems: [ConversationItem] {
        var result: [ConversationItem] = []
        for item in model.client.items {
            if case .thought = item, !model.showThinkingBlocks { continue }
            if isTodoTool(item) { continue }
            if model.mergeToolRows,
               case .tool(_, let title, _, _) = item,
               case .tool(_, let previous, _, _) = result.last,
               previous == title {
                result.removeLast()
            }
            result.append(item)
        }
        return result
    }

    private var todoFingerprint: String {
        model.client.todos.map { "\($0.id):\($0.status)" }.joined(separator: "|")
    }

    private var followToken: String {
        let last = model.client.items.last
        let tail: String
        switch last {
        case .assistant(_, let text, _):
            tail = "a\(text.count)"
        case .tool(_, _, let status, let detail):
            tail = "t\(status)\(detail.count)"
        case .thought(_, let text):
            tail = "h\(text.count)"
        case .user(let id, let text):
            tail = "u\(text.count)i\(model.client.itemImages[id]?.count ?? 0)"
        case .notice(_, let text):
            tail = "n\(text.count)"
        case .none:
            tail = "empty"
        }
        return "\(model.client.sessionID ?? "")-\(model.client.items.count)-\(tail)-\(todoFingerprint)-\(model.client.isTurnRunning)-\(model.client.isStopping)"
    }

    private func pinToBottom(_ proxy: ScrollViewProxy) {
        stickToLatest = true
        jumpToLatest(proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { jumpToLatest(proxy) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { jumpToLatest(proxy) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { jumpToLatest(proxy) }
    }

    private func jumpToLatest(_ proxy: ScrollViewProxy) {
        stickToLatest = true
        ignoreScrollUntil = Date().addingTimeInterval(0.8)
        let lastID = displayedItems.last?.id
        DispatchQueue.main.async {
            if let lastID {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            proxy.scrollTo("latest-anchor", anchor: .bottom)
        }
    }

    private func copyPrompt(_ id: String, _ text: String) {
        model.copyText(text)
        copiedPromptID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedPromptID == id {
                copiedPromptID = nil
            }
        }
    }

    private func isLatestAssistant(_ id: String) -> Bool {
        model.client.items.last(where: {
            if case .assistant = $0 { return true }
            return false
        })?.id == id
    }

    private func isTodoTool(_ item: ConversationItem) -> Bool {
        guard case .tool(_, let title, _, _) = item else { return false }
        let name = title.lowercased()
        return name == "todo_write" || name == "updating plan" || name.contains("todo")
    }

    private var turnStory: TurnStory? {
        TurnNarrative.story(
            items: model.client.items,
            todos: model.client.todos,
            hunks: model.client.hunks,
            chinese: model.language.resolved() == .chinese,
            running: model.client.isTurnRunning,
            stopping: model.client.isStopping
        )
    }

    private func turnStoryCard(_ story: TurnStory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("This turn", "本轮"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if story.total > 0 {
                    Text("\(story.done)/\(story.total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                if model.client.hasActiveWork {
                    Button(model.client.isStopping ? l10n.stopping : l10n.stop) {
                        if !model.client.isStopping { model.client.stopWork() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.sendGlyph)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(palette.send, in: Capsule())
                    .disabled(model.client.isStopping)
                }
            }
            storyLine(l10n.t("Goal", "目标"), story.goal)
            HStack(alignment: .top, spacing: 8) {
                Text(l10n.t("Now", "现在"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 52, alignment: .leading)
                HStack(spacing: 6) {
                    if story.phase == .working || story.phase == .stopping {
                        RunningStatusIcon(
                            active: story.phase == .working,
                            idleSystemImage: "pause.circle",
                            color: .orange,
                            size: 12
                        )
                    }
                    Text(story.step)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            if let next = story.nextStep, !next.isEmpty {
                storyLine(l10n.t("Next", "下一步"), next)
            }
            if !story.files.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(l10n.t("Changed", "改了"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(story.files.prefix(5)), id: \.self) { name in
                            ChatFileLabel(path: name)
                        }
                        if story.files.count > 5 {
                            Text("+\(story.files.count - 5)")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, model.compactChat ? 16 : 28)
    }

    private func storyLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 52, alignment: .leading)
            LinkedText(text: value, fontSize: 13, markdown: false)
        }
    }

    @ViewBuilder
    private func timestamp(_ id: String, always: Bool = false) -> some View {
        if always || model.showTimestamps, let date = model.client.itemDates[id] {
            Text(PromptTimestamp.format(date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondary)
        }
    }

    @ViewBuilder
    private func messageRow(_ item: ConversationItem) -> some View {
        switch item {
        case .user(let id, let text):
            let images = PromptMedia.resolvedImages(stored: model.client.itemImages[id], text: text)
            let shown = PromptMedia.displayText(text)
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    timestamp(id, always: true)
                    VStack(alignment: .trailing, spacing: 8) {
                        ForEach(images, id: \.path) { url in
                            PromptImageView(url: url)
                        }
                        if !shown.isEmpty {
                            LinkedText(
                                text: shown,
                                fontSize: model.compactChat ? 14 : 16,
                                markdown: false,
                                fillsWidth: false
                            )
                        } else if images.isEmpty {
                            LinkedText(
                                text: text,
                                fontSize: model.compactChat ? 14 : 16,
                                markdown: false,
                                fillsWidth: false
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, model.compactChat ? 8 : 12)
                    .background(palette.selected, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button {
                        copyPrompt(id, text)
                    } label: {
                        Image(systemName: copiedPromptID == id ? "checkmark" : "square.on.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(copiedPromptID == id ? l10n.copied : l10n.copyPrompt)
                }
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .assistant(let id, let text, let done):
            VStack(alignment: .leading, spacing: 4) {
                timestamp(id)
                if text.isEmpty {
                    Text("…")
                        .font(.system(size: model.compactChat ? 14 : 16))
                        .foregroundStyle(palette.secondary)
                } else {
                    MessageMarkdownView(
                        text: text,
                        fontSize: model.compactChat ? 14 : 16,
                        live: !done && model.client.isTurnRunning
                    )
                }
                if model.client.isTurnRunning, isLatestAssistant(id) {
                    Circle()
                        .fill(palette.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .thought(_, let text):
            DisclosureGroup(l10n.think) {
                LinkedText(text: text, fontSize: 13, markdown: false, color: palette.secondary)
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .tool(let id, let title, let status, let detail):
            let chinese = model.language.resolved() == .chinese
            let active = status == "running" || status == "in_progress"
            DisclosureGroup {
                if !detail.isEmpty {
                    LinkedText(
                        text: detail,
                        fontSize: 12,
                        monospaced: true,
                        markdown: false,
                        color: palette.secondary
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    RunningStatusIcon(
                        active: active && !model.client.isStopping,
                        idleSystemImage: status == "completed" ? "checkmark.circle.fill" : (status == "cancelled" ? "xmark.circle" : "wrench.and.screwdriver"),
                        color: status == "completed" ? .green : (status == "failed" || status == "cancelled" ? .orange : palette.secondary),
                        size: 13
                    )
                    LinkedText(
                        text: ToolVoice.headline(title, chinese: chinese),
                        fontSize: 13,
                        markdown: false,
                        fillsWidth: false
                    )
                    Spacer()
                    Text(model.client.isStopping && active ? l10n.stopping : ToolVoice.statusLabel(status, chinese: chinese))
                        .foregroundStyle(palette.secondary)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(12)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)
            .help(id)
        case .notice(_, let text):
            LinkedText(text: text, fontSize: 13, markdown: false, color: palette.secondary)
                .padding(.horizontal, 28)
        }
    }
}

private struct PromptImageView: View {
    let url: URL
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button {
            ChatLinkActions.open(url)
        } label: {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .help(l10n.t("Open image", "打开图片"))
        .contextMenu { ChatLinkContextButtons(url: url) }
    }
}

private struct ChatFileLabel: View {
    let path: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let url = ChatLinkDetector.resolve(path, baseDirectory: model.client.workingDirectory)?.url
            ?? URL(fileURLWithPath: path)
        Button(path) {
            ChatLinkActions.open(url)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: .linkColor))
        .underline()
        .help(url.path)
        .contextMenu { ChatLinkContextButtons(url: url) }
    }
}
