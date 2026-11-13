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
            content
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
    var onUserScroll: (ChatScrollMetrics) -> Void = { _ in }
    var driver: ChatScrollDriver?

    @MainActor
    final class Coordinator {
        var clip: NSClipView?
        weak var scroll: NSScrollView?
        nonisolated(unsafe) var token: NSObjectProtocol?
        nonisolated(unsafe) var frameToken: NSObjectProtocol?
        var lastNear: Bool?
        var lastPublished = ChatScrollMetrics()
        var ignoreUntil = Date.distantPast
        var slack: CGFloat = 56
        var isDark = false
        var onChange: (Bool) -> Void = { _ in }
        var onMetrics: (ChatScrollMetrics) -> Void = { _ in }
        var onUserScroll: (ChatScrollMetrics) -> Void = { _ in }
        var driver: ChatScrollDriver?
        private var attachAttempts = 0
        private var lastDocumentHeight: CGFloat = 0
        private var lastOffset: CGFloat = 0
        private var lastVisible: CGFloat = 0

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
                    self?.emit(userScroll: true)
                }
            }
            frameToken = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clip.documentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.emit(userScroll: false)
                }
            }
            emit(userScroll: false)
        }

        func emit(userScroll: Bool) {
            guard let clip else { return }
            if let scroll {
                driver?.attach(scroll)
            }
            let preview = Self.metrics(from: clip, slack: slack)
            let shrunk = ChatScrollMath.shouldRevealBottom(
                previousContent: lastDocumentHeight,
                content: preview.content,
                previousOffset: lastOffset,
                previousVisible: lastVisible
            )
            let follow = ChatScrollMath.shouldFollowGrowth(
                previousContent: lastDocumentHeight,
                content: preview.content,
                previousOffset: lastOffset,
                previousVisible: lastVisible
            )
            lastDocumentHeight = preview.content
            lastOffset = preview.offset
            lastVisible = preview.visible
            if shrunk && !userScroll {
                driver?.revealBottom()
            } else if follow && !userScroll {
                driver?.seek(to: 1)
            } else {
                driver?.clampIfOutside()
            }
            let metrics = Self.metrics(from: clip, slack: slack)
            lastDocumentHeight = metrics.content
            lastOffset = metrics.offset
            lastVisible = metrics.visible
            let programmatic = driver?.consumeProgrammatic(originY: clip.bounds.origin.y) ?? false
            driver?.update(metrics: metrics, isDark: isDark)
            if userScroll, !programmatic {
                onUserScroll(metrics)
            }
            if ChatScrollMath.jumpChromeChanged(
                oldNearBottom: lastPublished.isNearBottom,
                oldCanScroll: lastPublished.canScroll,
                newNearBottom: metrics.isNearBottom,
                newCanScroll: metrics.canScroll
            ) {
                lastPublished = metrics
                onMetrics(metrics)
            }
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
        coordinator.onUserScroll = onUserScroll
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
        context.coordinator.onUserScroll = onUserScroll
        context.coordinator.driver = driver
        if let scroll = context.coordinator.scroll {
            driver?.attach(scroll)
        }
        if context.coordinator.clip == nil {
            context.coordinator.attach(from: nsView)
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
    @State private var settleToken = 0
    @State private var suppressReleaseUntil = Date.distantPast
    @State private var bottomHits = 0
    @State private var pinStarted = Date.distantPast
    @State private var copiedPromptID: String?
    @State private var hoveredPromptID: String?
    @State private var ignoreScrollUntil = Date.distantPast
    @State private var scrollMetrics = ChatScrollMetrics()
    @State private var scrollDriver = ChatScrollDriver()
    @State private var scrollbarDragging = false
    @State private var expandedThoughts: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            conversationColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .grokCopyOnSelect)) { note in
            if let text = note.object as? String {
                model.copySelection(text)
            }
        }
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            contextWindowNote

            if let reason = model.firstRunReason, model.client.items.isEmpty, model.client.outgoingPreview == nil {
                FirstRunView(reason: reason)
                composerBlock
            } else if model.client.items.isEmpty, model.client.isLoadingSession, model.client.outgoingPreview == nil {
                loadingState
                composerBlock
            } else if model.client.items.isEmpty, model.client.outgoingPreview == nil, model.client.promptQueue.isEmpty {
                emptyState
            } else {
                if model.client.isReconnecting {
                    HStack(spacing: 7) {
                        RunningStatusIcon(active: true, idleSystemImage: "wifi.exclamationmark", color: palette.warning, size: 11)
                        Text(l10n.t("Reconnecting to grok…", "正在重新连接 grok…"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(palette.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.warning.opacity(0.10), in: Capsule())
                    .padding(.top, 10)
                }

                if model.client.compacted || !model.client.recap.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if model.client.compacted {
                            HStack(spacing: 5) {
                                Image(systemName: "rectangle.compress.vertical")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(l10n.t("Context compacted", "上下文已压缩"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(palette.warning)
                        }
                        if !model.client.recap.isEmpty {
                            Text(model.client.recap)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: GrokTheme.contentWidth, alignment: .leading)
                    .padding(11)
                    .grokCard(cornerRadius: 11)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                if let other = model.client.backgroundQuestions.first ?? model.client.backgroundPermissions.first {
                    Button {
                        _ = model.client.focusIfLoaded(other.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(palette.warning)
                            Text(
                                other.userQuestion != nil
                                    ? l10n.t("Another session is waiting for an answer", "另一个会话在等你回答")
                                    : l10n.t("Another session is waiting for approval", "另一个会话在等你批准")
                            )
                            .fontWeight(.medium)
                            Spacer()
                            Text(other.title.isEmpty ? String(other.id.prefix(8)) : other.title)
                                .foregroundStyle(palette.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.tertiary)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .grokCard(cornerRadius: 10, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: GrokTheme.contentWidth)
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
                                if let preview = outgoingPreviewText {
                                    userPromptRow(
                                        id: "outgoing-preview",
                                        text: preview,
                                        images: PromptMedia.imageURLs(in: preview)
                                    )
                                    .id("outgoing-preview")
                                }
                                if showsWaitingStatus {
                                    waitingStatusRow
                                        .id("waiting-status")
                                }
                                Color.clear
                                    .frame(height: 8)
                                    .id("latest-anchor")
                            }
                            .frame(maxWidth: GrokTheme.contentWidth)
                            .padding(.vertical, model.compactChat ? 16 : 28)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.never)
                        .modifier(ChatDefaultBottomAnchor())
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                        .modifier(ChatScrollGeometryReader { applyScrollMetrics($0) })
                        .background(
                            ChatScrollBottomMonitor(
                                ignoreUntil: ignoreScrollUntil,
                                isDark: palette.isDark,
                                onNearBottomChange: { _ in },
                                onMetrics: { applyScrollMetrics($0) },
                                onUserScroll: { applyUserScroll($0) },
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
                            Group {
                                if showJumpToLatest {
                                    JumpToLatestButton(label: l10n.jumpToLatest) {
                                        jumpToLatest(proxy)
                                    }
                                    .accessibilityLabel(l10n.jumpToLatest)
                                    .padding(.bottom, 12)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                }
                            }
                            .animation(.easeOut(duration: 0.16), value: showJumpToLatest)
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
                        if pinningToLatest {
                            snapToLatest(proxy)
                        } else if stickToLatest {
                            if #unavailable(macOS 15.0) {
                                snapToLatest(proxy)
                            }
                        }
                    }
                    .onChange(of: model.client.isTurnRunning) { wasRunning, running in
                        if running, !wasRunning, !scrollbarDragging {
                            stickToLatest = true
                            settleLatest(proxy)
                        } else if wasRunning, !running, stickToLatest, !scrollbarDragging {
                            settleLatest(proxy)
                        }
                    }
                    .onChange(of: showsOutgoingPreview) { _, showing in
                        if showing, !scrollbarDragging {
                            stickToLatest = true
                            settleLatest(proxy)
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

                turnStatusBlock

                composerBlock
            }

            if let error = model.client.lastError, model.firstRunReason == nil, !model.client.isReconnecting {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.warning)
                    Text(error)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Spacer()
                    Button(l10n.t("Dismiss", "关闭")) { model.client.dismissError() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(palette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.warning.opacity(0.25), lineWidth: 1)
                )
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            TapGesture().onEnded { model.noteConversationFocus() }
        )
    }

    @ViewBuilder
    private var turnStatusBlock: some View {
        if model.client.isTurnRunning || model.client.isStopping {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                turnStatusRow(now: timeline.date)
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 28)
            .padding(.bottom, 6)
        }
    }

    private func turnStatusRow(now: Date) -> some View {
        let turn = model.client.turnStartedAt.map { now.timeIntervalSince($0) }
        return HStack(spacing: 8) {
            RunningStatusIcon(
                active: !model.client.isStopping,
                idleSystemImage: "stop.circle",
                color: palette.warning,
                size: 11
            )
            Text(model.client.isStopping ? l10n.stopping : l10n.t("Working…", "正在处理…"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            if let turn, turn >= 1 {
                Text(PromptTimestamp.formatCompactElapsed(turn))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
                    .fixedSize()
            }
            if model.displayedContextUsed > 0 {
                Text("⇣\(PromptTimestamp.compactCount(model.displayedContextUsed))")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
    }

    private var composerBlock: some View {
        ComposerView()
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }

    @ViewBuilder
    private var contextWindowNote: some View {
        if let text = model.contextWindowNoteText {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                GrokIconButton(
                    systemImage: "xmark",
                    size: 22,
                    iconSize: 10,
                    helpText: l10n.t("Close", "关掉")
                ) {
                    model.dismissContextWindowNote()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseWorkingDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.secondary)
                    Text(model.client.workingDirectory.lastPathComponent)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(palette.tertiary)
                    if model.client.hasActiveWork {
                        RunningStatusIcon(
                            active: !model.client.isStopping,
                            idleSystemImage: "pause.circle",
                            color: palette.warning,
                            size: 10
                        )
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .grokHover(cornerRadius: 7)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("\(model.client.workingDirectory.path) (⌘⇧O)")

            if model.workspace.isRepo, let branch = model.workspace.branch, !branch.isEmpty {
                Button {
                    model.showWorktrees = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                        Text(branch)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(l10n.t("Manage worktrees", "管理 Worktree"))
            }

            Spacer(minLength: 12)

            if !model.showInspector, (model.client.sessionID != nil || model.displayedContextUsed > 0) {
                Button {
                    model.refreshContextBreakdown()
                    model.showContextSheet = true
                } label: {
                    Text(model.contextChipLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .grokHover(cornerRadius: 6)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(model.contextWindowNoteText ?? l10n.sessionContext)

                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)
            }

            rightSidebarControls
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
        }
    }

    private static let rightSidebarTools: [(tool: InspectorTool, shortcut: String)] = [
        (.changes, "⌘⇧D"),
        (.preview, "⌘⇧P"),
        (.terminal, "⌘J"),
        (.aside, "⌘⇧B"),
    ]

    private var rightSidebarControls: some View {
        HStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    ForEach(Self.rightSidebarTools, id: \.tool) { item in
                        inspectorToolButton(item.tool, shortcut: item.shortcut, compact: false)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 2) {
                    ForEach(Self.rightSidebarTools, id: \.tool) { item in
                        inspectorToolButton(item.tool, shortcut: item.shortcut, compact: true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            GrokIconButton(
                systemImage: "sidebar.right",
                size: 28,
                iconSize: 13,
                selected: model.showInspector,
                cornerRadius: 7,
                helpText: "\(l10n.inspector) (⌘I)"
            ) {
                model.showInspector.toggle()
            }
        }
        .layoutPriority(1)
    }

    private func inspectorToolButton(_ tool: InspectorTool, shortcut: String, compact: Bool) -> some View {
        let pressed = model.inspectorToolPressed(tool)
        let title = tool.title(chinese: l10n.language == .chinese)
        return Button {
            model.toggleInspectorTool(tool)
        } label: {
            HStack(spacing: 4.5) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 11, weight: .medium))
                if !compact {
                    Text(title)
                        .font(.system(size: 12, weight: pressed ? .semibold : .medium))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(pressed ? palette.text : palette.secondary)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, 5)
            .grokHover(cornerRadius: 7, selected: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(title)  \(shortcut)")
        .accessibilityLabel(title)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(l10n.t("Loading conversation…", "正在加载对话…"))
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        let chinese = model.showsChinese
        let folderSessions = model.filteredSessions.filter { $0.cwd == model.client.workingDirectory.path }
        return VStack(spacing: 16) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissComposerSuggestions() }

            GrokMark(size: 34)
                .padding(.bottom, 2)

            if model.isHomeDirectory {
                Text(l10n.t("Open a project to start", "打开一个项目开始工作"))
                    .font(.system(size: 21, weight: .semibold))
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
                                HStack(spacing: 9) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(palette.secondary)
                                    Text(project.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(palette.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .grokCard(cornerRadius: 10, interactive: true)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text(model.client.workingDirectory.lastPathComponent)
                        .font(.system(size: 21, weight: .semibold))
                    Text(l10n.t("Ask Grok to explore, plan, or edit in this project.", "在这个项目里提问、规划或直接修改代码。"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }

                starterSuggestions

                if !folderSessions.isEmpty {
                    emptyList(title: l10n.t("Continue here", "继续这个项目")) {
                        ForEach(folderSessions.prefix(3)) { session in
                            Button {
                                model.open(session)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text(RelativeTime.format(session.updatedAt, chinese: chinese))
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(palette.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8.5)
                                .grokCard(cornerRadius: 10, interactive: true)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var starterSuggestions: some View {
        HStack(spacing: 8) {
            starterChip(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                label: l10n.t("Plan a task", "规划复杂任务"),
                badge: "/plan"
            ) {
                model.client.setMode(.plan)
            }
            starterChip(
                icon: "at",
                label: l10n.t("Mention files", "引用项目文件"),
                badge: "@"
            ) {
                if !model.draft.hasSuffix("@") {
                    model.draft += (model.draft.isEmpty ? "@" : " @")
                }
                model.updateMentions(from: model.draft)
            }
            starterChip(
                icon: "command",
                label: l10n.t("Slash actions", "命令面板"),
                badge: "⌘K"
            ) {
                model.draft = "/"
                model.showPalette = true
            }
        }
    }

    private func starterChip(icon: String, label: String, badge: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.text)
                GrokKbdBadge(keys: badge)
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .padding(.vertical, 6)
            .grokCard(cornerRadius: 10, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func emptyList<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 2)
            content()
        }
        .frame(maxWidth: 440)
    }

    private var displayedRows: [ChatDisplayRow] {
        ChatDisplay.rows(
            items: model.client.items,
            hideAsides: true,
            showThinking: model.showThinkingBlocks,
            skipTodoTools: true
        )
    }

    private var showJumpToLatest: Bool {
        !pinningToLatest
            && scrollMetrics.canScroll
            && (!stickToLatest || !scrollMetrics.isNearBottom)
    }

    private func applyUserScroll(_ metrics: ChatScrollMetrics) {
        guard !pinningToLatest, !scrollbarDragging else { return }
        scrollDriver.update(metrics: metrics, isDark: palette.isDark)
        if metrics.userReleased {
            let offsetMoved = abs(metrics.offset - scrollMetrics.offset) > 1
            if Date() >= suppressReleaseUntil, offsetMoved || scrollMetrics.visible <= 1 {
                stickToLatest = false
                settleToken += 1
            }
        } else if metrics.isNearBottom {
            stickToLatest = true
        }
        if ChatScrollMath.jumpChromeChanged(
            oldNearBottom: scrollMetrics.isNearBottom,
            oldCanScroll: scrollMetrics.canScroll,
            newNearBottom: metrics.isNearBottom,
            newCanScroll: metrics.canScroll
        ) {
            scrollMetrics = metrics
        }
    }

    private func applyScrollMetrics(_ metrics: ChatScrollMetrics) {
        scrollDriver.update(metrics: metrics, isDark: palette.isDark)
        if scrollbarDragging { return }
        if ChatScrollMath.jumpChromeChanged(
            oldNearBottom: scrollMetrics.isNearBottom,
            oldCanScroll: scrollMetrics.canScroll,
            newNearBottom: metrics.isNearBottom,
            newCanScroll: metrics.canScroll
        ) {
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
            }
        }
    }

    private func chatScrollbar(_ proxy: ScrollViewProxy) -> some View {
        OverlayScrollbar(
            metrics: scrollMetrics,
            marks: turnMarks,
            isDark: palette.isDark,
            previousLabel: l10n.t("Previous prompt", "上一条"),
            nextLabel: l10n.t("Next prompt", "下一条"),
            driver: scrollDriver,
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
            },
            onMark: { id in
                jumpToRow(id, proxy)
            },
            onLatest: {
                jumpToLatest(proxy)
            }
        )
        .frame(width: 240)
        .padding(.vertical, 4)
    }

    private var turnMarks: [TurnRailMark] {
        let rows = displayedRows
        let count = rows.count
        guard count > 0 else { return [] }
        return rows.enumerated().compactMap { index, row in
            guard case .message(.user(_, let text)) = row else { return nil }
            let shown = TranscriptLoader.displayUserText(text)
            let label = shown.trimmingCharacters(in: .whitespacesAndNewlines)
            return TurnRailMark(
                id: row.id,
                progress: TurnRail.progress(index: index, count: count),
                label: String((label.isEmpty ? l10n.t("Prompt", "提问") : label).prefix(80))
            )
        }
    }

    private func jumpToRow(_ id: String, _ proxy: ScrollViewProxy) {
        pinningToLatest = false
        stickToLatest = false
        ignoreScrollUntil = Date().addingTimeInterval(0.45)
        proxy.scrollTo(id, anchor: .top)
    }

    private var lastDisplayID: String? {
        if showsWaitingStatus { return "waiting-status" }
        if showsOutgoingPreview { return "outgoing-preview" }
        return displayedRows.last?.id
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
        return "\(model.client.sessionID ?? "")-\(model.client.items.count)-\(tail)-\(todoFingerprint)-\(model.client.isTurnRunning)-\(model.client.isStopping)-o\(model.client.outgoingPreview?.count ?? 0)-w\(showsWaitingStatus)"
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
        for delay in [0.08, 0.28, 0.7] {
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

    /// The finished turn folds tools and thinking, and swaps the live reply for markdown.
    /// The scroll offset can sit in that vacated gap, which stays blank until a wheel event.
    private func settleLatest(_ proxy: ScrollViewProxy) {
        settleToken += 1
        let token = settleToken
        suppressReleaseUntil = Date().addingTimeInterval(0.36)
        reveal(proxy)
        for delay in [0.08, 0.24] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard token == settleToken, stickToLatest, !scrollbarDragging else { return }
                reveal(proxy)
            }
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        scrollDriver.revealBottom()
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
        let shown = PromptMedia.displayText(text)
        model.copyText(shown.isEmpty ? text : shown)
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

    private func isCurrentActivity(_ id: String) -> Bool {
        guard model.client.isTurnRunning else { return false }
        return model.client.items.last(where: { item in
            if isTodoTool(item) { return false }
            if case .thought = item, !model.showThinkingBlocks { return false }
            return true
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
    private func displayRow(_ row: ChatDisplayRow) -> some View {
        switch row {
        case .message(let item):
            messageRow(item)
        case .stream(_, let items):
            streamCluster(items)
        }
    }

    @ViewBuilder
    private func timestamp(_ id: String, always: Bool = false) -> some View {
        if always || model.showTimestamps, let date = model.client.itemDates[id] {
            Text(PromptTimestamp.format(date))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
    }

    private var outgoingPreviewText: String? {
        guard let preview = model.client.outgoingPreview, !SessionFold.isAside(preview) else { return nil }
        if model.client.items.contains(where: {
            if case .user(_, let text) = $0 { return text == preview }
            return false
        }) {
            return nil
        }
        return preview
    }

    private var showsOutgoingPreview: Bool {
        outgoingPreviewText != nil
    }

    private var showsWaitingStatus: Bool {
        if showsOutgoingPreview { return true }
        guard model.client.isTurnRunning, !model.client.isStopping else { return false }
        return !hasVisibleTurnProgress
    }

    private var hasVisibleTurnProgress: Bool {
        guard let lastUser = model.client.items.lastIndex(where: {
            if case .user = $0 { return true }
            return false
        }) else { return false }
        let tail = model.client.items.suffix(from: lastUser + 1)
        for item in tail {
            if SessionFold.belongsToAside(item, items: model.client.items) { continue }
            switch item {
            case .assistant(_, let text, _) where !text.isEmpty:
                return true
            case .tool(_, _, let status, _) where ToolVoice.isActive(status):
                return true
            case .thought where model.showThinkingBlocks:
                return true
            default:
                continue
            }
        }
        return false
    }

    private var waitingTitle: String {
        if model.client.isReconnecting || model.client.state == .connecting {
            return l10n.t("Connecting to grok…", "正在连接 grok…")
        }
        if model.client.isLoadingSession {
            return l10n.t("Loading session…", "正在加载会话…")
        }
        if model.client.isStopping {
            return l10n.stopping
        }
        return l10n.t("Received — thinking…", "已收到，正在思考…")
    }

    private var waitingStatusRow: some View {
        HStack(spacing: 8) {
            RunningStatusIcon(active: true, idleSystemImage: "ellipsis", color: palette.warning, size: 12)
            Text(waitingTitle)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, model.compactChat ? 16 : 28)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func userPromptRow(
        id: String,
        text: String,
        images: [URL]
    ) -> some View {
        let raw = SessionFold.isAside(text) ? SessionFold.asideDisplay(text) : text
        let shown = PromptMedia.displayText(raw)
        let caption = shown.isEmpty && images.isEmpty ? raw : shown
        let actionsVisible = hoveredPromptID == id || copiedPromptID == id
        HStack {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: 4) {
                if model.showTimestamps {
                    timestamp(id, always: true)
                }
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(images, id: \.path) { url in
                        PromptImageView(url: url)
                    }
                    if !caption.isEmpty {
                        LinkedText(
                            text: caption,
                            fontSize: GrokTheme.chatBubbleSize(compact: model.compactChat),
                            markdown: false,
                            fillsWidth: false,
                            color: palette.promptBubbleText,
                            maxContentWidth: GrokTheme.bubbleMaxWidth
                        )
                    }
                }
                .padding(.horizontal, images.isEmpty ? 15 : 9)
                .padding(.vertical, model.compactChat ? 8.5 : 10.5)
                .background(
                    palette.promptBubble,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.promptBubbleBorder, lineWidth: 1)
                )

                HStack(spacing: 2) {
                    if !model.showTimestamps, actionsVisible {
                        timestamp(id, always: true)
                            .padding(.trailing, 4)
                    }
                    if isLatestUser(id) {
                        GrokIconButton(
                            systemImage: "arrow.uturn.backward",
                            size: 22,
                            iconSize: 10.5,
                            cornerRadius: 6,
                            helpText: l10n.restorePrompt
                        ) {
                            model.restorePromptToComposer(text)
                        }
                    }
                    GrokIconButton(
                        systemImage: copiedPromptID == id ? "checkmark" : "doc.on.doc",
                        size: 22,
                        iconSize: 10.5,
                        cornerRadius: 6,
                        helpText: copiedPromptID == id ? l10n.copied : l10n.copyPrompt
                    ) {
                        copyPrompt(id, text)
                    }
                }
                .opacity(actionsVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: actionsVisible)
            }
        }
        .padding(.horizontal, model.compactChat ? 16 : 28)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredPromptID = id
            } else if hoveredPromptID == id {
                hoveredPromptID = nil
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ item: ConversationItem) -> some View {
        switch item {
        case .user(let id, let text):
            userPromptRow(
                id: id,
                text: text,
                images: PromptMedia.resolvedImages(stored: model.client.itemImages[id], text: text)
            )
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
                if model.client.isTurnRunning, isCurrentActivity(id) {
                    HStack(spacing: 6) {
                        RunningStatusIcon(active: true, idleSystemImage: "ellipsis", color: palette.warning, size: 10)
                        Text(text.isEmpty
                             ? l10n.t("Thinking…", "正在思考…")
                             : l10n.t("Writing…", "正在回复…"))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                } else if let label = turnDurationLabel(for: id) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.tertiary)
                }
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .thought(let id, let text):
            thoughtRow(id: id, text: text)
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
    private func streamCluster(_ items: [ConversationItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ChatDisplay.streamPieces(items, mergeTools: model.mergeToolRows)) { piece in
                switch piece {
                case .tools(_, let tools):
                    toolCluster(tools)
                case .item(let item):
                    streamItem(item)
                }
            }
        }
        .padding(.horizontal, model.compactChat ? 16 : 28)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func streamItem(_ item: ConversationItem) -> some View {
        switch item {
        case .thought(let id, let text):
            thoughtRow(id: id, text: text)
        case .tool(let id, let title, let status, let detail):
            toolLine(id: id, title: title, status: status, detail: detail)
        case .notice(_, let text):
            LinkedText(text: text, fontSize: GrokTheme.chatMetaSize(compact: model.compactChat), markdown: false, color: palette.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func thoughtRow(id: String, text: String) -> some View {
        let chinese = l10n.language == .chinese
        let live = isCurrentActivity(id)
        let elapsed = TurnTiming.seconds(
            forThought: id,
            items: model.client.items,
            dates: model.client.itemDates,
            stored: model.client.itemDurations,
            running: live
        )
        let header = ThoughtVoice.header(elapsed: elapsed, running: live, chinese: chinese)
        let tail = ThoughtVoice.tail(text)
        let expanded = Binding(
            get: { expandedThoughts.contains(id) },
            set: { on in
                if on { expandedThoughts.insert(id) } else { expandedThoughts.remove(id) }
            }
        )
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: expanded) {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LinkedText(
                        text: text,
                        fontSize: GrokTheme.chatMetaSize(compact: model.compactChat),
                        markdown: false,
                        color: palette.secondary
                    )
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(palette.hairline)
                            .frame(width: 1.5)
                            .padding(.leading, 4)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    if live {
                        RunningStatusIcon(active: true, idleSystemImage: "sparkles", color: palette.warning, size: 11)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.tertiary)
                            .frame(width: 12)
                    }
                    Text(header)
                        .font(.system(size: GrokTheme.chatMetaSize(compact: model.compactChat), weight: .medium))
                        .foregroundStyle(palette.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .tint(palette.tertiary)
            if live, !expandedThoughts.contains(id), !tail.lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if tail.ellipsis {
                        Text("…")
                            .foregroundStyle(palette.tertiary)
                    }
                    ForEach(Array(tail.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: GrokTheme.chatMetaSize(compact: model.compactChat)))
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(width: 1.5)
                        .padding(.leading, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func toolCluster(_ items: [ConversationItem]) -> some View {
        let chinese = model.showsChinese
        let status = items.allSatisfy(toolSucceeded) ? "completed" : (items.contains(where: { item in
            if case .tool(_, _, let value, _) = item { return value == "failed" }
            return false
        }) ? "failed" : "cancelled")
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.id) { item in
                    if case .tool(let id, let itemTitle, let itemStatus, let detail) = item {
                        toolLine(id: id, title: itemTitle, status: itemStatus, detail: detail, grouped: true)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1.5)
                    .padding(.leading, 4)
            }
        } label: {
            toolHeader(
                status: status,
                verb: ToolVoice.groupLabel(items: items, chinese: chinese),
                target: "",
                location: nil,
                grouped: true
            )
        }
        .tint(palette.tertiary)
    }

    @ViewBuilder
    private func toolLine(
        id: String,
        title: String,
        status: String,
        detail: String,
        grouped: Bool = false
    ) -> some View {
        let chinese = model.showsChinese
        let active = ToolVoice.isActive(status) && model.client.isTurnRunning
        let parsed = ToolVoice.line(title, chinese: chinese, cwd: model.client.workingDirectory, running: active)
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
                .padding(.leading, grouped ? 10 : 14)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(width: 1.5)
                        .padding(.leading, grouped ? 2 : 4)
                }
            } label: {
                toolHeader(status: shownStatus, verb: parsed.verb, target: parsed.target, location: parsed.location)
            }
            .tint(palette.tertiary)
            .help(id)
        }
    }

    private func toolHeader(
        status: String,
        verb: String,
        target: String,
        location: String?,
        grouped: Bool = false
    ) -> some View {
        let active = ToolVoice.isActive(status) && model.client.isTurnRunning && !model.client.isStopping
        return HStack(spacing: 7) {
            toolStatusBadge(status: status, active: active, grouped: grouped)
            Text(verb)
                .foregroundStyle(palette.secondary)
            if !target.isEmpty {
                if let location, looksLikeFileTarget(location) {
                    ChatFileLabel(path: location, title: target)
                } else {
                    Text(target)
                        .font(.system(size: GrokTheme.chatToolSize(compact: model.compactChat) - 0.5, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.84))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if status == "failed" || status == "cancelled" {
                Text(ToolVoice.statusLabel(status, chinese: model.showsChinese))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(status == "failed" ? palette.warning : palette.tertiary)
            }
        }
        .font(.system(size: GrokTheme.chatToolSize(compact: model.compactChat)))
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func toolStatusBadge(status: String, active: Bool, grouped: Bool) -> some View {
        if active {
            RunningStatusIcon(active: true, idleSystemImage: "circle.dotted", color: palette.success, size: 11)
                .frame(width: 12)
        } else if status == "failed" {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(palette.warning)
                .frame(width: 12)
        } else if status == "cancelled" {
            Image(systemName: "minus.circle")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiary)
                .frame(width: 12)
        } else {
            Image(systemName: grouped ? "checkmark.circle" : "checkmark")
                .font(.system(size: grouped ? 11 : 10, weight: .semibold))
                .foregroundStyle(palette.tertiary)
                .frame(width: 12)
        }
    }

    private func toolSucceeded(_ item: ConversationItem) -> Bool {
        if case .tool(_, _, let status, _) = item {
            return status == "completed"
        }
        return false
    }

    private func looksLikeFileTarget(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("./") || path.contains("/")
    }
}

private struct JumpToLatestButton: View {
    @Environment(\.palette) private var palette
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 34, height: 34)
                .background(hovering ? palette.surface : palette.elevated, in: Circle())
                .overlay(Circle().stroke(hovering ? palette.borderStrong : palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.10), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.hairline, lineWidth: 1)
                    )
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
    @State private var hovering = false

    var body: some View {
        let url = ChatLinkDetector.resolve(path, baseDirectory: model.client.workingDirectory)?.url
            ?? URL(fileURLWithPath: path)
        Button {
            ChatLinkActions.activate(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.tertiary)
                Text(title ?? path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(hovering ? palette.text : palette.text.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2)
            .background(
                hovering ? palette.selected : palette.chip,
                in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .stroke(hovering ? palette.borderStrong : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
        .contextMenu { ChatLinkContextButtons(url: url) }
    }
}
