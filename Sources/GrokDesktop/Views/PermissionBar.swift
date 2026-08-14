import GrokDesktopCore
import SwiftUI

struct PermissionBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let request: PermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("Needs your OK", "需要你点头"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text(request.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(3)
            HStack(spacing: 8) {
                if let allow = allowOption {
                    Button(l10n.t("Allow once", "允许一次")) {
                        model.client.answerPermission(optionID: allow.id)
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())

                    Menu {
                        Button(l10n.t("Allow for this session", "本会话都允许")) {
                            model.client.answerPermission(optionID: allow.id, rememberSession: true)
                        }
                        Button(l10n.t("Allow edits this session", "本会话允许编辑")) {
                            model.client.setAllowEditsThisSession(true)
                            model.client.answerPermission(optionID: allow.id)
                        }
                        ForEach(request.options.filter { extraOption($0) }) { option in
                            Button(option.name) {
                                model.client.answerPermission(optionID: option.id)
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
                    model.client.rejectPermission()
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
        .padding(.horizontal, 24)
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
