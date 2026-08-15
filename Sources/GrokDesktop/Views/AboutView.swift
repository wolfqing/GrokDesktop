import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.9"
    }

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showAbout = false }

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        model.showAbout = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }

                GrokMark(size: 44)
                Text("Grok Desktop")
                    .font(.system(size: 20, weight: .semibold))
                Text("Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)

                Button {
                    if let url = URL(string: "https://github.com/wolfqing") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("build by wolfqing")
                        .font(.system(size: 13, weight: .medium))
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text)
                .help("https://github.com/wolfqing")

                Text(l10n.t("Community client for Grok Build. Not an official xAI product.", "Grok Build 社区客户端，不是 xAI 官方应用。"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(width: 320)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.hairline))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        }
    }
}
