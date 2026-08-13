import GrokDesktopCore
import SwiftUI

struct PermissionBar: View {
    @EnvironmentObject private var model: AppModel
    let request: PermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要批准")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GrokTheme.secondary)
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
        .background(GrokTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GrokTheme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private func background(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? GrokTheme.chip : GrokTheme.text
    }

    private func foreground(for option: PermissionRequest.Option) -> Color {
        option.kind.contains("reject") ? GrokTheme.text : GrokTheme.canvas
    }
}
