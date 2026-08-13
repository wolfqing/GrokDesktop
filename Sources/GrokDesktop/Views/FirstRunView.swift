import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    let reason: FirstRunReason

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Grok Desktop")
                .font(.system(size: 32, weight: .medium, design: .serif))
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(GrokTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if reason == .missingCLI {
                Text("curl -fsSL https://x.ai/cli/install.sh | bash")
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
                    .background(GrokTheme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GrokTheme.canvas)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GrokTheme.text, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GrokSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(GrokTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GrokTheme.chip, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
