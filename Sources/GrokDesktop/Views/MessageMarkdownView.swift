import AppKit
import GrokDesktopCore
import SwiftUI

struct MessageMarkdownView: View {
    let text: String
    var fontSize: CGFloat = 16
    var live = false
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var copiedLanguage: String?

    var body: some View {
        if live {
            LinkedText(text: text, fontSize: fontSize, markdown: false, live: true)
        } else {
            finishedBlocks
        }
    }

    private var finishedBlocks: some View {
        VStack(alignment: .leading, spacing: GrokTheme.chatBlockSpacing(compact: fontSize < 15)) {
            ForEach(Array(ChatMarkdown.blocks(in: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let value):
                    LinkedText(text: value, fontSize: fontSize, markdown: true, live: live)
                case .heading(let level, let value):
                    Text(value)
                        .font(.system(size: GrokTheme.chatHeadingSize(level: level, compact: fontSize < 15), weight: .semibold))
                        .foregroundStyle(palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 4 : 2)
                case .table(let table):
                    ChatTableView(table: table, fontSize: fontSize)
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
                    .font(.system(size: GrokTheme.chatMetaSize(compact: fontSize < 15), weight: .medium, design: .monospaced))
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
            LinkedText(
                text: code,
                fontSize: GrokTheme.chatCodeSize(compact: fontSize < 14),
                monospaced: true,
                markdown: false,
                live: live
            )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ChatTableView: View {
    let table: ChatTable
    let fontSize: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, header: true, last: false, alignment: table.alignments[safe: index] ?? .leading)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            cellView(
                                cell,
                                header: false,
                                last: rowIndex == table.rows.count - 1,
                                alignment: table.alignments[safe: index] ?? .leading
                            )
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private func cellView(_ text: String, header: Bool, last: Bool, alignment: ChatTableAlignment) -> some View {
        Text(Self.attributed(text))
            .font(.system(size: max(fontSize - 1.5, 12), weight: header ? .semibold : .regular))
            .foregroundStyle(header ? palette.text : palette.text.opacity(0.92))
            .multilineTextAlignment(alignment.text)
            .textSelection(.enabled)
            .frame(minWidth: 88, maxWidth: 240, alignment: alignment.frame)
            .padding(.horizontal, 10)
            .padding(.vertical, header ? 8 : 7)
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            .background(header ? palette.chip : Color.clear)
            .overlay(alignment: .bottom) {
                if header || !last {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                }
            }
    }

    private static func attributed(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private extension ChatTableAlignment {
    var text: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
