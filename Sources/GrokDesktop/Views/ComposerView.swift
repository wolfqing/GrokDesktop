import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var isChinese: Bool { model.showsChinese }

    @State private var showModelMenu = false
    @FocusState private var editorFocused: Bool
    @StateObject private var speech = DictateCapture()
    @State private var spoken = ""
    @State private var speechBase = ""
    @State private var discardSpoken = false

    private var draftImages: [URL] {
        PromptMedia.imageURLs(in: model.draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = model.pendingBusySend {
                BusySendBar(text: pending)
            }
            if showsSuggestPanel {
                suggestPanel
                    .zIndex(8)
            }
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.goalMode {
                        goalModeChip
                    }
                    if !draftImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draftImages, id: \.path) { url in
                                    DraftImageThumb(url: url)
                                }
                            }
                        }
                    }
                    TextField(composerPlaceholder, text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1...8)
                        .focused($editorFocused)
                        .onSubmit {
                            let modifiers = NSEvent.modifierFlags
                            if model.requireCmdEnter && !modifiers.contains(.command) && !modifiers.contains(.control) {
                                model.draft += "\n"
                            } else if modifiers.contains(.shift) {
                                model.draft += "\n"
                            } else if model.client.isTurnRunning && canSend && (modifiers.contains(.command) || modifiers.contains(.control)) {
                                submit(forceNow: true)
                            } else {
                                submit()
                            }
                        }
                        .onChange(of: model.draft) { _, value in
                            if model.suppressSuggest {
                                model.suppressSuggest = false
                                return
                            }
                            model.showPalette = value.hasPrefix("/") && !value.contains(where: \.isWhitespace)
                            model.updateMentions(from: value)
                        }
                    if !speech.status.isEmpty {
                        Text(speech.status)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }

                    if speech.listening {
                        recordingBar
                    } else {
                        HStack(spacing: 6) {
                            GrokIconButton(
                                systemImage: model.showAttachMenu ? "xmark" : "plus",
                                size: 28,
                                iconSize: 12.5,
                                selected: model.showAttachMenu,
                                cornerRadius: 8,
                                helpText: l10n.t("Attach or mention (@)", "附加文件或引用 (@)")
                            ) {
                                showModelMenu = false
                                model.showAttachMenu.toggle()
                            }
                            .popover(isPresented: $model.showAttachMenu, arrowEdge: .bottom) {
                                attachMenu
                            }

                            modeMenu

                            Spacer(minLength: 8)

                            usageChip

                            ModelEffortPicker(
                                isOpen: $showModelMenu,
                                modelID: $model.client.buildModel,
                                choices: model.modelChoices,
                                effort: $model.client.effort,
                                chinese: isChinese,
                                refreshChoices: { model.refreshModelChoices() },
                                applyTier: { model.client.apply(tier: $0) }
                            )

                            GrokIconButton(
                                systemImage: "mic",
                                size: 28,
                                iconSize: 13.5,
                                cornerRadius: 8,
                                helpText: l10n.t("Speak", "口述")
                            ) {
                                toggleSpeech()
                            }

                            if model.client.hasActiveWork {
                                ComposerCircleButton(
                                    systemImage: "stop.fill",
                                    loading: model.client.isStopping,
                                    active: true,
                                    fill: palette.send,
                                    glyph: palette.sendGlyph,
                                    helpText: model.client.isStopping ? l10n.stopping : "\(l10n.stop) (Esc)"
                                ) {
                                    if !model.client.isStopping { model.client.stopWork() }
                                }
                                .disabled(model.client.isStopping)
                            }

                            sendButton
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 11)
                .background(
                    editorFocused ? palette.inputFocused : palette.input,
                    in: RoundedRectangle(cornerRadius: GrokTheme.inputRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GrokTheme.inputRadius, style: .continuous)
                        .stroke(editorFocused ? palette.focusRing : palette.hairline, lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(palette.isDark ? (editorFocused ? 0.36 : 0.20) : (editorFocused ? 0.07 : 0.03)),
                    radius: editorFocused ? 14 : 6,
                    y: editorFocused ? 5 : 2
                )
                .animation(.easeOut(duration: 0.15), value: editorFocused)
            }

            if !model.client.promptQueue.isEmpty {
                queuePanel
            }

            if model.isHomeDirectory {
                Button {
                    model.chooseWorkingDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.questionmark")
                        Text(model.client.workingDirectory.lastPathComponent)
                            .lineLimit(1)
                        Text("·")
                        Text(l10n.t("Pick a project folder", "建议先选项目目录"))
                            .foregroundStyle(palette.warning)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .grokHover(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help(model.client.workingDirectory.path)
            }
        }
        .onExitCommand {
            _ = model.handleEscape()
        }
        .onDisappear {
            if speech.listening { commitSpoken() }
        }
        .onChange(of: speech.listening) { _, listening in
            guard !listening else { return }
            if discardSpoken {
                discardSpoken = false
                spoken = ""
                return
            }
            let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            spoken = ""
            guard !text.isEmpty else { return }
            model.suppressSuggest = true
            model.draft = Self.spokenDraft(base: speechBase, spoken: text)
        }
        .background(ComposerKeyMonitor())
        .onPasteCommand(of: [.image, .fileURL]) { _ in
            model.pasteAttachments()
        }
        .onChange(of: model.showAttachMenu) { _, open in
            if open { showModelMenu = false }
        }
        .onChange(of: model.showPalette) { _, open in
            if open {
                showModelMenu = false
                model.showAttachMenu = false
            }
        }
        .onChange(of: model.mentionQuery) { _, query in
            if query != nil {
                showModelMenu = false
                model.showAttachMenu = false
            }
        }
    }

    private var modeMenu: some View {
        Menu {
            ForEach(AgentMode.allCases) { mode in
                Button {
                    model.client.setMode(mode)
                } label: {
                    Label(
                        "\(mode.title(chinese: isChinese)) — \(mode.subtitle(chinese: isChinese))",
                        systemImage: modeIcon(mode)
                    )
                }
            }
        } label: {
            ModePillLabel(
                icon: modeIcon(model.client.mode),
                title: model.client.mode.title(chinese: isChinese),
                accent: modeAccent(model.client.mode)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(model.client.mode.subtitle(chinese: isChinese)) (⇧⇥)")
    }

    private func modeIcon(_ mode: AgentMode) -> String {
        switch mode {
        case .normal: return "hand.raised"
        case .plan: return "point.topleft.down.to.point.bottomright.curvepath"
        case .auto: return "bolt.shield"
        case .alwaysApprove: return "checkmark.shield.fill"
        }
    }

    private func modeAccent(_ mode: AgentMode) -> Color? {
        switch mode {
        case .normal: return nil
        case .plan: return palette.info
        case .auto: return palette.success
        case .alwaysApprove: return palette.warning
        }
    }

    private var usageChip: some View {
        UsagePillButton(
            percent: usagePercent,
            isLoaded: model.accountUsage.isLoaded,
            helpText: l10n.t("Account usage", "账号用量")
        ) {
            model.openUsage()
        }
    }

    private var usagePercent: Int {
        model.accountUsage.displayPercent
    }

    private var showsSuggestPanel: Bool {
        model.mentionQuery != nil || model.showPalette
    }

    @ViewBuilder
    private var suggestPanel: some View {
        if model.mentionQuery != nil {
            mentionPanel
        } else if model.showPalette {
            CommandPalette(embedded: true)
        }
    }

    private var mentionPanel: some View {
        ComposerSuggestChrome {
            SuggestSection(title: l10n.t("Add", "添加"))
            SuggestRow(
                icon: "paperclip",
                title: l10n.t("Files and folders", "文件和文件夹"),
                detail: l10n.t("Attach from disk", "从磁盘附加")
            ) {
                attachFiles()
            }
            SuggestRow(
                icon: "photo",
                title: l10n.t("Paste image", "粘贴图片"),
                detail: l10n.t("Use the clipboard image", "使用剪贴板里的图")
            ) {
                model.mentionQuery = nil
                model.pasteAttachments()
            }
            SuggestRow(
                icon: "folder",
                title: l10n.t("Working directory", "工作目录"),
                detail: model.client.workingDirectory.path
            ) {
                model.mentionQuery = nil
                model.chooseWorkingDirectory()
            }
            SuggestRow(
                icon: model.goalMode ? "flag.fill" : "flag",
                title: l10n.t("Goal mode", "目标模式"),
                detail: model.goalMode
                    ? l10n.t("On — keep going until the goal is done", "已开 — 做到为止")
                    : l10n.t("Keep working until the goal is done", "做到为止，不达目标不停")
            ) {
                model.toggleGoalMode()
            }
            SuggestSection(title: l10n.t("Files", "文件"))
            if model.mentionMatches.isEmpty {
                Text(l10n.t("No matching files", "没有匹配的文件"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                ForEach(model.mentionMatches, id: \.path) { url in
                    SuggestRow(
                        icon: "doc.text",
                        title: url.lastPathComponent,
                        detail: url.deletingLastPathComponent().lastPathComponent
                    ) {
                        model.insertMention(url)
                    }
                }
            }
        }
    }

    private var composerPlaceholder: String {
        if model.goalMode {
            return l10n.t("Describe the goal to keep working toward…", "写一个要做到的目标…")
        }
        return l10n.askAnything
    }

    private var goalModeChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.warning)
            Text(l10n.t("Goal mode", "目标模式"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.text)
            Button {
                model.goalMode = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t("Turn off goal mode", "关闭目标模式"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(palette.warning.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(palette.warning.opacity(0.28), lineWidth: 1))
        .help(l10n.t("This prompt is sent as /goal. The agent keeps going until it’s done.", "这条会按 /goal 发出。做到为止。"))
    }

    private var attachMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            attachItem(l10n.t("Attach file (@)", "附加文件 (@)"), systemImage: "doc") { attachFiles() }
            attachItem(l10n.t("Paste image", "粘贴图片"), systemImage: "photo") {
                model.showAttachMenu = false
                model.pasteAttachments()
            }
            attachItem(l10n.t("Working directory", "工作目录"), systemImage: "folder") {
                model.showAttachMenu = false
                model.chooseWorkingDirectory()
            }
            attachItem(
                model.goalMode
                    ? l10n.t("Goal mode · On", "目标模式 · 开")
                    : l10n.t("Goal mode", "目标模式"),
                systemImage: model.goalMode ? "flag.fill" : "flag"
            ) {
                model.toggleGoalMode()
            }
        }
        .padding(6)
        .frame(width: 216)
    }

    private func attachItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .grokHover(cornerRadius: 7)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sendSymbol: String {
        "arrow.up"
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (speech.listening && !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var sendButton: some View {
        let active = canSend || speech.listening
        return ComposerCircleButton(
            systemImage: sendSymbol,
            loading: false,
            active: active,
            fill: active ? palette.send : palette.chip,
            glyph: active ? palette.sendGlyph : palette.tertiary,
            helpText: model.requireCmdEnter ? "⌘⏎" : "⏎"
        ) {
            submit()
        }
        .disabled(!active)
    }

    private var recordingBar: some View {
        HStack(spacing: 8) {
            Button(action: cancelSpeech) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 30, height: 30)
                    .background(palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .help(l10n.t("Cancel", "取消"))

            VoiceWaveform(levels: speech.levels, quiet: palette.secondary, loud: palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 30)

            Button(action: finishSpeech) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(palette.text)
                    .frame(width: 9, height: 9)
                    .frame(width: 30, height: 30)
                    .background(palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .help(l10n.t("Stop speaking", "说完"))

            sendButton
        }
    }

    private func toggleSpeech() {
        guard !speech.listening else { return }
        discardSpoken = false
        spoken = ""
        speechBase = model.draft
        speech.toggle(
            localeID: model.desk.localeID,
            deniedSpeech: l10n.t("Speech recognition is off.", "语音识别没有打开。"),
            deniedMic: l10n.t("The microphone is off.", "麦克风没有打开。"),
            unavailable: l10n.t("Speech recognition is not available.", "这台 Mac 不能做语音识别。"),
            onPartial: { applySpoken($0) },
            onFinal: { applySpoken($0) }
        )
    }

    private func applySpoken(_ text: String) {
        spoken = text
        model.suppressSuggest = true
        model.draft = Self.spokenDraft(base: speechBase, spoken: text)
    }

    private func cancelSpeech() {
        spoken = ""
        discardSpoken = true
        model.suppressSuggest = true
        model.draft = speechBase
        speech.stop()
    }

    private func finishSpeech() {
        commitSpoken()
    }

    private func commitSpoken() {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        spoken = ""
        discardSpoken = true
        speech.stop()
        guard !text.isEmpty else { return }
        model.suppressSuggest = true
        model.draft = Self.spokenDraft(base: speechBase, spoken: text)
    }

    private static func spokenDraft(base: String, spoken: String) -> String {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return base }
        guard !base.isEmpty else { return spoken }
        if base.last?.isWhitespace == true { return base + spoken }
        return base + " " + spoken
    }

    private func submit(forceNow: Bool = false) {
        if speech.listening { commitSpoken() }
        model.dismissComposerSuggestions()
        showModelMenu = false
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.pendingBusySend != nil {
            if text.isEmpty {
                model.confirmBusySendNow()
            }
            return
        }
        if SlashBuiltins.handles(model.draft) {
            model.handleCommand(model.draft)
            model.draft = ""
            return
        }
        if text.isEmpty {
            return
        }
        if forceNow, model.client.isTurnRunning, !text.isEmpty {
            model.beginBusySend(text)
            return
        }
        model.sendDraft()
    }

    private var queuePanel: some View {
        let items = model.client.promptQueue
        let count = items.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(queueHeader(count))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
            if count > 3 {
                ScrollView {
                    queueStack(items)
                }
                .scrollIndicators(.visible)
                .frame(height: 210)
            } else {
                queueStack(items)
            }
        }
        .padding(.horizontal, 4)
    }

    private func queueStack(_ items: [QueuedPrompt]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                queuedRow(item, isNext: index == 0)
            }
        }
    }

    private func queuedRow(_ item: QueuedPrompt, isNext: Bool) -> some View {
        let images = PromptMedia.imageURLs(in: item.text)
        let raw = item.kind == .aside ? SessionFold.asideDisplay(item.text) : item.text
        let shown = PromptMedia.displayText(raw)
        let armed = model.client.armedQueueID == item.id
        let handoff = model.client.armedQueueID != nil
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: item.kind == .aside ? "text.bubble" : "clock")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 14)
            if let first = images.first {
                DraftImageThumb(url: first, size: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow = queueEyebrow(item, isNext: isNext, armed: armed) {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                }
                Text(shown.isEmpty ? l10n.t("Image", "图片") : shown)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if images.count > 1 {
                    Text("+\(images.count - 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
            }
            Spacer(minLength: 8)
            if item.kind == .followUp, !armed {
                Button(l10n.sendNow) {
                    model.sendQueuedNow(id: item.id)
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                .opacity(handoff ? 0.35 : 1)
                .disabled(handoff)
                .help(
                    model.client.isTurnRunning
                        ? l10n.t("Cancel this turn and send this one next", "打断当前回合并马上发这一条")
                        : l10n.t("Send this prompt", "发送这条")
                )
            }
            GrokIconButton(
                systemImage: "xmark",
                size: 22,
                iconSize: 9.5,
                cornerRadius: 6,
                helpText: l10n.t("Remove from queue", "从队列移除")
            ) {
                model.client.removeQueuedPrompt(id: item.id)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .grokCard(cornerRadius: 11)
        .help(shown)
    }

    private func queueHeader(_ count: Int) -> String {
        if model.client.armedQueueID != nil {
            return l10n.t(
                "Ending this turn, then sending that prompt",
                "正在结束这一轮，随后发送这条"
            )
        }
        if model.client.holdQueue, model.client.isTurnRunning {
            return l10n.t(
                "Ending this turn. The other queued prompts stay.",
                "正在结束这一轮，其余排队保留"
            )
        }
        if !model.client.isTurnRunning {
            return l10n.t(
                "Queued \(count) — Send now runs one",
                "排队 \(count) 条 — 点立即发送发出"
            )
        }
        return l10n.t(
            "Queued \(count) — sends in order when this turn finishes",
            "排队 \(count) 条 — 当前回复结束后按顺序发送"
        )
    }

    private func queueEyebrow(_ item: QueuedPrompt, isNext: Bool, armed: Bool) -> String? {
        if armed {
            return l10n.t("Sending next", "即将发送")
        }
        if isNext, item.kind == .aside {
            return l10n.t("Next · Aside", "下一条 · 旁问")
        }
        if item.kind == .aside {
            return l10n.t("Aside", "旁问")
        }
        if isNext {
            return l10n.t("Next", "下一条")
        }
        return nil
    }

    private func attachFiles() {
        model.showAttachMenu = false
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "@"
        guard panel.runModal() == .OK else { return }
        let refs = panel.urls.map(PromptMedia.mentionToken(for:)).joined(separator: " ")
        if model.draft.isEmpty {
            model.draft = refs + " "
        } else {
            model.draft += " " + refs
        }
    }
}

private struct ModePillLabel: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    let accent: Color?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(accent ?? palette.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent ?? (hovering ? palette.text : palette.secondary))
            Image(systemName: "chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            accent != nil
                ? accent!.opacity(hovering ? 0.16 : 0.10)
                : (hovering ? palette.selected : palette.chip),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(accent != nil ? accent!.opacity(0.26) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct UsagePillButton: View {
    @Environment(\.palette) private var palette
    let percent: Int
    let isLoaded: Bool
    let helpText: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5.5) {
                ZStack {
                    Circle()
                        .stroke(palette.secondary.opacity(0.24), lineWidth: 1.8)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                        .stroke(
                            percent >= 85 ? palette.danger : palette.warning,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12.5, height: 12.5)
                Text(isLoaded ? "\(percent)%" : "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(hovering ? palette.text : palette.secondary)
            }
            .padding(.horizontal, 8.5)
            .padding(.vertical, 5)
            .background(hovering ? palette.selected : palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(helpText)
    }
}

private struct ComposerCircleButton: View {
    let systemImage: String
    let loading: Bool
    let active: Bool
    let fill: Color
    let glyph: Color
    let helpText: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 11.5, weight: .bold))
                }
            }
            .foregroundStyle(glyph)
            .frame(width: 28, height: 28)
            .background(fill, in: Circle())
            .opacity(active && hovering ? 0.88 : 1)
            .scaleEffect(active && hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(helpText)
    }
}

private struct DraftImageThumb: View {
    let url: URL
    var size: CGFloat = 72
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(palette.secondary)
                    .frame(width: size, height: size)
            }
        }
        .background(palette.chip)
        .clipShape(RoundedRectangle(cornerRadius: min(10, size / 4), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: min(10, size / 4), style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .help(url.lastPathComponent)
    }
}

struct BusySendBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.busySendTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            let images = PromptMedia.imageURLs(in: text)
            let shown = PromptMedia.displayText(text)
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.path) { url in
                            DraftImageThumb(url: url)
                        }
                    }
                }
            }
            if !shown.isEmpty {
                Text(shown)
                    .font(.system(size: 13.5))
                    .lineLimit(3)
            } else if images.isEmpty {
                Text(text)
                    .font(.system(size: 13.5))
                    .lineLimit(3)
            }
            Text(l10n.busySendDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                Button(l10n.sendNow) { model.confirmBusySendNow() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])

                Button(l10n.editPrompt) { model.confirmBusyEdit() }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])

                Button(l10n.cancelPrompt) { model.confirmBusyCancel() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grokCard(cornerRadius: 15)
    }
}

