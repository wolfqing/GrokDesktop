import SwiftUI

struct ImagineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: l10n.imagine,
                subtitle: l10n.t("Describe an image. This sends /imagine to the local grok agent.", "描述一张图。会把 /imagine 发给本机 grok。")
            )
            TextField(l10n.t("A still from a rainy street at night", "雨夜街道"), text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(3...8)
                .padding(14)
                .background(palette.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(l10n.t("Generate", "生成")) {
                let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                model.destination = .chat
                model.draft = "/imagine \(text)"
                model.sendDraft()
            }
            .buttonStyle(GrokPrimaryButtonStyle())
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }
}
