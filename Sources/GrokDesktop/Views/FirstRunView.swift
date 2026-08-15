import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let reason: FirstRunReason

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            SuperGrokWordmark(markSize: 40, title: model.account.plan.wordmark)
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

            if reason == .unsigned {
                if let challenge = model.client.authChallenge {
                    if let url = challenge.url {
                        Text(url.absoluteString)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    if let code = challenge.userCode {
                        Text(code)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    }
                }
                TextField(l10n.t("One-time code", "一次性代码"), text: $model.loginCode)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(maxWidth: 280)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                Button(l10n.t("Submit code", "提交代码")) { model.submitLoginCode() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }

            HStack(spacing: 10) {
                if reason == .missingCLI {
                    Button(l10n.t("Install CLI", "安装 CLI")) { model.installCLI() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                    Button(l10n.t("Recheck", "重新检测")) { model.retryLocate() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                } else {
                    Button(l10n.loginGrok) { model.login() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                    Button(l10n.t("Recheck", "重新检测")) { model.retryLocate() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
                if reason != .unsigned {
                    Button(l10n.loginGrok) { model.login() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
                Button(l10n.t("Docs", "文档")) { model.openDocs() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            Spacer()
        }
        .padding(24)
    }

    private var message: String {
        switch reason {
        case .missingCLI:
            return l10n.t(
                "The grok CLI was not found. Install official Grok Build, sign in, then reopen this app.",
                "本机没有找到 grok CLI。先安装官方 Grok Build，登录后再打开这个应用。"
            )
        case .unsigned:
            return l10n.t(
                "No grok.com session or XAI_API_KEY. Sign in with grok login, or use the ACP login URL.",
                "没有 grok.com 登录态，也没有 XAI_API_KEY。用 grok login，或走 ACP 登录链接。"
            )
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PageHeader<Action: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: () -> Action

    init(title: String, subtitle: String? = nil, @ViewBuilder action: @escaping () -> Action) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Spacer(minLength: 12)
                action()
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension PageHeader where Action == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