private struct VoiceWaveform: View {
    var levels: [CGFloat]
    var quiet: Color
    var loud: Color

    var body: some View {
        Canvas { context, size in
            let columns = max(24, Int(size.width / 4.2))
            let dot: CGFloat = 2.4
            let pitch: CGFloat = 3.4
            let mid = size.height / 2
            let count = max(levels.count, 1)
            for index in 0..<columns {
                let x = (CGFloat(index) + 0.5) * size.width / CGFloat(columns)
                let t = CGFloat(index) / CGFloat(max(columns - 1, 1))
                let window = exp(-pow((t - 0.5) / 0.27, 2))
                let sampleIndex = min(count - 1, Int(t * CGFloat(count - 1)))
                let sample = levels.isEmpty ? 0 : levels[sampleIndex]
                let now = levels.last ?? 0
                let amp = min(1, (sample * 0.65 + now * 0.7) * (0.18 + 0.82 * window))
                let dots = amp < 0.06 ? 1 : min(7, 1 + Int((amp * 6).rounded(.down)))
                let span = CGFloat(dots - 1) * pitch
                var y = mid - span / 2
                let color = dots == 1 ? quiet.opacity(0.42) : loud.opacity(0.55 + amp * 0.4)
                for _ in 0..<dots {
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    y += pitch
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private final class ComposerKeyMonitorBox: ObservableObject {
    var monitor: Any?

    func start(_ handler: @escaping (NSEvent) -> NSEvent?) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private struct ComposerKeyMonitor: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var box = ComposerKeyMonitorBox()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                box.start { event in
                    let keyCode = event.keyCode
                    let flags = event.modifierFlags.rawValue
                    let swallow = MainActor.assumeIsolated {
                        model.handleComposerKey(keyCode: keyCode, modifierFlags: flags)
                    }
                    return swallow ? nil : event
                }
            }
            .onDisappear {
                box.stop()
            }
    }
}
