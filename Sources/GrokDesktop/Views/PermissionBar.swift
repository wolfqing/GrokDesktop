import GrokDesktopCore
import SwiftUI

struct PermissionBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let request: PermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要批准")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text(request.title)
                .font(.system(size: 14))
                .lineLimit(4)
            Text(model.copy.t("The agent is waiting.", "agent 正在等你决定。"))
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                if let allow = allowOption {
                    Button(model.copy.t("Allow once", "允许一次")) {
                        model.client.answerPermission(optionID: allow.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.send, in: Capsule())
                    .foregroundStyle(palette.sendGlyph)

                    Button(model.copy.t("Allow session", "本会话允许")) {
                        model.client.answerPermission(optionID: allow.id, rememberSession: true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.chip, in: Capsule())

                    Button(model.copy.t("Allow edits", "允许本会话编辑")) {
                        model.client.setAllowEditsThisSession(true)
                        model.client.answerPermission(optionID: allow.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.chip, in: Capsule())
                }
                Button(model.copy.t("Deny", "拒绝")) {
                    model.client.rejectPermission()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.chip, in: Capsule())

                ForEach(request.options.filter { extraOption($0) }) { option in
                    Button(option.name) {
                        model.client.answerPermission(optionID: option.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(background(for: option), in: Capsule())
                    .foregroundStyle(foreground(for: option))
                }
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

    private func background(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? palette.chip : palette.send
    }

    private func foreground(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? palette.text : palette.sendGlyph
    }
}
