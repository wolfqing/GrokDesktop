import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var version: String { AppBuild.marketingVersion }

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showAbout = false }

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    GrokIconButton(systemImage: "xmark", size: 26, iconSize: 11, cornerRadius: 7, helpText: "Esc") {
                        model.showAbout = false
                    }
                }

                GrokMark(size: 44)
                Text("Grok Desktop")
                    .font(.system(size: 20, weight: .semibold))
                Text("Version \(version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                if case .ready(let next) = model.appUpdateNotice {
                    Text(l10n.t(
                        "Version \(next) installs the next time you open the app.",
                        "版本 \(next) 会在下次打开时安装。"
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                }

                Button {
                    if let url = URL(string: "https://github.com/wolfqing") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("build by wolfqing")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .grokHover(cornerRadius: 7, selected: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text)
                .help("https://github.com/wolfqing")

                Text(l10n.t("Community client for Grok Build. Not an official xAI product.", "Grok Build 社区客户端，不是 xAI 官方应用。"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(width: 320)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.borderStrong))
            .shadow(color: .black.opacity(palette.isDark ? 0.52 : 0.18), radius: 26, y: 10)
        }
        .onExitCommand { model.showAbout = false }
    }
}
