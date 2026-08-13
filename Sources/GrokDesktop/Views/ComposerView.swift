import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var isChinese: Bool { model.language.resolved() == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(l10n.askAnything, text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .lineLimit(1...8)
                        .onSubmit {
                            if model.requireCmdEnter || NSEvent.modifierFlags.contains(.shift) {
                                model.draft += "\n"
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

                        Spacer()

                        usageChip

                        Menu {
                            ForEach(ModelTier.allCases) { tier in
                                Button(tier.menuTitle) { model.client.apply(tier: tier) }
                            }
                        } label: {
                            Text(model.client.modelTier.menuTitle)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .help(model.client.modelTier.menuSubtitle)

                        Menu {
                            ForEach(EffortLevel.allCases) { level in
                                Button(level.title(chinese: isChinese)) { model.client.effort = level }
                            }
                        } label: {
                            Text(model.client.effort.title(chinese: isChinese))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.purple)
                        }
                        .menuStyle(.borderlessButton)

                        Button(action: submit) {
                            Image(systemName: sendSymbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(canSend || model.client.isTurnRunning ? palette.sendGlyph : palette.secondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    canSend || model.client.isTurnRunning ? palette.send : palette.chip,
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
        HStack(spacing: 5) {
            Circle()
                .trim(from: 0, to: CGFloat(min(max(model.workspace.contextPercent, 1), 100)) / 100)
                .stroke(Color.orange, lineWidth: 2)
                .rotationEffect(.degrees(-90))
                .frame(width: 12, height: 12)
            Text("\(model.workspace.contextPercent)%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondary)
        }
        .help("/context")
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.secondary)
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
        if model.client.isTurnRunning { return "stop.fill" }
        return "arrow.up"
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        model.showAttachMenu = false
        if model.client.isTurnRunning {
            model.client.cancelTurn()
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
