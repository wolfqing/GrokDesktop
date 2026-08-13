import GrokDesktopCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showSettings = false }

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 220)
                    .background(palette.sidebar)
                Rectangle().fill(palette.hairline).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(title(for: model.settingsSection))
                            .font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Button {
                            model.showSettings = false
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(palette.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                    ScrollView {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                }
                .background(palette.elevated)
            }
            .frame(width: 860, height: 580)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.hairline))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel(l10n.general)
            item(.account, l10n.account, "person")
            item(.appearance, l10n.appearance, "pencil")
            item(.behavior, l10n.behavior, "slider.horizontal.3")
            groupLabel(l10n.grok).padding(.top, 14)
            item(.customize, l10n.customize, "slider.horizontal.2.square")
            groupLabel(l10n.payments).padding(.top, 14)
            item(.billing, l10n.billing, "creditcard")
            item(.usage, l10n.usage, "bolt")
            groupLabel(l10n.dataAndInformation).padding(.top, 14)
            item(.dataControls, l10n.dataControls, "doc.text")
            Spacer()
        }
        .padding(16)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func item(_ section: SettingsSection, _ title: String, _ icon: String) -> some View {
        Button {
            model.settingsSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13.5))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(model.settingsSection == section ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch model.settingsSection {
        case .account: accountPage
        case .appearance: appearancePage
        case .behavior: behaviorPage
        case .customize: customizePage
        case .billing: billingPage
        case .usage: usagePage
        case .dataControls: dataPage
        }
    }

    private var accountPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            row {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.purple)
                        Text(accountInitial)
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountName)
                            .font(.system(size: 15, weight: .medium))
                        if let email = model.account.email {
                            Text(email).font(.system(size: 13)).foregroundStyle(palette.secondary)
                        }
                    }
                    Spacer()
                    Button(l10n.manage) { model.login() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            Divider().overlay(palette.hairline)
            row {
                HStack {
                    GrokMark(size: 18)
                    Text(model.account.plan.wordmark)
                    Spacer()
                    Button(l10n.manage) { model.settingsSection = .billing }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            row {
                HStack {
                    Text(l10n.languageTitle)
                    Spacer()
                    Text(languageLabel)
                        .foregroundStyle(palette.secondary)
                    Button(l10n.change) { model.showLanguagePicker.toggle() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
            if model.showLanguagePicker {
                VStack(spacing: 6) {
                    languageOption(.system, l10n.systemLanguage)
                    languageOption(.english, l10n.english)
                    languageOption(.chinese, l10n.chinese)
                }
            }
            Button(l10n.loginGrok) { model.login() }
                .buttonStyle(GrokPrimaryButtonStyle())
        }
        .padding(.top, 8)
    }

    private var accountName: String {
        model.account.displayName.isEmpty ? l10n.notSignedIn : model.account.displayName
    }

    private var accountInitial: String {
        model.account.initial.isEmpty ? "G" : model.account.initial
    }

    private var languageLabel: String {
        switch model.language {
        case .system: return l10n.systemLanguage
        case .english: return l10n.english
        case .chinese: return l10n.chinese
        }
    }

    private func languageOption(_ value: AppLanguage, _ title: String) -> some View {
        Button {
            model.language = value
            model.showLanguagePicker = false
        } label: {
            HStack {
                Text(title)
                Spacer()
                if model.language == value {
                    Image(systemName: "checkmark")
                }
            }
            .padding(10)
            .background(model.language == value ? palette.selected : palette.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text(l10n.theme)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                HStack(spacing: 12) {
                    themeCard(.light, l10n.light)
                    themeCard(.dark, l10n.dark)
                    themeCard(.system, l10n.system)
                }
            }
            toggle(l10n.wrapCode, isOn: $model.wrapCodeLines)
        }
        .padding(.top, 8)
    }

    private func themeCard(_ value: AppearancePreference, _ title: String) -> some View {
        Button {
            model.appearance = value
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(previewFill(value))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(model.appearance == value ? palette.text : palette.hairline, lineWidth: model.appearance == value ? 2 : 1)
                    )
                    .frame(width: 88, height: 62)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func previewFill(_ value: AppearancePreference) -> Color {
        switch value {
        case .light: return Color.white
        case .dark: return Color.black
        case .system: return Color(white: 0.25)
        }
    }

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle(l10n.enableAutoScroll, isOn: $model.autoScroll)
            toggle(l10n.notifyThinking, isOn: $model.notifyThinking)
            Divider().padding(.vertical, 10).overlay(palette.hairline)
            toggle(l10n.requireCmdEnter, subtitle: l10n.requireCmdEnterHelp, isOn: $model.requireCmdEnter)
            toggle(l10n.richTextEditor, subtitle: l10n.richTextHelp, isOn: $model.richTextEditor)
        }
        .padding(.top, 8)
    }

    private var customizePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(l10n.customizeResponse)
                .font(.system(size: 15, weight: .medium))
            HStack(spacing: 8) {
                ForEach(ResponseStyle.allCases) { style in
                    Button(styleTitle(style)) {
                        model.responseStyle = style
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(Capsule().stroke(palette.hairline))
                    .background(model.responseStyle == style ? palette.selected : Color.clear, in: Capsule())
                }
            }
            HStack {
                Text(l10n.agentLibrary)
                Spacer()
                Button(l10n.createAgent) {
                    model.destination = .chat
                    model.draft = "/config-agents "
                    model.showSettings = false
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(.top, 8)
    }

    private func styleTitle(_ style: ResponseStyle) -> String {
        switch style {
        case .custom: return l10n.custom
        case .concise: return l10n.concise
        case .formal: return l10n.formal
        case .tutor: return l10n.tutor
        case .comprehensive: return l10n.comprehensive
        }
    }

    private var billingPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.currentPlan).font(.system(size: 12)).foregroundStyle(palette.secondary)
                    HStack { GrokMark(size: 18); Text(model.account.plan.wordmark).font(.system(size: 18, weight: .semibold)) }
                    Menu {
                        ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                            Button(plan.wordmark) { model.account.plan = plan }
                        }
                    } label: {
                        Text(l10n.switchPlan)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(palette.chip, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))

                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.extraCredits).font(.system(size: 12)).foregroundStyle(palette.secondary)
                    Text("US$0.00").font(.system(size: 24, weight: .semibold))
                    HStack {
                        Button(l10n.buyMore) { model.openAccountUsage() }
                            .buttonStyle(GrokSecondaryButtonStyle())
                        Button(l10n.viewUsage) { model.settingsSection = .usage }
                            .buttonStyle(GrokSecondaryButtonStyle())
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))
            }
            Text(l10n.invoices).font(.system(size: 14, weight: .semibold))
            Text(l10n.t("Billing stays on grok.com / `/usage`.", "账单仍在 grok.com 或 `/usage` 中管理。"))
                .foregroundStyle(palette.secondary)
        }
        .padding(.top, 8)
    }

    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(l10n.usageForAccount)
                    .foregroundStyle(palette.secondary)
                Text(model.account.email ?? l10n.notSignedIn)
                    .font(.system(size: 14, weight: .medium))
            }
            Text(l10n.weeklyPlanLimit).font(.system(size: 13)).foregroundStyle(palette.secondary)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(model.workspace.contextPercent)% \(l10n.used)")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text(l10n.t("This session context", "当前会话上下文"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Capsule().fill(palette.chip).frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: max(8, 240 * CGFloat(min(model.workspace.contextPercent, 100)) / 100), height: 8)
                    }
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))

            HStack(spacing: 10) {
                Button(l10n.openGrokUsage) { model.openAccountUsage() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                Button(l10n.openAPIUsage) { model.openAPIUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }

            Text(l10n.extraCredits)
            HStack {
                VStack(alignment: .leading) {
                    Text(model.account.plan.wordmark).font(.system(size: 18, weight: .semibold))
                    Text(model.account.email ?? l10n.notSignedIn)
                        .foregroundStyle(palette.secondary)
                }
                Spacer()
                Button(l10n.buyMore) { model.openAccountUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))
        }
        .padding(.top, 8)
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t(
                "Training and retention follow your grok.com / `/privacy` choice. This app only talks to the local grok CLI.",
                "训练与留存遵循 grok.com / `/privacy` 的选择。本应用只连接本机 grok CLI。"
            ))
            .foregroundStyle(palette.secondary)
            Button("/privacy") {
                model.destination = .chat
                model.draft = "/privacy"
                model.showSettings = false
                model.sendDraft()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
        .padding(.top, 8)
    }

    private func toggle(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 10)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
    }

    private func title(for section: SettingsSection) -> String {
        switch section {
        case .account: return l10n.account
        case .appearance: return l10n.appearance
        case .behavior: return l10n.behavior
        case .customize: return l10n.customize
        case .billing: return l10n.billing
        case .usage: return l10n.usage
        case .dataControls: return l10n.dataControls
        }
    }
}
