import AppKit
import GrokDesktopCore
import SwiftUI

struct ImagineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var prompt = ""
    @State private var recent: [ImagineAsset] = []

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
            if !recent.isEmpty {
                Text(l10n.t("Recent", "最近生成"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(recent) { asset in
                        Button {
                            ChatLinkActions.open(asset.url)
                        } label: {
                            ImagineThumb(url: asset.url)
                        }
                        .buttonStyle(.plain)
                        .help(asset.url.lastPathComponent)
                        .contextMenu { ChatLinkContextButtons(url: asset.url) }
                    }
                }
            }
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
        .onAppear { recent = ImagineLibrary.recent() }
    }
}

private struct ImagineThumb: View {
    let url: URL
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .clipped()
        .background(palette.chip)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
