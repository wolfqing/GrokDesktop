import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var isChinese: Bool { model.language.resolved() == .chinese }

    @State private var showModelMenu = false

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
                    if !draftImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draftImages, id: \.path) { url in
                                    DraftImageThumb(url: url)
                                }
                            }
                        }
                    }
                    TextField(l10n.askAnything, text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .lineLimit(1...8)
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

                    HStack(spacing: 8) {
                        Button {
                            showModelMenu = false
                            model.showAttachMenu.toggle()
                        } label: {
                            Image(systemName: model.showAttachMenu ? "xmark" : "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("@")
                        .popover(isPresented: $model.showAttachMenu, arrowEdge: .bottom) {
                            attachMenu
                        }

                        Menu {
                            ForEach(AgentMode.allCases) { mode in
                                Button {
                                    model.client.setMode(mode)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title(chinese: isChinese))
                                        Text(mode.subtitle(chinese: isChinese))
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.secondary)
                                    }
                                }
                            }
                        } label: {
                            chip(model.client.mode.title(chinese: isChinese))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(model.client.mode.subtitle(chinese: isChinese))

                        Spacer(minLength: 8)

                        usageChip

                        ModelEffortPicker(
                            isOpen: $showModelMenu,
                            buildModel: $model.client.buildModel,
                            effort: $model.client.effort,
                            chinese: isChinese,
                            applyTier: { model.client.apply(tier: $0) }
                        )

                        if model.client.hasActiveWork {
                            Button {
                                if !model.client.isStopping { model.client.stopWork() }
                            } label: {
                                Group {
                                    if model.client.isStopping {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                }
                                .foregroundStyle(palette.sendGlyph)
                                .frame(width: 30, height: 30)
                                .background(palette.send, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.client.isStopping)
                            .help(model.client.isStopping ? l10n.stopping : l10n.stop)
                        }

                        Button(action: { submit() }) {
                            Image(systemName: sendSymbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(canSend ? palette.sendGlyph : palette.secondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    canSend ? palette.send : palette.chip,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(palette.input, in: RoundedRectangle(cornerRadius: GrokTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GrokTheme.inputRadius, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 1)
                )
            }

            if !model.client.promptQueue.isEmpty {
                Text(l10n.t("Queued \(model.client.promptQueue.count)", "已排队 \(model.client.promptQueue.count) 条"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 6)
            }

            Button {
                model.chooseWorkingDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(model.client.workingDirectory.lastPathComponent)
                        .lineLimit(1)
                    if model.isHomeDirectory {
                        Text(l10n.t("pick a project", "先选项目"))
                            .foregroundStyle(Color.orange)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help(model.client.workingDirectory.path)
            .padding(.horizontal, 6)
        }
        .onExitCommand {
            _ = model.handleEscape()
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

    private var usageChip: some View {
        Button {
            model.openUsage()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(palette.secondary.opacity(0.28), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(usagePercent, 0), 100)) / 100)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                Text(model.accountUsage.isLoaded ? "\(usagePercent)%" : "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(l10n.t("Account usage", "账号用量"))
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
            SuggestSection(title: l10n.t("Files", "文件"))
            if model.mentionMatches.isEmpty {
                Text(l10n.t("No matching files", "没有匹配的文件"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                ForEach(model.mentionMatches, id: \.path) { url in
                    SuggestRow(
                        icon: "doc",
                        title: url.lastPathComponent,
                        detail: url.deletingLastPathComponent().lastPathComponent
                    ) {
                        model.insertMention(url)
                    }
                }
            }
        }
    }

    private func chip(_ title: String, accent: Color? = nil) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent ?? palette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.chip, in: Capsule())
    }

    private var attachMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachItem(l10n.t("Attach file (@)", "附加文件 (@)"), systemImage: "doc") { attachFiles() }
            attachItem(l10n.t("Paste image", "粘贴图片"), systemImage: "photo") {
                model.showAttachMenu = false
                model.pasteAttachments()
            }
            attachItem(l10n.t("Working directory", "工作目录"), systemImage: "folder") {
                model.showAttachMenu = false
                model.chooseWorkingDirectory()
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
    }

    private func attachItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sendSymbol: String {
        "arrow.up"
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(forceNow: Bool = false) {
        model.dismissComposerSuggestions()
        showModelMenu = false
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.pendingBusySend != nil, text.isEmpty {
            model.confirmBusySendNow()
            return
        }
        if model.client.isTurnRunning {
            if text.isEmpty {
                model.client.cancelTurn()
                return
            }
            if forceNow {
                model.pendingBusySend = text
                model.draft = ""
                model.confirmBusySendNow()
                return
            }
            model.beginBusySend(text)
            return
        }
        if SlashBuiltins.handles(model.draft) {
            model.handleCommand(model.draft)
            model.draft = ""
            return
        }
        model.sendDraft()
    }

    private func attachFiles() {
        model.showAttachMenu = false
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "@"
        guard panel.runModal() == .OK else { return }
        let refs = panel.urls.map { "@\($0.path)" }.joined(separator: " ")
        if model.draft.isEmpty {
            model.draft = refs + " "
        } else {
            model.draft += " " + refs
        }
    }
}

private struct DraftImageThumb: View {
    let url: URL
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(palette.secondary)
                    .frame(width: 72, height: 72)
            }
        }
        .background(palette.chip)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 14))
                    .lineLimit(3)
            } else if images.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .lineLimit(3)
            }
            Text(l10n.busySendDetail)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                Button(l10n.sendNow) { model.confirmBusySendNow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.send, in: Capsule())
                    .foregroundStyle(palette.sendGlyph)
                    .keyboardShortcut(.return, modifiers: [])

                Button(l10n.editPrompt) { model.confirmBusyEdit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.chip, in: Capsule())
                    .keyboardShortcut(.escape, modifiers: [])

                Button(l10n.cancelPrompt) { model.confirmBusyCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.chip, in: Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
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
