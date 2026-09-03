import GrokDesktopCore
import SwiftUI

struct PermissionBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let request: PermissionRequest
    var sessionID: String? = nil
    var inset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("Needs your OK", "需要你点头"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            if !provenance.isEmpty {
                Text(provenance)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            Text(displayTitle)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(3)
            if !request.detail.isEmpty, request.detail != request.title {
                Text(request.detail)
                    .font(.system(size: 12, design: request.command == nil ? .default : .monospaced))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            if let path = request.path, !path.isEmpty {
                let url = ChatLinkDetector.resolve(path, baseDirectory: model.client.workingDirectory)?.url
                    ?? URL(fileURLWithPath: path)
                Button(url.lastPathComponent) {
                    ChatLinkActions.activate(url)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .linkColor))
                .help(path)
                .contextMenu { ChatLinkContextButtons(url: url) }
            }
            if !request.questions.isEmpty {
                ForEach(request.questions) { question in
                    VStack(alignment: .leading, spacing: 4) {
                        if !question.question.isEmpty {
                            Text(question.question)
                                .font(.system(size: 13, weight: .medium))
                        }
                        ForEach(question.options) { option in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 12, weight: .medium))
                                if !option.detail.isEmpty {
                                    Text(option.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if let allow = allowOption {
                    Button(l10n.t("Allow once", "允许一次")) {
                        model.client.answerPermission(optionID: allow.id, sessionID: sessionID)
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())

                    Menu {
                        Button(l10n.t("Allow for this session", "本会话都允许")) {
                            model.client.answerPermission(optionID: allow.id, rememberSession: true, sessionID: sessionID)
                        }
                        Button(l10n.t("Allow edits this session", "本会话允许编辑")) {
                            model.client.setAllowEditsThisSession(true)
                            model.client.answerPermission(optionID: allow.id, sessionID: sessionID)
                        }
                        ForEach(request.options.filter { extraOption($0) }) { option in
                            Button(option.name) {
                                model.client.answerPermission(optionID: option.id, sessionID: sessionID)
                            }
                        }
                    } label: {
                        Text(l10n.t("More", "更多"))
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(palette.chip, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Button(l10n.t("Deny", "拒绝")) {
                    model.client.rejectPermission(sessionID: sessionID)
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, inset ? 24 : 0)
    }

    private var provenance: String {
        let mode = model.client.mode.title(chinese: l10n.language == .chinese)
        switch request.source.lowercased() {
        case "rule":
            return l10n.t("Because a config rule asked", "因为配置规则要求询问") + " · \(mode)"
        case "hook":
            return l10n.t("Because a hook asked", "因为钩子要求询问") + " · \(mode)"
        case "classifier":
            return l10n.t("Because auto mode is unsure", "因为自动模式不确定") + " · \(mode)"
        case "session":
            return l10n.t("Remembered for this session", "本会话已记住") + " · \(mode)"
        case "mode":
            return mode
        case "":
            return l10n.t("Mode", "模式") + " · \(mode)"
        default:
            return "\(request.source) · \(mode)"
        }
    }

    private var displayTitle: String {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased() == "ask_user_question" || title.lowercased() == "ask user question" {
            return l10n.t("Grok has a question", "Grok 在问你")
        }
        return title
    }

    private var allowOption: PermissionRequest.Option? {
        request.options.first { !$0.kind.contains("reject") && !$0.id.contains("cancel") }
    }

    private func extraOption(_ option: PermissionRequest.Option) -> Bool {
        if option.id == allowOption?.id { return false }
        if option.kind.contains("reject") || option.id.contains("cancel") { return false }
        return true
    }
}
