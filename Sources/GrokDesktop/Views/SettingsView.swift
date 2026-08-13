import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.showSettings = false }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.bottom, 8)
                    ForEach(SettingsSection.allCases) { section in
                        Button(section.title) {
                            model.settingsSection = section
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(model.settingsSection == section ? GrokTheme.text : GrokTheme.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            model.settingsSection == section ? GrokTheme.chip : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    Spacer()
                    Button("完成") { model.showSettings = false }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
                .padding(16)
                .frame(width: 180)
                .background(GrokTheme.sidebar)

                Rectangle().fill(GrokTheme.hairline).frame(width: 1)

                ScrollView {
                    settingsBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .background(GrokTheme.elevated)
            }
            .frame(width: 760, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(GrokTheme.hairline, lineWidth: 1)
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
                labeled("主题", "跟随系统 / 浅色 / 深色（与 grok.com 设置菜单一致）")
                labeled("紧凑显示", "对应 /compact-mode")
                labeled("思考块", "config.toml [ui] show_thinking_blocks")
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
                        .foregroundStyle(GrokTheme.secondary)
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
                .foregroundStyle(GrokTheme.secondary)
        }
        .padding(.vertical, 4)
    }
}
