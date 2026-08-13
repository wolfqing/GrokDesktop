import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let reason: FirstRunReason

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            SuperGrokWordmark(markSize: 40)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if reason == .missingCLI {
                Text("curl -fsSL https://x.ai/cli/install.sh | bash")
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("重新检测") { model.retryLocate() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                Button("登录 grok") { model.login() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            Spacer()
        }
        .padding(24)
    }

    private var message: String {
        switch reason {
        case .missingCLI:
            return "本机没有找到 grok CLI。先安装官方 Grok Build，登录后再打开这个应用。"
        case .agent(let detail):
            return detail
        }
    }
}

struct GrokPrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.sendGlyph)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.send, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GrokSecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.chip, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
