import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        model.showAttachMenu.toggle()
                    } label: {
                        Image(systemName: model.showAttachMenu ? "xmark" : "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.uploadFile)

                    TextField(l10n.whatsOnYourMind, text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .lineLimit(1...6)
                        .onSubmit {
                            if model.requireCmdEnter || NSEvent.modifierFlags.contains(.shift) {
                                model.draft += "\n"
                            } else {
                                submit()
                            }
                        }
                        .onChange(of: model.draft) { _, value in
                            model.showPalette = value.hasPrefix("/") && !value.contains("\n")
                        }

                    Menu {
                        ForEach(ModelTier.allCases) { tier in
                            Button(tier.menuTitle) {
                                model.client.modelTier = tier
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.client.modelTier.menuTitle)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.text)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button {
                        // Voice is not in the Build CLI path yet.
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("语音稍后接入")

                    Button(action: submit) {
                        Image(systemName: sendSymbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.sendGlyph)
                            .frame(width: 34, height: 34)
                            .background(palette.send, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !model.client.isTurnRunning)
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
            .background(palette.input, in: Capsule())
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(palette.isDark ? 0.35 : 0.06), radius: 18, y: 6)

            if model.showAttachMenu {
                attachMenu
                    .offset(x: 8, y: 56)
                    .zIndex(4)
            }
        }
    }

    private var attachMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachItem(l10n.uploadFile, systemImage: "square.and.arrow.up") { attachFiles() }
            attachItem(l10n.recent, systemImage: "clock", trailing: true) { }
            attachItem(l10n.project, systemImage: "folder", trailing: true) { model.chooseWorkingDirectory() }
            Divider().overlay(palette.hairline).padding(.vertical, 4)
            attachItem(l10n.skills, systemImage: "puzzlepiece.extension", trailing: true) {
                model.destination = .skills
                model.showAttachMenu = false
            }
            attachItem(l10n.addConnector, systemImage: "plus.square.on.square") {
                model.destination = .skills
                model.skillsTab = 1
                model.showAttachMenu = false
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

    private func attachItem(_ title: String, systemImage: String, trailing: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if trailing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                }
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
        if canSend { return "arrow.up" }
        return "waveform"
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

    private func attachFiles() {
        model.showAttachMenu = false
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        let refs = panel.urls.map { "@\($0.path)" }.joined(separator: " ")
        if model.draft.isEmpty {
            model.draft = refs + " "
        } else {
            model.draft += " " + refs
        }
    }
}
