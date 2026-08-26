import AppKit
import GrokDesktopCore
import SwiftUI

private struct ChatScrollGeometryReader: ViewModifier {
    var onMetrics: (ChatScrollMetrics) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: ChatScrollMetrics.self) { geo in
                ChatScrollMetrics(
                    offset: max(geo.visibleRect.minY, 0),
                    visible: max(geo.containerSize.height, 1),
                    content: max(geo.contentSize.height, geo.containerSize.height)
                )
            } action: { _, metrics in
                onMetrics(metrics)
            }
        } else {
            content
        }
    }
}

private struct ChatDefaultBottomAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.defaultScrollAnchor(.bottom)
        } else {
            content
        }
    }
}



struct ChatScrollBottomMonitor: NSViewRepresentable {
    var ignoreUntil: Date
    var slack: CGFloat = 56
    var isDark = false
    var onNearBottomChange: (Bool) -> Void
    var onMetrics: (ChatScrollMetrics) -> Void = { _ in }
    var driver: ChatScrollDriver?

    @MainActor
    final class Coordinator {
        var clip: NSClipView?
        weak var scroll: NSScrollView?
        nonisolated(unsafe) var token: NSObjectProtocol?
        nonisolated(unsafe) var frameToken: NSObjectProtocol?
        var lastNear: Bool?
        var ignoreUntil = Date.distantPast
        var slack: CGFloat = 56
        var isDark = false
        var onChange: (Bool) -> Void = { _ in }
        var onMetrics: (ChatScrollMetrics) -> Void = { _ in }
        var driver: ChatScrollDriver?
        private var attachAttempts = 0

        func attach(from view: NSView) {
            if clip != nil {
                styleScroller()
                return
            }
            if let scroll = enclosingScrollView(from: view) {
                self.scroll = scroll
                driver?.attach(scroll)
                styleScroller()
                observe(scroll.contentView)
                return
            }
            attachAttempts += 1
            guard attachAttempts < 20 else { return }
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                self.attach(from: view)
            }
        }

        func styleScroller() {
            guard let scroll else { return }
            driver?.attach(scroll)
        }

