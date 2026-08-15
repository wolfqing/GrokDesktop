import GrokDesktopCore
import SwiftUI

struct SkillsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

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

            if model.skillsTab == 0 {
                Text(l10n.personal)
                    .font(.system(size: 15, weight: .semibold))
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.filteredSkills) { skill in
                            Button {
                                model.runSkill(skill)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: skill.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(palette.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(skill.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(palette.text)
                                        Text(skill.detail)
                                            .font(.system(size: 13))
                                            .foregroundStyle(palette.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(palette.hairline, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
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
                if model.mcpServers.isEmpty {
                    Text(l10n.noConnectors)
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 20)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.mcpServers) { server in
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
                                .padding(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(palette.hairline, lineWidth: 1)
                                )
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
