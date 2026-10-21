import GrokDesktopCore
import SwiftUI

struct SessionDeskSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("Permission", "权限"))
                .font(.system(size: 13, weight: .semibold))
            Text(l10n.t("Ask is the default. Full auto is optional and stays off until you choose it.", "默认是询问。全自动是可选项，不选就不会开。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            Picker("", selection: tierBinding) {
                Text(l10n.t("Ask", "询问")).tag(PermissionTier.ask)
                Text(l10n.t("Allow once", "仅此一次")).tag(PermissionTier.allowOnce)
                Text(l10n.t("Allow for session", "本次会话")).tag(PermissionTier.allowSession)
                Text(l10n.t("Deny", "拒绝")).tag(PermissionTier.deny)
                Text(l10n.t("Full auto (optional)", "全自动（可选）")).tag(PermissionTier.yolo)
            }
            .pickerStyle(.menu)
            HStack {
                Text(l10n.t("This folder", "当前目录"))
                Spacer()
                Picker("", selection: projectTierBinding) {
                    Text(l10n.t("Follow default", "跟随默认")).tag(PermissionTier.ask)
                    Text(l10n.t("Allow for session", "本次会话")).tag(PermissionTier.allowSession)
                    Text(l10n.t("Deny", "拒绝")).tag(PermissionTier.deny)
                }
                .pickerStyle(.menu)
            }
            Text(l10n.t("Session history", "会话记录"))
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: modeBinding) {
                Text(l10n.t("Shared with the CLI", "和命令行共用")).tag(SessionDataMode.shared)
                Text(l10n.t("Independent", "各自独立")).tag(SessionDataMode.independent)
            }
            .pickerStyle(.segmented)
            Text(l10n.t("Switching does not copy the other history.", "切换不会把另一边的记录拷过来。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            HStack {
                TextField(l10n.t("Reference session id", "参考会话 id"), text: $desk.referenceDraft)
                    .textFieldStyle(.roundedBorder)
                Button(l10n.t("Attach", "附上")) { model.attachReference() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            if !model.client.referenceSessionIDs.isEmpty {
                Text(model.client.referenceSessionIDs.joined(separator: "  "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            HStack {
                Button(desk.trustedPaths.contains(ProjectTrust.normalize(model.client.workingDirectory.path))
                       ? l10n.t("Trusted", "已信任")
                       : l10n.t("Trust this folder", "信任这个目录")) {
                    model.trustCurrentFolder()
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.t("Import CLI sessions", "导入命令行会话")) { model.importCLISessions() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            if !desk.lastFork.isEmpty {
                Text(desk.lastFork)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var tierBinding: Binding<PermissionTier> {
        Binding(
            get: { PermissionTier(rawValue: desk.permissionTier) ?? .ask },
            set: { desk.permissionTier = $0.rawValue }
        )
    }

    private var projectTierBinding: Binding<PermissionTier> {
        Binding(
            get: { desk.policy().effective(project: model.client.workingDirectory.path) },
            set: { desk.setProjectTier(model.client.workingDirectory.path, tier: $0) }
        )
    }

    private var modeBinding: Binding<SessionDataMode> {
        Binding(
            get: { SessionDataMode(rawValue: desk.sessionDataMode) ?? .shared },
            set: { model.setSessionDataMode($0) }
        )
    }
}

struct AccountDeskSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var keyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("API key", "API Key"))
                .font(.system(size: 13, weight: .semibold))
            SecureField(l10n.t("Stored in the keychain", "保存在钥匙串"), text: $keyDraft)
                .textFieldStyle(.roundedBorder)
            Button(l10n.t("Save to keychain", "存入钥匙串")) {
                model.saveAccountKey(keyDraft)
                keyDraft = ""
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            Text(l10n.t("The saved key is not shown again.", "存好的密钥不会再显示出来。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            HStack {
                TextField(l10n.t("Account label", "账号名称"), text: $desk.slotLabel)
                    .textFieldStyle(.roundedBorder)
                Button(l10n.t("Save login", "保存这个登录")) { model.saveAccountSlot() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            ForEach(desk.accountSlots) { slot in
                HStack {
                    Text(slot.label)
                    Spacer()
                    if desk.activeAccount == slot.id {
                        Text(l10n.t("Current", "当前"))
                            .foregroundStyle(palette.secondary)
                    }
                    Button(l10n.t("Use", "使用")) { model.activateAccount(slot) }
                        .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
        }
    }
}

struct UsageDeskSection: View {
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("Local usage", "本地用量"))
                .font(.system(size: 13, weight: .semibold))
            let cells = UsageHeatmap.cells(timestamps: UsageLedger.timestamps(), now: Date(), days: 12)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(cells, id: \.day) { cell in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(cell.count == 0 ? palette.chip : Color.orange.opacity(0.35 + 0.15 * Double(min(cell.count, 4))))
                        .frame(width: 14, height: 10 + CGFloat(min(cell.count, 6)) * 6)
                        .help("\(cell.day) \(cell.count)")
                }
            }
            Text(l10n.t("Counts turns sent from this app, including a custom relay.", "统计这个应用发出的回合，自定义中转也算。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        }
    }
}

struct ExtensionDeskSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.hookDefinitions.isEmpty {
                Text(l10n.t("Hook switches", "钩子开关"))
                    .font(.system(size: 13, weight: .semibold))
                ForEach(Array(model.hookDefinitions.prefix(8))) { hook in
                    Toggle(hook.title, isOn: Binding(
                        get: { ExtensionToggles.isEnabled(desk.extensionToggles, kind: "hook", name: hook.title) },
                        set: { enabled in
                            desk.extensionToggles = ExtensionToggles.set(desk.extensionToggles, kind: "hook", name: hook.title, enabled: enabled)
                        }
                    ))
                    .font(.system(size: 13))
                }
            }
        }
    }
}

struct AdvancedDeskSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            relayBlock
            bridgeBlock
            mirrorBlock
            remoteBlock
            proxyBlock
            doctorBlock
        }
    }

    private var relayBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("Custom relay", "自定义中转"))
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: $desk.relayPreset) {
                ForEach(RelayPreset.allCases, id: \.rawValue) { preset in
                    Text(preset.rawValue).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
            TextField("Base URL", text: $desk.relayBase)
                .textFieldStyle(.roundedBorder)
            TextField(l10n.t("Default model", "默认模型"), text: $desk.relayModel)
                .textFieldStyle(.roundedBorder)
            SecureField(l10n.t("Key", "密钥"), text: $desk.relayKey)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $desk.relayMode) {
                Text(l10n.t("Independent home", "独立目录")).tag(RelayHomeMode.independent.rawValue)
                Text(l10n.t("Shared home", "共用目录")).tag(RelayHomeMode.shared.rawValue)
            }
            .pickerStyle(.segmented)
            HStack {
                Button(l10n.t("Save relay", "保存中转")) { model.saveRelay() }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.t("Test", "测试")) { model.testRelay() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
            if !desk.relayNote.isEmpty {
                Text(desk.relayNote)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var bridgeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("Bridges", "桥接"))
                .font(.system(size: 13, weight: .semibold))
            Text(l10n.t("Inbound text starts a Build turn only for a trusted project. /p picks one, /r resumes one.", "进来的文字只会在已信任的项目里开一轮。/p 选项目，/r 继续已有会话。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            Picker("", selection: $desk.imChannel) {
                ForEach(IMChannel.allCases, id: \.rawValue) { channel in
                    Text(channel.rawValue).tag(channel)
                }
            }
            .pickerStyle(.menu)
            ForEach(desk.imChannel.requiredFields, id: \.self) { field in
                SecureField(field, text: fieldBinding(field))
                    .textFieldStyle(.roundedBorder)
            }
            Button(l10n.t("Save bridge", "保存桥接")) { model.saveBridge() }
                .buttonStyle(GrokSecondaryButtonStyle())
            ForEach(desk.bridges, id: \.channel) { bridge in
                Text("\(bridge.channel.rawValue) · \(bridge.isComplete ? l10n.t("ready", "已填好") : l10n.t("incomplete", "未填完"))")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var mirrorBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("Mobile mirror", "手机镜像"))
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: $desk.mirrorExposure) {
                Text(l10n.t("This Mac only", "仅本机")).tag(MirrorExposure.loopback.rawValue)
                Text(l10n.t("Same network", "同一局域网")).tag(MirrorExposure.lan.rawValue)
                Text(l10n.t("Quick tunnel", "临时隧道")).tag(MirrorExposure.tunnel.rawValue)
            }
            .pickerStyle(.menu)
            HStack {
                Button(desk.mirrorOn ? l10n.t("Stop", "停止") : l10n.t("Start", "启动")) { model.toggleMirror() }
                    .buttonStyle(GrokSecondaryButtonStyle())
                if desk.mirrorOn {
                    Text(":\(desk.mirrorPort)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
            }
            if !desk.maskedMirrorToken.isEmpty {
                Text(l10n.t("Token saved \(desk.maskedMirrorToken)", "令牌已保存 \(desk.maskedMirrorToken)"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                Button(l10n.t("Copy token", "复制令牌")) { model.copyMirrorToken() }
                    .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
    }

    private var remoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("SSH hosts", "SSH 主机"))
                .font(.system(size: 13, weight: .semibold))
            Button(l10n.t("Read SSH config", "读取 SSH 配置")) { model.refreshSSHHosts() }
                .buttonStyle(GrokSecondaryButtonStyle())
            ForEach(desk.sshHosts.prefix(8)) { host in
                Button(host.hostName.isEmpty ? host.alias : "\(host.alias) · \(host.hostName)") {
                    desk.sshAlias = host.alias
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.secondary)
            }
            TextField(l10n.t("SSH alias", "SSH 别名"), text: $desk.sshAlias)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(l10n.t("Test", "测试")) { model.testSSHHost() }
                Button(l10n.t("Watch", "保持")) { model.watchSSHHost() }
                Button(l10n.t("Remote agent", "远程 agent")) { model.openRemoteSession() }
                Button(l10n.t("Terminal", "终端")) { model.openRemoteTerminal() }
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            TextField(l10n.t("Remote relative path", "远程相对路径"), text: $desk.sshRelative)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(l10n.t("Read", "读取")) { model.readRemoteText() }
                Button(l10n.t("Skills", "技能")) { model.listRemoteSkills() }
                Button(l10n.t("Forward", "转发")) { model.forwardRemoteLoopback() }
            }
            .buttonStyle(GrokSecondaryButtonStyle())
            TextField(l10n.t("Text to write", "要写入的文本"), text: $desk.sshBody)
                .textFieldStyle(.roundedBorder)
            Button(l10n.t("Write remote file", "写入远程文件")) { model.writeRemoteText() }
                .buttonStyle(GrokSecondaryButtonStyle())
            if !desk.sshNote.isEmpty {
                Text(desk.sshNote)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(4)
            }
            TextField(l10n.t("PR numbers", "PR 编号"), text: $desk.prNumbers)
                .textFieldStyle(.roundedBorder)
            Button(l10n.t("Check pull requests", "检查 Pull Request")) { model.checkPullRequests() }
                .buttonStyle(GrokSecondaryButtonStyle())
            if !desk.prNote.isEmpty {
                Text(desk.prNote)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var proxyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("Proxy", "代理"))
                .font(.system(size: 13, weight: .semibold))
            TextField("http:// or socks5://", text: $desk.proxyURL)
                .textFieldStyle(.roundedBorder)
            Button(l10n.t("Use for agent", "用于 agent")) { model.applyProxy() }
                .buttonStyle(GrokSecondaryButtonStyle())
        }
    }

    private var doctorBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(l10n.t("Copy redacted report", "复制打码后的报告")) { model.copyDoctorReport() }
                .buttonStyle(GrokSecondaryButtonStyle())
            Button(l10n.t("Open log folder", "打开日志目录")) { model.openDoctorLogs() }
                .buttonStyle(GrokSecondaryButtonStyle())
            if !desk.doctorNote.isEmpty {
                Text(desk.doctorNote)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func fieldBinding(_ field: String) -> Binding<String> {
        Binding(
            get: { desk.imFields[field] ?? "" },
            set: { desk.imFields[field] = $0 }
        )
    }
}