        func observe(_ clip: NSClipView) {
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            clip.documentView?.postsFrameChangedNotifications = true
            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.emit()
                }
            }
            frameToken = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clip.documentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.emit()
                }
            }
            emit()
        }

        func emit() {
            guard let clip else { return }
            if let scroll {
                driver?.attach(scroll)
            }
            let metrics = Self.metrics(from: clip, slack: slack)
            driver?.update(metrics: metrics, isDark: isDark)
            onMetrics(metrics)
            guard Date() >= ignoreUntil else { return }
            if lastNear != metrics.isNearBottom {
                lastNear = metrics.isNearBottom
                onChange(metrics.isNearBottom)
            }
        }

        static func metrics(from clip: NSClipView, slack: CGFloat) -> ChatScrollMetrics {
            let visible = clip.documentVisibleRect
            let content = max(clip.documentView?.bounds.height ?? visible.height, visible.height)
            let viewH = max(clip.bounds.height, 1)
            let flipped = clip.documentView?.isFlipped ?? clip.isFlipped
            let offset = max(flipped ? visible.minY : content - visible.maxY, 0)
            return ChatScrollMetrics(offset: offset, visible: viewH, content: content)
        }

        private func enclosingScrollView(from view: NSView) -> NSScrollView? {
            if let scroll = view.enclosingScrollView { return scroll }
            if let parent = view.superview {
                for sibling in parent.subviews {
                    if let scroll = nearbyScrollView(in: sibling) { return scroll }
                }
            }
            var current: NSView? = view
            for _ in 0..<12 {
                if let scroll = current as? NSScrollView { return scroll }
                if let scroll = current?.enclosingScrollView { return scroll }
                current = current?.superview
            }
            return nil
        }

        private func nearbyScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews {
                if let scroll = child as? NSScrollView { return scroll }
            }
            return nil
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            if let frameToken { NotificationCenter.default.removeObserver(frameToken) }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.ignoreUntil = ignoreUntil
        coordinator.slack = slack
        coordinator.isDark = isDark
        coordinator.onChange = onNearBottomChange
        coordinator.onMetrics = onMetrics
        coordinator.driver = driver
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.attach(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.ignoreUntil = ignoreUntil
        context.coordinator.slack = slack
        context.coordinator.isDark = isDark
        context.coordinator.onChange = onNearBottomChange
        context.coordinator.onMetrics = onMetrics
        context.coordinator.driver = driver
        if let scroll = context.coordinator.scroll {
            driver?.attach(scroll)
        }
        if context.coordinator.clip == nil {
            context.coordinator.attach(from: nsView)
        } else {
            context.coordinator.styleScroller()
            context.coordinator.emit()
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var stickToLatest = true
    @State private var pinningToLatest = false
    @State private var pinToken = 0
    @State private var bottomHits = 0
    @State private var pinStarted = Date.distantPast
    @State private var copiedPromptID: String?
    @State private var ignoreScrollUntil = Date.distantPast
    @State private var scrollMetrics = ChatScrollMetrics()
    @State private var scrollDriver = ChatScrollDriver()
    @State private var scrollbarDragging = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let reason = model.firstRunReason, model.client.items.isEmpty {
                FirstRunView(reason: reason)
                composerBlock
            } else if model.client.items.isEmpty, model.client.isLoadingSession {
                loadingState
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

                if model.client.compacted || !model.client.recap.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if model.client.compacted {
                            Text(l10n.t("Context compacted", "上下文已压缩"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }
                        if !model.client.recap.isEmpty {
                            Text(model.client.recap)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                if let other = model.client.backgroundQuestions.first ?? model.client.backgroundPermissions.first {
                    Button {
                        _ = model.client.focusIfLoaded(other.id)
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text(
                                other.userQuestion != nil
                                    ? l10n.t("Another session is waiting for an answer", "另一个会话在等你回答")
                                    : l10n.t("Another session is waiting for approval", "另一个会话在等你批准")
                            )
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

                ScrollViewReader { proxy in
                    ZStack {
                        ScrollView {
                            LazyVStack(
                                alignment: .leading,
                                spacing: GrokTheme.chatRowSpacing(compact: model.compactChat)
                            ) {
                                ForEach(displayedRows) { row in
                                    displayRow(row)
                                        .id(row.id)
                                }
                                Color.clear
                                    .frame(height: 8)
                                    .id("latest-anchor")
                            }
                            .frame(maxWidth: GrokTheme.contentWidth)
                            .padding(.vertical, model.compactChat ? 16 : 32)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.never)
                        .modifier(ChatDefaultBottomAnchor())
                        .modifier(ChatScrollGeometryReader { applyScrollMetrics($0) })
                        .background(
                            ChatScrollBottomMonitor(
                                ignoreUntil: ignoreScrollUntil,
                                isDark: palette.isDark,
                                onNearBottomChange: { nearBottom in
                                    applyNearBottom(nearBottom)
                                },
                                onMetrics: { applyScrollMetrics($0) },
                                driver: scrollDriver
                            )
                        )
                        .background(CopyOnSelectMonitor())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if model.mentionQuery != nil || model.showPalette {
                                    model.dismissComposerSuggestions()
                                }
                            }
                        )
                        .overlay(alignment: .trailing) {
                            chatScrollbar(proxy)
                        }
                        .overlay {
                            if pinningToLatest {
                                palette.canvas
                                    .overlay { ProgressView() }
                                    .transition(.opacity)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if showJumpToLatest {
                                Button {
                                    jumpToLatest(proxy)
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                        .frame(width: 34, height: 34)
                                        .background(palette.elevated, in: Circle())
                                        .overlay(Circle().stroke(palette.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help(l10n.jumpToLatest)
                                .padding(.bottom, 10)
                                .accessibilityLabel(l10n.jumpToLatest)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            }
                        }
                    }
                    .id(model.client.sessionID ?? "none")
                    .onAppear { pinToLatestOnOpen(proxy) }
                    .onChange(of: model.client.sessionID) { _, _ in
                        pinToLatestOnOpen(proxy)
                    }
                    .onChange(of: model.client.items.isEmpty) { wasEmpty, isEmpty in
                        if wasEmpty, !isEmpty {
                            pinToLatestOnOpen(proxy)
                        }
                    }
                    .onChange(of: followToken) { _, _ in
                        if pinningToLatest || stickToLatest {
                            snapToLatest(proxy)
                        }
                    }
                    .onChange(of: model.jumpTarget) { _, target in
                        if let target {
                            if target == lastDisplayID {
                                jumpToLatest(proxy)
                            } else {
                                pinningToLatest = false
                                stickToLatest = false
                                proxy.scrollTo(target, anchor: .center)
                            }
                            model.jumpTarget = nil
                        }
                    }
                }

                if let question = model.client.userQuestion {
                    QuestionCard(request: question)
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.bottom, 8)
                } else if let permission = model.client.permission {
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
        .animation(.easeOut(duration: 0.16), value: stickToLatest)
        .onReceive(NotificationCenter.default.publisher(for: .grokCopyOnSelect)) { note in
            if let text = note.object as? String {
                model.copySelection(text)
            }
        }
    }

    private func compactContext(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.0fk", Double(value) / 1000)
        }
        return "\(value)"
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

            if model.client.sessionID != nil || model.displayedContextUsed > 0 {
                Button {
                    model.refreshContextBreakdown()
                    model.showContextSheet = true
                } label: {
                    Text("\(model.displayedContextPercent)% · \(compactContext(model.displayedContextUsed))/\(compactContext(model.displayedContextWindow))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.sessionContext)
            }

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

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text(l10n.t("Loading conversation…", "正在加载对话…"))
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private enum DisplayRow: Identifiable {
        case message(ConversationItem)
        case tools(id: String, items: [ConversationItem])

        var id: String {
            switch self {
            case .message(let item):
                return item.id
            case .tools(let id, _):
                return id
            }
        }

    }

    private var displayedRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        var pending: [ConversationItem] = []

        func flushTools() {
            guard !pending.isEmpty else { return }
            let id = pending.map(\.id).joined(separator: "+")
            rows.append(.tools(id: id, items: pending))
            pending = []
        }

        for item in model.client.items {
            if case .thought = item, !model.showThinkingBlocks { continue }
            if isTodoTool(item) { continue }
            if case .tool(_, let title, let status, _) = item {
                if canMerge(title: title, status: status, onto: pending) {
                    pending.append(item)
                } else {
                    flushTools()
                    pending = [item]
                }
            } else {
                flushTools()
                rows.append(.message(item))
            }
        }
        flushTools()
        return rows
    }

    private var showJumpToLatest: Bool {
        !pinningToLatest
            && scrollMetrics.canScroll
            && (!stickToLatest || !scrollMetrics.isNearBottom)
    }

    private func applyNearBottom(_ near: Bool) {
        guard !pinningToLatest, !scrollbarDragging else { return }
        guard Date() >= ignoreScrollUntil else { return }
        if stickToLatest != near {
            stickToLatest = near
        }
    }

    private func applyScrollMetrics(_ metrics: ChatScrollMetrics) {
        if scrollbarDragging { return }
        if scrollMetrics != metrics {
            scrollMetrics = metrics
        }
        if pinningToLatest {
            stickToLatest = true
            let waited = Date().timeIntervalSince(pinStarted) >= 0.2
            if metrics.isNearBottom {
                bottomHits += 1
                if bottomHits >= 3, waited, metrics.canScroll || Date().timeIntervalSince(pinStarted) >= 0.35 {
                    pinningToLatest = false
                }
            } else {
                bottomHits = 0
                scrollDriver.seek(to: 1)
            }
            return
        }
        applyNearBottom(metrics.isNearBottom)
    }

    private func chatScrollbar(_ proxy: ScrollViewProxy) -> some View {
        OverlayScrollbar(
            metrics: scrollMetrics,
            isDark: palette.isDark,
            onBegan: {
                pinningToLatest = false
                scrollbarDragging = true
            },
            onSeek: { progress in
                scrollDriver.seek(to: progress)
            },
            onEnded: { progress in
                scrollbarDragging = false
                var next = scrollMetrics
                next.offset = min(max(progress, 0), 1) * next.travel
                scrollMetrics = next
                ignoreScrollUntil = Date().addingTimeInterval(0.2)
                stickToLatest = progress >= 0.985
                if progress >= 0.985 {
                    jumpToLatest(proxy)
                }
            }
        )
        .frame(width: 14)
        .padding(.vertical, 6)
    }

    private var lastDisplayID: String? {
        displayedRows.last?.id
    }

    private func canMerge(title: String, status: String, onto pending: [ConversationItem]) -> Bool {
        guard model.mergeToolRows, let last = pending.last else { return false }
        guard case .tool(_, let previousTitle, let previousStatus, _) = last else { return false }
        guard !ToolVoice.isActive(status), !ToolVoice.isActive(previousStatus) else { return false }
        let kind = ToolVoice.kind(title)
        return kind != .other && kind == ToolVoice.kind(previousTitle)
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

    private func pinToLatestOnOpen(_ proxy: ScrollViewProxy) {
        pinToken += 1
        let token = pinToken
        pinningToLatest = true
        bottomHits = 0
        pinStarted = Date()
        stickToLatest = true
        ignoreScrollUntil = Date().addingTimeInterval(2.6)
        snapToLatest(proxy)
        for delay in [0.05, 0.12, 0.24, 0.4, 0.7, 1.1, 1.6, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard token == pinToken, pinningToLatest else { return }
                snapToLatest(proxy)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            guard token == pinToken else { return }
            pinningToLatest = false
            stickToLatest = scrollMetrics.isNearBottom || !scrollMetrics.canScroll
        }
    }

    private func jumpToLatest(_ proxy: ScrollViewProxy) {
        pinningToLatest = false
        stickToLatest = true
        ignoreScrollUntil = Date().addingTimeInterval(0.8)
        snapToLatest(proxy)
    }

    private func snapToLatest(_ proxy: ScrollViewProxy) {
        stickToLatest = true
        scrollDriver.seek(to: 1)
        let lastID = lastDisplayID
        DispatchQueue.main.async {
            if let lastID {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            proxy.scrollTo("latest-anchor", anchor: .bottom)
            scrollDriver.seek(to: 1)
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

    private func turnDurationLabel(for id: String) -> String? {
        if model.client.isTurnRunning, isLatestAssistant(id) { return nil }
        guard let seconds = TurnTiming.seconds(
            forAssistant: id,
            items: model.client.items,
            dates: model.client.itemDates,
            stored: model.client.itemDurations
        ) else { return nil }
        let chinese = l10n.language == .chinese
        let clock = PromptTimestamp.formatElapsed(seconds, chinese: chinese)
        return l10n.t(clock, "用时 \(clock)")
    }

    private func isLatestAssistant(_ id: String) -> Bool {
        model.client.items.last(where: {
            if case .assistant = $0 { return true }
            return false
        })?.id == id
    }

    private func isLatestUser(_ id: String) -> Bool {
        model.client.items.last(where: {
            if case .user = $0 { return true }
            return false
        })?.id == id
    }

    private func isTodoTool(_ item: ConversationItem) -> Bool {
        guard case .tool(_, let title, _, _) = item else { return false }
        return ToolVoice.kind(title) == .todo
    }

    @ViewBuilder
    private func displayRow(_ row: DisplayRow) -> some View {
        switch row {
        case .message(let item):
            messageRow(item)
        case .tools(_, let items):
            toolCluster(items)
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
                                fontSize: GrokTheme.chatBubbleSize(compact: model.compactChat),
                                markdown: false,
                                fillsWidth: false,
                                color: palette.promptBubbleText,
                                maxContentWidth: GrokTheme.bubbleMaxWidth
                            )
                        } else if images.isEmpty {
                            LinkedText(
                                text: text,
                                fontSize: GrokTheme.chatBubbleSize(compact: model.compactChat),
                                markdown: false,
                                fillsWidth: false,
                                color: palette.promptBubbleText,
                                maxContentWidth: GrokTheme.bubbleMaxWidth
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, model.compactChat ? 8 : 10)
                    .background(palette.promptBubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack(spacing: 4) {
                        if isLatestUser(id) {
                            Button {
                                model.restorePromptToComposer(text)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help(l10n.restorePrompt)
                        }
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
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .assistant(let id, let text, let done):
            VStack(alignment: .leading, spacing: 6) {
                timestamp(id)
                if text.isEmpty {
                    Text("…")
                        .font(.system(size: GrokTheme.chatBodySize(compact: model.compactChat)))
                        .foregroundStyle(palette.secondary)
                } else {
                    MessageMarkdownView(
                        text: text,
                        fontSize: GrokTheme.chatBodySize(compact: model.compactChat),
                        live: !done && model.client.isTurnRunning
                    )
                }
                if model.client.isTurnRunning, isLatestAssistant(id) {
                    Circle()
                        .fill(palette.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.7)
                } else if let label = turnDurationLabel(for: id) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .thought(_, let text):
            DisclosureGroup {
                LinkedText(text: text, fontSize: GrokTheme.chatMetaSize(compact: model.compactChat), markdown: false, color: palette.secondary)
            } label: {
                Text(l10n.think)
                    .font(.system(size: GrokTheme.chatMetaSize(compact: model.compactChat)))
                    .foregroundStyle(palette.secondary)
            }
            .tint(palette.secondary)
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .tool(let id, let title, let status, let detail):
            toolLine(id: id, title: title, status: status, detail: detail)
                .padding(.horizontal, model.compactChat ? 16 : 28)
        case .notice(_, let text):
            LinkedText(text: text, fontSize: GrokTheme.chatMetaSize(compact: model.compactChat), markdown: false, color: palette.secondary)
                .padding(.horizontal, model.compactChat ? 16 : 28)
        }
    }

    @ViewBuilder
    private func toolCluster(_ items: [ConversationItem]) -> some View {
        let chinese = model.language.resolved() == .chinese
        if items.count == 1, case .tool(let id, let title, let status, let detail) = items[0] {
            toolLine(id: id, title: title, status: status, detail: detail)
                .padding(.horizontal, model.compactChat ? 16 : 28)
        } else if let first = items.first, case .tool(_, let title, _, _) = first {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        if case .tool(let id, let itemTitle, let status, let detail) = item {
                            toolLine(id: id, title: itemTitle, status: status, detail: detail, grouped: true)
                        }
                    }
                }
                .padding(.leading, 20)
            } label: {
                toolHeader(
                    status: items.allSatisfy(toolSucceeded) ? "completed" : "cancelled",
                    verb: ToolVoice.groupHeadline(kind: ToolVoice.kind(title), count: items.count, chinese: chinese),
                    target: "",
                    location: nil
                )
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        }
    }

    @ViewBuilder
    private func toolLine(
        id: String,
        title: String,
        status: String,
        detail: String,
        grouped: Bool = false
    ) -> some View {
        let chinese = model.language.resolved() == .chinese
        let parsed = ToolVoice.line(title, chinese: chinese, cwd: model.client.workingDirectory)
        let shownStatus = model.client.isStopping && ToolVoice.isActive(status) ? "cancelled" : status
        if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toolHeader(status: shownStatus, verb: parsed.verb, target: parsed.target, location: parsed.location)
                .help(id)
        } else {
            DisclosureGroup {
                LinkedText(
                    text: detail,
                    fontSize: GrokTheme.chatCodeSize(compact: model.compactChat),
                    monospaced: true,
                    markdown: false,
                    color: palette.secondary
                )
                .padding(.leading, grouped ? 0 : 20)
            } label: {
                toolHeader(status: shownStatus, verb: parsed.verb, target: parsed.target, location: parsed.location)
            }
            .help(id)
        }
    }

    private func toolHeader(status: String, verb: String, target: String, location: String?) -> some View {
        let active = ToolVoice.isActive(status) && model.client.isTurnRunning
        return HStack(spacing: 8) {
            RunningStatusIcon(
                active: active && !model.client.isStopping,
                idleSystemImage: toolIdleIcon(status),
                color: toolColor(status),
                size: 11
            )
            Text(verb)
                .foregroundStyle(palette.secondary)
            if !target.isEmpty {
                if let location, looksLikeFileTarget(location) {
                    ChatFileLabel(path: location, title: target)
                } else {
                    Text(target)
                        .foregroundStyle(palette.text.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if status == "failed" || status == "cancelled" {
                Text(ToolVoice.statusLabel(status, chinese: model.language.resolved() == .chinese))
                    .foregroundStyle(palette.secondary)
            }
        }
        .font(.system(size: GrokTheme.chatToolSize(compact: model.compactChat)))
        .padding(.vertical, 1)
    }

    private func toolSucceeded(_ item: ConversationItem) -> Bool {
        if case .tool(_, _, let status, _) = item {
            return status == "completed"
        }
        return false
    }

    private func toolIdleIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark"
        case "cancelled": return "xmark"
        case "failed": return "exclamationmark"
        default: return "circle"
        }
    }

    private func toolColor(_ status: String) -> Color {
        switch status {
        case "completed": return palette.secondary
        case "failed": return .orange
        case "cancelled": return palette.secondary.opacity(0.7)
        default: return palette.secondary
        }
    }

    private func looksLikeFileTarget(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("./") || path.contains("/")
    }
}

private struct PromptImageView: View {
    let url: URL
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button {
            ChatLinkActions.activate(url)
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
    var title: String? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let url = ChatLinkDetector.resolve(path, baseDirectory: model.client.workingDirectory)?.url
            ?? URL(fileURLWithPath: path)
        Button(title ?? path) {
            ChatLinkActions.activate(url)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: .linkColor))
        .underline()
        .help(url.path)
        .contextMenu { ChatLinkContextButtons(url: url) }
    }
}
