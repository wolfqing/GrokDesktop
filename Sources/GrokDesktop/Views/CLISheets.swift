import GrokDesktopCore
import SwiftUI

struct OverlaySheet<Content: View>: View {
    @Environment(\.palette) private var palette
    var width: CGFloat = 520
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(20)
            .frame(width: width)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hairline))
        }
    }
}

struct PromptHistorySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var query = ""

    var body: some View {
        OverlaySheet(width: 520, onDismiss: { model.showPromptHistory = false }) {
            Text(l10n.t("Prompt history", "提示词历史"))
                .font(.system(size: 16, weight: .semibold))
            TextField(l10n.searchEllipsis, text: $query)
                .textFieldStyle(.plain)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            if filtered.isEmpty {
                Text(l10n.t("No saved prompts yet. Send something first, or press ↑ on an empty composer.", "还没有保存的提示词。先发送一条，或在空输入框按 ↑。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, text in
                            Button {
                                model.applyHistory(text)
                            } label: {
                                Text(text)
                                    .font(.system(size: 13))
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 320)
            }
        }
    }

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return model.promptHistory }
        return model.promptHistory.filter { $0.localizedCaseInsensitiveContains(needle) }
    }
}

struct CLIReportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 640, onDismiss: { model.showCLIReport = false }) {
            HStack {
                Text(model.cliReportTitle)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(l10n.t("Copy", "复制")) {
                    model.copyText(model.cliReportBody)
                    model.flash(l10n.copied)
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
            ScrollView {
                Text(model.cliReportBody)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 380)
        }
    }
}

struct DocsPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 520, onDismiss: { model.showDocsPicker = false }) {
            Text(model.docsPickerTutorial
                 ? l10n.t("Tutorial", "教程")
                 : l10n.t("How-to guides", "使用指南"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(guides) { guide in
                        Button {
                            model.openGuide(guide)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guide.title)
                                    .font(.system(size: 14, weight: .medium))
                                Text(guide.filename)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 360)
            Button(l10n.t("Open web docs", "打开网页文档")) {
                model.showDocsPicker = false
                model.openDocs()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
    }

    private var guides: [LocalGuide] {
        model.docsPickerTutorial ? LocalGuides.tutorial() : LocalGuides.all()
    }
}

struct FeedbackSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 480, onDismiss: { model.showFeedbackSheet = false }) {
            Text(l10n.t("Feedback", "反馈"))
                .font(.system(size: 16, weight: .semibold))
            Text(l10n.t("This is sent as /feedback in the current session.", "会作为 /feedback 发到当前会话。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(l10n.t("What happened?", "发生了什么？"), text: $model.feedbackDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button(l10n.t("Send", "发送")) { model.submitFeedback() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct ShortcutsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 560, onDismiss: { model.showShortcuts = false }) {
            Text(l10n.t("Shortcuts", "快捷键"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    row("⌘N", l10n.t("New chat", "新对话"))
                    row("⌘K / ⌘P", l10n.t("Command palette", "命令面板"))
                    row("⌘,", l10n.t("Settings", "设置"))
                    row("⌘⇧R", l10n.t("Resume session", "恢复会话"))
                    row("⌘Y", l10n.t("Prompt history", "提示词历史"))
                    row("⌘I", l10n.t("Inspector", "右侧栏"))
                    row("⇧⇥", l10n.t("Cycle permission mode", "切换权限模式"))
                    row("⌃\\", l10n.t("Dashboard", "任务面板"))
                    row("↑ / ↓", l10n.t("Recall previous prompts", "回忆上一条提示词"))
                    row("Esc Esc", l10n.t("Clear prompt, or rewind if empty", "清空输入；空输入则回退一轮"))
                    row("Esc", l10n.t("Stop a running turn", "停止进行中的任务"))
                    row("/", l10n.t("Slash commands", "斜杠命令"))
                    row("@", l10n.t("Attach a file", "附加文件"))
                }
            }
            .frame(height: 360)
        }
    }

    private func row(_ key: String, _ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.secondary)
        }
        .font(.system(size: 13))
        .padding(.vertical, 2)
    }
}

struct ClaudeImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 600, onDismiss: { model.showClaudeImport = false }) {
            Text(l10n.t("Import Claude settings", "导入 Claude 设置"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                Text(model.claudeImport.report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 280)
            HStack {
                Button(l10n.t("Import MCP", "导入 MCP")) {
                    model.importClaudeMCP()
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(model.claudeImport.servers.isEmpty)
                Button(l10n.t("Ask Grok to finish", "交给 Grok 处理其余")) {
                    model.sendClaudeImportToAgent()
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Spacer()
            }
        }
    }
}
