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
            item(.session, l10n.t("Session", "会话"), "clock")
            groupLabel(l10n.grok).padding(.top, 14)
            item(.customize, l10n.customize, "slider.horizontal.2.square")
            item(.models, l10n.t("Models", "模型"), "cpu")
            item(.feedback, l10n.t("Feedback", "反馈"), "bubble.left")
            item(.extensions, l10n.t("Extensions", "扩展"), "puzzlepiece.extension")
            item(.agent, l10n.t("Agent", "Agent"), "cpu")
            groupLabel(l10n.payments).padding(.top, 14)
            item(.billing, l10n.billing, "creditcard")
            item(.usage, l10n.usage, "bolt")
            groupLabel(l10n.dataAndInformation).padding(.top, 14)
            item(.dataControls, l10n.dataControls, "doc.text")
            item(.advanced, l10n.t("Advanced", "高级"), "wrench.and.screwdriver")
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
        case .session: sessionPage
        case .customize: customizePage
        case .models: modelsPage
        case .feedback: feedbackPage
        case .billing: billingPage
        case .usage: usagePage
        case .dataControls: dataPage
        case .extensions: extensionsPage
        case .agent: agentPage
        case .advanced: advancedPage
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
            VStack(alignment: .leading, spacing: 8) {
                statusLine(
                    model.client.authPresence == .signedIn
                        ? l10n.buildSignedIn
                        : (model.client.authPresence == .apiKey ? l10n.buildAPIKey : l10n.buildSignedOut),
                    ok: model.client.authPresence.isReady
                )
                statusLine(model.webChatSignedIn ? l10n.chatSignedIn : l10n.chatSignedOut, ok: model.webChatSignedIn)
                if model.client.authPresence == .apiKey {
                    Text(l10n.apiKeyChatNote)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
            }
            Button(l10n.loginGrok) { model.login() }
                .buttonStyle(GrokPrimaryButtonStyle())
            Button(l10n.t("Sign out", "退出登录")) { model.logout() }
                .buttonStyle(GrokSecondaryButtonStyle())
        }
        .padding(.top, 8)
        .task { await model.refreshWebChatAuth() }
    }

    private func statusLine(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green.opacity(0.85) : palette.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(ok ? palette.text : palette.secondary)
        }
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
            toggle(l10n.t("Compact conversation", "紧凑对话"), isOn: $model.compactChat)
            toggle(l10n.t("Show timestamps on replies", "回复也显示时间戳"), isOn: $model.showTimestamps)
            toggle(
                l10n.t("Show thinking blocks", "显示思考块"),
                isOn: Binding(
                    get: { model.showThinkingBlocks },
                    set: { value in
                        model.showThinkingBlocks = value
                        try? model.configStore.set(section: "ui", key: "show_thinking_blocks", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                )
            )
            toggle(l10n.t("Merge tool rows", "合并工具行"), isOn: $model.mergeToolRows)
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
        VStack(alignment: .leading, spacing: 12) {
            toggle(l10n.enableAutoScroll, isOn: $model.autoScroll)
            toggle(l10n.notifyThinking, isOn: $model.notifyThinking)
            toggle(l10n.requireCmdEnter, subtitle: l10n.requireCmdEnterHelp, isOn: $model.requireCmdEnter)
            toggle(l10n.richTextEditor, subtitle: l10n.richTextHelp, isOn: $model.richTextEditor)
            HStack {
                Text(l10n.t("Default model", "默认模型"))
                Spacer()
                Menu(model.grokConfig.defaultModel) {
                    ForEach(BuildModel.allCases) { item in
                        Button(item.title) {
                            try? model.configStore.set(section: "models", key: "default", value: item.rawValue)
                            model.grokConfig = model.configStore.load()
                            model.client.apply(tier: .auto)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            HStack {
                Text(l10n.t("Permission mode", "权限模式"))
                Spacer()
                Menu(model.grokConfig.permissionMode) {
                    ForEach(["ask", "auto", "always-approve"], id: \.self) { mode in
                        Button(mode) {
                            try? model.configStore.set(section: "ui", key: "permission_mode", value: mode)
                            model.grokConfig = model.configStore.load()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            toggle(
                l10n.t("Remember tool approvals", "记住工具批准"),
                isOn: Binding(
                    get: { model.grokConfig.rememberApprovals },
                    set: { value in
                        try? model.configStore.set(section: "ui", key: "remember_tool_approvals", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                )
            )
        }
        .padding(.top, 8)
    }

    private var modelsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("Fast / Auto / Expert / Heavy map onto local models and effort.", "Fast / Auto / Expert / Heavy 映射到本机模型和 effort。"))
                .foregroundStyle(palette.secondary)
            tierRow("Fast", modelKey: "fast_model", effortKey: "fast_effort", model: model.grokConfig.fastModel, effort: model.grokConfig.fastEffort)
            HStack {
                Text("Auto")
                Spacer()
                Text("\(model.grokConfig.defaultModel) · \(model.grokConfig.defaultEffort)")
                    .foregroundStyle(palette.secondary)
            }
            tierRow("Expert", modelKey: "expert_model", effortKey: "expert_effort", model: model.grokConfig.expertModel, effort: model.grokConfig.expertEffort)
            tierRow("Heavy", modelKey: "heavy_model", effortKey: "heavy_effort", model: model.grokConfig.heavyModel, effort: model.grokConfig.heavyEffort)
        }
        .padding(.top, 8)
    }

    private func tierRow(_ title: String, modelKey: String, effortKey: String, model current: String, effort: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Menu(current) {
                ForEach(BuildModel.allCases) { item in
                    Button(item.title) {
                        try? self.model.configStore.set(section: "grok_desktop", key: modelKey, value: item.rawValue)
                        self.model.grokConfig = self.model.configStore.load()
                        self.model.client.apply(tier: self.model.client.modelTier)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            Menu(effort) {
                ForEach(EffortLevel.allCases) { level in
                    Button(level.rawValue) {
                        try? self.model.configStore.set(section: "grok_desktop", key: effortKey, value: level.rawValue)
                        self.model.grokConfig = self.model.configStore.load()
                        self.model.client.apply(tier: self.model.client.modelTier)
                    }
                }
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var feedbackPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("Send feedback through the local grok CLI.", "通过本机 grok CLI 发送反馈。"))
                .foregroundStyle(palette.secondary)
            Button("/feedback") {
                model.destination = .build
                model.draft = "/feedback "
                model.showSettings = false
            }
            .buttonStyle(GrokPrimaryButtonStyle())
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
                    model.destination = .build
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
                    Text(model.accountUsage.prepaidDisplay).font(.system(size: 24, weight: .semibold))
                    HStack {
                        Button(l10n.buyMore) { model.openAccountUsage() }
                            .buttonStyle(GrokSecondaryButtonStyle())
                        Button(l10n.viewUsage) {
                            model.settingsSection = .usage
                            model.refreshAccountUsage()
                        }
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
        .onAppear { model.refreshAccountUsage() }
    }

    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(l10n.usageForAccount)
                    .foregroundStyle(palette.secondary)
                Text(model.account.email ?? l10n.notSignedIn)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button(l10n.refreshUsage) { model.refreshAccountUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    .disabled(model.isRefreshingUsage)
            }
            Text(periodTitle).font(.system(size: 13)).foregroundStyle(palette.secondary)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(usageHeadline)
                        .font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text(l10n.grokBuildUsage)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Capsule().fill(palette.chip).frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: max(8, 240 * CGFloat(min(model.accountUsage.displayPercent, 100)) / 100), height: 8)
                    }
                if let reset = resetLabel {
                    Text("\(l10n.nextReset): \(reset)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                if let error = model.accountUsage.error, !model.accountUsage.isLoaded {
                    Text(error == "Not signed in" ? l10n.notSignedIn : l10n.usageUnavailable)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))

            if !model.accountUsage.products.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.accountUsage.products) { product in
                        HStack {
                            Text(product.name)
                            Spacer()
                            Text(product.percent.map { "\($0)% \(l10n.used)" } ?? "—")
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))
            }

            Text(l10n.extraCredits)
            HStack {
                VStack(alignment: .leading) {
                    Text(model.accountUsage.prepaidDisplay).font(.system(size: 18, weight: .semibold))
                    Text(model.account.plan.wordmark)
                        .foregroundStyle(palette.secondary)
                }
                Spacer()
                Button(l10n.buyMore) { model.openAccountUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))

            if model.accountUsage.hasPayAsYouGo {
                HStack {
                    Text(l10n.t("Pay as you go", "按量付费"))
                    Spacer()
                    Text(String(format: "US$%.2f / US$%.2f", model.accountUsage.onDemandUsed, model.accountUsage.onDemandCap))
                        .foregroundStyle(palette.secondary)
                }
                .font(.system(size: 13))
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.hairline))
            }

            HStack(spacing: 10) {
                Button(l10n.openGrokUsage) { model.openAccountUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.openAPIUsage) { model.openAPIUsage() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(.top, 8)
        .onAppear { model.refreshAccountUsage() }
    }

    private var periodTitle: String {
        switch model.accountUsage.periodKind {
        case .monthly: return l10n.monthlyPlanLimit
        case .weekly, .unknown: return l10n.weeklyPlanLimit
        }
    }

    private var usageHeadline: String {
        if model.accountUsage.isLoaded || model.accountUsage.fetchedAt != nil {
            return "\(model.accountUsage.displayPercent)% \(l10n.used)"
        }
        if model.isRefreshingUsage {
            return l10n.t("Loading…", "正在同步…")
        }
        return "— \(l10n.used)"
    }

    private var resetLabel: String? {
        guard let date = model.accountUsage.periodEnd else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t(
                "Training and retention follow your grok.com / `/privacy` choice. This app only talks to the local grok CLI.",
                "训练与留存遵循 grok.com / `/privacy` 的选择。本应用只连接本机 grok CLI。"
            ))
            .foregroundStyle(palette.secondary)
            HStack {
                Text("Grok Desktop 0.1.15")
                Spacer()
                Text(model.client.grokVersion ?? "grok ?")
                    .foregroundStyle(palette.secondary)
            }
            .font(.system(size: 13))
            Button("/privacy") {
                model.destination = .build
                model.draft = "/privacy"
                model.showSettings = false
                model.sendDraft()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
        .padding(.top, 8)
    }

    private var sessionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(l10n.t("Auto-compact threshold", "自动压缩阈值"))
                Spacer()
                Text("\(model.grokConfig.autoCompactPercent)%")
                    .foregroundStyle(palette.secondary)
            }
            Button(l10n.t("Remember this folder for new chats", "新会话记住当前目录")) {
                model.rememberWorkingDirectory(model.client.workingDirectory)
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            toggle(l10n.enableAutoScroll, isOn: $model.autoScroll)
            Button(l10n.t("Write auto_compact_threshold_percent = 85", "写入自动压缩 85%")) {
                try? model.configStore.set(section: "session", key: "auto_compact_threshold_percent", int: 85)
                model.grokConfig = model.configStore.load()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
        .padding(.top, 8)
    }

    private var extensionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MCP")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(l10n.t("Add MCP", "添加 MCP")) { model.showAddMCP = true }
                    .buttonStyle(GrokPrimaryButtonStyle())
            }
            Text(l10n.t("Adds and removes servers with `grok mcp`, writing ~/.grok/config.toml.", "通过 `grok mcp` 增删，写入 ~/.grok/config.toml。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            if model.mcpServers.isEmpty {
                Text(l10n.noConnectors)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(model.mcpServers) { server in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name).font(.system(size: 14, weight: .medium))
                            Text(server.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.enabled },
                            set: { _ in model.toggleMCPServer(server) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        Button(role: .destructive) {
                            model.removeMCPServer(server)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }
            labeledList("Skills", model.skills.prefix(8).map(\.title))
            labeledList("Plugins", model.extensions.plugins.isEmpty ? [l10n.t("None installed", "未安装")] : model.extensions.plugins)
            labeledList("Hooks", model.extensions.hooks.isEmpty ? [l10n.t("None", "无")] : model.extensions.hooks)
            HStack {
                Button(l10n.t("MCP doctor", "MCP 诊断")) {
                    model.showSettings = false
                    model.handleCommand("/mcps doctor")
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.t("List plugins", "列出插件")) {
                    model.showSettings = false
                    model.handleCommand("/plugins list")
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
            Button(l10n.t("Open config.toml", "打开 config.toml")) {
                model.configStore.openInEditor()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
        }
        .padding(.top, 8)
        .onAppear {
            model.mcpServers = model.mcpCatalog.load(locator: model.locator, cwd: model.client.workingDirectory)
        }
    }

    private func labeledList(_ title: String, _ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var agentPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l10n.t("Sandbox", "沙箱"))
                Spacer()
                Menu(model.grokConfig.sandboxProfile) {
                    ForEach(["off", "workspace", "read-only", "strict"], id: \.self) { profile in
                        Button(profile) {
                            try? model.configStore.set(section: "sandbox", key: "profile", value: profile)
                            model.grokConfig = model.configStore.load()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            toggle(
                l10n.t("Memory", "记忆"),
                isOn: Binding(
                    get: { model.grokConfig.memoryEnabled },
                    set: { value in
                        try? model.configStore.set(section: "memory", key: "enabled", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                )
            )
            toggle(
                l10n.t("Codebase indexing", "代码索引"),
                isOn: Binding(
                    get: { model.grokConfig.codebaseIndexing },
                    set: { value in
                        try? model.configStore.set(section: "features", key: "codebase_indexing", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                )
            )
            toggle(
                l10n.t("Respect gitignore", "遵守 gitignore"),
                isOn: Binding(
                    get: { model.grokConfig.respectGitignore },
                    set: { value in
                        try? model.configStore.set(section: "tools", key: "respect_gitignore", bool: value)
                        model.grokConfig = model.configStore.load()
                    }
                )
            )
        }
        .padding(.top, 8)
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("App")
                Spacer()
                Text("0.1.15")
            }
            HStack {
                Text("grok")
                Spacer()
                Text(model.client.grokVersion ?? l10n.t("not found", "未找到"))
            }
            if let error = model.client.lastError {
                Text(error).foregroundStyle(.red)
            }
            if !model.client.events.isEmpty {
                Text(l10n.t("ACP events", "ACP 事件"))
                    .font(.system(size: 12, weight: .medium))
                Text(model.client.events.suffix(16).map(\.line).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.client.stderrLines.isEmpty {
                Text(model.client.stderrLines.suffix(12).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
            }
            Button(l10n.t("Open config.toml", "打开 config.toml")) {
                model.configStore.openInEditor()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button("/doctor") {
                model.showSettings = false
                model.handleCommand("/doctor")
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button("/inspect") {
                model.showSettings = false
                model.handleCommand("/inspect")
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button("/import-claude") {
                model.showSettings = false
                model.handleCommand("/import-claude")
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button(l10n.t("Check CLI updates", "检查 CLI 更新")) {
                model.showSettings = false
                model.handleCommand("/update")
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button(l10n.t("Export diagnostic", "导出诊断包")) {
                model.exportDiagnostics()
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Button("Docs") { model.openDocs() }
                .buttonStyle(GrokSecondaryButtonStyle())
            Button("CHANGELOG") { model.openChangelog() }
                .buttonStyle(GrokSecondaryButtonStyle())
            if !model.client.capabilities.methods.isEmpty {
                Text(model.client.capabilities.methods.joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
        }
        .font(.system(size: 13))
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
        case .session: return l10n.t("Session", "会话")
        case .customize: return l10n.customize
        case .models: return l10n.t("Models", "模型")
        case .feedback: return l10n.t("Feedback", "反馈")
        case .billing: return l10n.billing
        case .usage: return l10n.usage
        case .dataControls: return l10n.dataControls
        case .extensions: return l10n.t("Extensions", "扩展")
        case .agent: return l10n.t("Agent", "Agent")
        case .advanced: return l10n.t("Advanced", "高级")
        }
    }
}
