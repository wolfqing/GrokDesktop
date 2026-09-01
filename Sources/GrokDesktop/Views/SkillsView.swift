import GrokDesktopCore
import SwiftUI

struct SkillsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.skillsAndConnectors)
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Menu {
                    Button(l10n.newSkill) {
                        model.destination = .build
                        model.draft = "/create-skill "
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l10n.newSkill)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.sendGlyph)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.send, in: Capsule())
                }
                .menuStyle(.borderlessButton)
            }

            HStack {
                HStack(spacing: 0) {
                    tab(l10n.skills, index: 0)
                    tab(l10n.connectors, index: 1)
                    tab(l10n.t("Plugins", "插件"), index: 2)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.secondary)
                    TextField(l10n.searchEllipsis, text: $model.skillsQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 220)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.hairline))
            }

            if model.skillsTab == 2 {
                pluginsPane
            } else if model.skillsTab == 0 {
                if model.filteredSkills.isEmpty {
                    if model.catalogsLoading {
                        ProgressView()
                            .padding(.top, 24)
                    } else {
                        Text(l10n.t("No skills match.", "没有匹配的技能。"))
                            .foregroundStyle(palette.secondary)
                            .padding(.top, 20)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(model.skillGroups, id: \.id) { group in
                                Text("\(group.title) · \(group.items.count)")
                                    .font(.system(size: 15, weight: .semibold))
                                ForEach(Array(stride(from: 0, to: group.items.count, by: 2)), id: \.self) { index in
                                    HStack(alignment: .top, spacing: 14) {
                                        skillCard(group.items[index])
                                        if index + 1 < group.items.count {
                                            skillCard(group.items[index + 1])
                                        } else {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                HStack {
                    Text(l10n.t("MCP servers", "MCP 服务器"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(l10n.t("Doctor", "诊断")) {
                        model.handleCommand("/mcps doctor")
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    Button(l10n.t("Add MCP", "添加 MCP")) { model.showAddMCP = true }
                        .buttonStyle(GrokPrimaryButtonStyle())
                }
                if model.filteredMCPServers.isEmpty {
                    Text(model.mcpServers.isEmpty ? l10n.noConnectors : l10n.t("No connectors match.", "没有匹配的连接器。"))
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 20)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.filteredMCPServers) { server in
                                connectorRow(server)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .padding(36)
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.canvas)
        .onAppear { model.refreshCatalogs() }
    }

    private func skillCard(_ skill: SkillRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                model.runSkill(skill)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: skill.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(skill.enabled ? palette.secondary : palette.hairline)
                        .frame(width: 28, height: 28)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(skill.enabled ? palette.text : palette.secondary)
                        Text(skill.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(skill.invocation)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help(skill.invocation)
            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { _ in model.toggleSkill(skill) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(l10n.t("Include this skill in the agent", "让 agent 能用这个技能"))
        }
        .padding(16)
        .opacity(skill.enabled ? 1 : 0.55)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private var pluginsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    TextField(l10n.t("owner/repo or git URL", "owner/repo 或 git 地址"), text: $model.pluginSource)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                    Button(l10n.t("Install", "安装")) { model.installPluginSource() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                        .disabled(model.pluginSource.trimmingCharacters(in: .whitespaces).isEmpty || model.pluginBusy)
                    Button(l10n.t("Add source", "添加市场")) { model.addMarketplaceSource() }
                        .buttonStyle(GrokSecondaryButtonStyle())
                        .disabled(model.pluginSource.trimmingCharacters(in: .whitespaces).isEmpty || model.pluginBusy)
                }
                if !model.marketplaces.isEmpty {
                    Text(model.marketplaces.map(\.name).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                pluginGroup(l10n.t("Installed", "已安装"), model.installedPlugins, available: false)
                pluginGroup(l10n.t("Marketplace", "市场"), model.availablePlugins, available: true)
            }
            .padding(.bottom, 24)
        }
    }

    private func pluginGroup(_ title: String, _ items: [PluginRecord], available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) · \(items.count)")
                .font(.system(size: 15, weight: .semibold))
            if items.isEmpty {
                Text(available
                     ? l10n.t("No marketplace plugins match.", "没有匹配的市场插件。")
                     : l10n.t("No plugins installed yet.", "还没有安装插件。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(items.prefix(available ? 80 : 200)) { plugin in
                    pluginRow(plugin, available: available)
                }
            }
        }
    }

    private func pluginRow(_ plugin: PluginRecord, available: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name)
                    .font(.system(size: 14, weight: .semibold))
                if !plugin.detail.isEmpty {
                    Text(plugin.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
                Text([plugin.marketplace, plugin.providesLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if available {
                Button(l10n.t("Trust & install", "信任并安装")) {
                    model.confirmInstall(plugin)
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(model.pluginBusy)
            } else {
                Toggle("", isOn: Binding(
                    get: { plugin.enabled },
                    set: { _ in model.togglePlugin(plugin) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(model.pluginBusy)
                Button(role: .destructive) {
                    model.uninstallPlugin(plugin)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(model.pluginBusy)
            }
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .opacity(plugin.enabled || available ? 1 : 0.55)
    }

    private func connectorRow(_ server: MCPServerRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "server.rack")
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 28)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(server.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if server.managed {
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
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button(title) {
            model.skillsTab = index
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(model.skillsTab == index ? palette.selected : Color.clear, in: Capsule())
        .overlay(Capsule().stroke(model.skillsTab == index ? palette.hairline : Color.clear))
    }
}
