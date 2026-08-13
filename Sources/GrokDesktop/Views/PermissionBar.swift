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
            HStack(spacing: 8) {
                ForEach(request.options) { option in
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

    private func background(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? palette.chip : palette.send
    }

    private func foreground(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? palette.text : palette.sendGlyph
    }
}
