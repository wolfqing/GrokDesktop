import AppKit
import GrokDesktopCore
import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showModelMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("向 Grok 提任何问题", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...8)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        model.draft += "\n"
                    } else {
                        submit()
                    }
                }
                .onChange(of: model.draft) { _, value in
                    model.showPalette = value.hasPrefix("/") && !value.contains("\n")
                }

            HStack {
                Button {
                    attach()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(GrokTheme.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .help("附件")

                Spacer()

                Menu {
                    ForEach(ModelTier.allCases) { tier in
                        Button {
                            model.client.modelTier = tier
                        } label: {
                            VStack(alignment: .leading) {
                                Text(tier.menuTitle)
                                Text(tier.menuSubtitle)
                                    .font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.client.modelTier.menuTitle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button(action: submit) {
                    Image(systemName: model.client.isTurnRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSend || model.client.isTurnRunning ? GrokTheme.canvas : GrokTheme.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            canSend || model.client.isTurnRunning ? GrokTheme.text : GrokTheme.chip,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !model.client.isTurnRunning)
            }
        }
        .padding(14)
        .background(GrokTheme.input, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(GrokTheme.hairline, lineWidth: 1)
        )
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
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

    private func attach() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "附加"
        guard panel.runModal() == .OK else { return }
        let refs = panel.urls.map { "@\($0.path)" }.joined(separator: " ")
        if model.draft.isEmpty {
            model.draft = refs + " "
        } else {
            model.draft += " " + refs
        }
    }
}
