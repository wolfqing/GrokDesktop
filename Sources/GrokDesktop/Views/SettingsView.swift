import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.overlay
                .ignoresSafeArea()
                .onTapGesture { model.showSettings = false }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        GrokMark(size: 18)
                        Text("设置")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding(.bottom, 8)
                    ForEach(SettingsSection.allCases) { section in
                        Button(section.title) {
                            model.settingsSection = section
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(model.settingsSection == section ? palette.text : palette.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            model.settingsSection == section ? palette.selected : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    Spacer()
                    Button("完成") { model.showSettings = false }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
                .padding(16)
                .frame(width: 180)
                .background(palette.sidebar)

                Rectangle().fill(palette.hairline).frame(width: 1)

                ScrollView {
                    settingsBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .background(palette.elevated)
            }
            .frame(width: 760, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.settingsSection.title)
                .font(.system(size: 22, weight: .semibold))

            switch model.settingsSection {
            case .appearance:
                Text("外观")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                VStack(spacing: 6) {
                    ForEach(AppearancePreference.allCases) { option in
                        Button {
                            model.appearance = option
                        } label: {
                            HStack {
                                Image(systemName: model.appearance == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.appearance == option ? palette.text : palette.secondary)
                                Text(option.title)
                                Spacer()
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(palette.text)
                            .padding(12)
                            .background(
                                model.appearance == option ? palette.selected : palette.chip,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .language:
                labeled("界面语言", "中文 / English")
            case .feedback:
                labeled("反馈", "对应 /feedback，发到 Grok 反馈通道")
            case .account:
                labeled("登录", "复用 ~/.grok/auth.json")
                Button("运行 grok login") { model.login() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                labeled("用量 / 隐私", "/usage 与 /privacy")
            case .behavior:
                labeled("默认模型", "config.toml [models].default")
                labeled("四档映射", "Fast / Auto / Expert / Heavy")
                labeled("权限模式", "Normal / Plan / Always-approve / Auto")
            case .session:
                labeled("自动压缩", "[session] auto_compact_threshold_percent")
                labeled("发送后滚到顶", "[ui] page_flip_on_send")
            case .agent:
                labeled("Sandbox", "grok --sandbox")
                labeled("Memory", "GROK_MEMORY / /memory")
                labeled("索引", "[features] codebase_indexing")
            case .extensions:
                labeled("MCP / Skills / Plugins / Hooks", "与 TUI 扩展模态同一份配置")
            case .advanced:
                labeled("配置文件", "~/.grok/config.toml")
                labeled("Doctor", "/doctor")
                if let grok = model.locator.locate() {
                    Text(grok.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.system(size: 14))
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
        }
        .padding(.vertical, 4)
    }
}
