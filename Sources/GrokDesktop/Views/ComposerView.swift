import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var isChinese: Bool { model.language.resolved() == .chinese }

    private var draftImages: [URL] {
        PromptMedia.imageURLs(in: model.draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = model.pendingBusySend {
                BusySendBar(text: pending)
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
                            model.showPalette = value.hasPrefix("/") && !value.contains("\n")
                            model.updateMentions(from: value)
                        }

                    HStack(spacing: 8) {
                        Button {
                            model.showAttachMenu.toggle()
                        } label: {
                            Image(systemName: model.showAttachMenu ? "xmark" : "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("@")

                        Menu {
                            ForEach(AgentMode.allCases) { mode in
                                Button(mode.title) { model.client.setMode(mode) }
                            }
                        } label: {
                            chip(model.client.mode.title)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Spacer(minLength: 8)

                        usageChip

                        modelEffortChip

                        if model.client.hasActiveWork {
                            Button {
                                model.client.stopWork()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.sendGlyph)
                                    .frame(width: 30, height: 30)
                                    .background(palette.send, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help(l10n.stop)
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

                if model.showAttachMenu {
                    attachMenu
                        .offset(x: 12, y: 88)
                        .zIndex(4)
                }
                if let query = model.mentionQuery {
                    mentionMenu(query)
                        .offset(x: 12, y: 88)
                        .zIndex(5)
                }
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
                    Text(model.client.workingDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
        .onPasteCommand(of: [.image, .fileURL]) { _ in
            model.pasteAttachments()
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

    private var modelEffortChip: some View {
        HStack(spacing: 5) {
            Text(model.client.buildModel.shortTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
            Text(model.client.effort.title(chinese: isChinese))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.purple)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.chip, in: Capsule())
        .overlay {
            Menu {
                Section(l10n.t("Model", "模型")) {
                    ForEach(BuildModel.allCases) { item in
                        Button {
                            model.client.buildModel = item
                        } label: {
                            menuLabel(item.menuTitle, selected: model.client.buildModel == item)
                        }
                    }
                }
                Section(l10n.t("Reasoning", "推理强度")) {
                    ForEach(EffortLevel.allCases) { level in
                        Button {
                            model.client.effort = level
                        } label: {
                            menuLabel(level.title(chinese: isChinese), selected: model.client.effort == level)
                        }
                    }
                }
                Section(l10n.t("Preset", "预设")) {
                    ForEach(ModelTier.allCases) { tier in
                        Button(tier.menuTitle) { model.client.apply(tier: tier) }
                    }
                }
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(0.001)
        }
        .fixedSize()
        .help("\(model.client.buildModel.menuTitle) · \(model.client.effort.title(chinese: isChinese))")
    }

    private func chip(_ title: String, accent: Color? = nil) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent ?? palette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.chip, in: Capsule())
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
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
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(palette.popover, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
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
        model.showAttachMenu = false
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
        if model.draft.hasPrefix("/") && !model.draft.contains(" ") && model.draft.count > 1 {
            model.handleCommand(model.draft)
            model.draft = ""
            return
        }
        model.sendDraft()
    }

    private func mentionMenu(_ query: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@\(query.isEmpty ? l10n.t("files", "文件") : query)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            if model.mentionMatches.isEmpty {
                Text(l10n.t("No matching files", "没有匹配的文件"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(12)
            } else {
                ForEach(model.mentionMatches, id: \.path) { url in
                    Button {
                        model.insertMention(url)
                    } label: {
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Text(url.deletingLastPathComponent().lastPathComponent)
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 280)
        .background(palette.popover, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hairline))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
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
