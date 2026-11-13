import AppKit
import GrokDesktopCore
import SwiftUI

struct MessageMarkdownView: View {
    let text: String
    var fontSize: CGFloat = 14
    var live = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var copiedKey: String?

    var body: some View {
        if live {
            LinkedText(text: text, fontSize: fontSize, markdown: false, live: true)
        } else {
            finishedBlocks
        }
    }

    private var finishedBlocks: some View {
        VStack(alignment: .leading, spacing: GrokTheme.chatBlockSpacing(compact: fontSize < 13.5)) {
            ForEach(Array(ChatMarkdown.blocks(in: text).enumerated()), id: \.offset) { index, block in
                switch block {
                case .prose(let value):
                    LinkedText(text: value, fontSize: fontSize, markdown: true, live: live)
                case .heading(let level, let value):
                    Text(value)
                        .font(.system(size: GrokTheme.chatHeadingSize(level: level, compact: fontSize < 13.5), weight: .semibold))
                        .foregroundStyle(palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 6 : 3)
                case .table(let table):
                    ChatTableView(table: table, fontSize: fontSize)
                case .code(let language, let code):
                    CodeBlockCard(
                        key: "\(index)-\(language)-\(code.prefix(24))",
                        language: language,
                        code: code,
                        fontSize: GrokTheme.chatCodeSize(compact: fontSize < 13.5),
                        wrapLines: model.wrapCodeLines,
                        live: live,
                        copiedKey: $copiedKey
                    )
                }
            }
        }
    }
}

private struct CodeBlockCard: View {
    let key: String
    let language: String
    let code: String
    let fontSize: CGFloat
    let wrapLines: Bool
    let live: Bool
    @Binding var copiedKey: String?

    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var copyHover = false

    private var isCopied: Bool { copiedKey == key }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedKey = key
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if copiedKey == key {
                            copiedKey = nil
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(isCopied ? l10n.copied : l10n.t("Copy", "复制"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? palette.success : (copyHover ? palette.text : palette.secondary))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        copyHover || isCopied ? palette.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { copyHover = $0 }
                .help(isCopied ? l10n.copied : l10n.t("Copy code", "复制代码"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(palette.codeHeader)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }

            if wrapLines {
                LinkedText(
                    text: code,
                    fontSize: fontSize,
                    monospaced: true,
                    markdown: false,
                    live: live
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LinkedText(
                        text: code,
                        fontSize: fontSize,
                        monospaced: true,
                        markdown: false,
                        fillsWidth: false,
                        maxContentWidth: 4000,
                        live: live
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .frame(minWidth: 88, maxWidth: 260, alignment: alignment.frame)
            .padding(.horizontal, 11)
            .padding(.vertical, header ? 8.5 : 7.5)
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            .background(header ? palette.codeHeader : Color.clear)
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
