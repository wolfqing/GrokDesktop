import AppKit
import GrokDesktopCore
import SwiftUI

struct MessageMarkdownView: View {
    let text: String
    var fontSize: CGFloat = 16
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var copiedLanguage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ChatMarkdown.blocks(in: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let value):
                    LinkedText(text: value, fontSize: fontSize, markdown: true)
                case .code(let language, let code):
                    codeBlock(language: language, code: code)
                }
            }
        }
    }

    private func codeBlock(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedLanguage = language + code.prefix(24)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copiedLanguage = nil
                    }
                } label: {
                    Image(systemName: copiedLanguage == language + code.prefix(24) ? "checkmark" : "square.on.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .help(copiedLanguage == language + code.prefix(24) ? l10n.copied : l10n.t("Copy code", "复制代码"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            LinkedText(text: code, fontSize: 12.5, monospaced: true, markdown: false)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
