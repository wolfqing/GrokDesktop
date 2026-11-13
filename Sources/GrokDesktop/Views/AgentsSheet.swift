import AppKit
import GrokDesktopCore
import SwiftUI

struct AgentsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 640, onDismiss: { model.showAgents = false }) {
            HStack(spacing: 12) {
                Text(model.agentsTab == 0 ? l10n.t("Agents", "Agents") : l10n.t("Personas", "人设"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("", selection: $model.agentsTab) {
                    Text(l10n.t("Agents", "Agents")).tag(0)
                    Text(l10n.t("Personas", "人设")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                GrokIconButton(
                    systemImage: "xmark",
                    size: 26,
                    iconSize: 11,
                    cornerRadius: 7,
                    helpText: "Esc"
                ) {
                    model.showAgents = false
                }
            }
            if model.agentsTab == 0 {
                agentsTab
            } else {
                personasTab
            }
        }
    }

    private var agentsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(l10n.t("name", "名称"), text: $model.newAgentName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .grokFieldChrome(cornerRadius: 9)
                TextField(l10n.t("what it does", "做什么"), text: $model.newAgentDetail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .grokFieldChrome(cornerRadius: 9)
                Button(l10n.t("Add", "添加")) { model.createUserAgent() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.agentDefinitions) { agent in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(agent.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(2)
                                Text("\(agent.scope) · \(agent.permissionMode)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.tertiary)
                            }
                            Spacer()
                            Button(l10n.t("Use", "使用")) {
                                model.showAgents = false
                                model.draft = "/agents \(agent.slug) "
                                model.destination = .build
                            }
                            .buttonStyle(GrokSecondaryButtonStyle())
                            if !agent.isBundled {
                                GrokIconButton(
                                    systemImage: "trash",
                                    size: 28,
                                    iconSize: 12,
                                    cornerRadius: 7,
                                    helpText: l10n.t("Delete", "删除")
                                ) {
                                    model.deleteAgentDefinition(agent)
                                }
                            }
                        }
                        .padding(12)
                        .grokCard(cornerRadius: 11, interactive: true)
                    }
                }
            }
            .frame(height: 320)
        }
    }

    private var personasTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(l10n.t("name", "名称"), text: $model.newPersonaName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .grokFieldChrome(cornerRadius: 9)
            TextField(l10n.t("short description", "一句话"), text: $model.newPersonaDetail)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .grokFieldChrome(cornerRadius: 9)
            TextField(l10n.t("instructions", "指令"), text: $model.newPersonaBody, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...5)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .grokFieldChrome(cornerRadius: 9)
            Button(l10n.t("Save persona", "保存人设")) { model.createUserPersona() }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(model.newPersonaName.trimmingCharacters(in: .whitespaces).isEmpty)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.personaDefinitions) { persona in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(persona.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(persona.detail.isEmpty ? persona.instructions : persona.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(3)
                                Text(persona.scope + (persona.model.isEmpty ? "" : " · \(persona.model)"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.tertiary)
                            }
                            Spacer()
                            Button(l10n.t("Show in Finder", "在 Finder 中显示")) {
                                NSWorkspace.shared.activateFileViewerSelecting([persona.url])
                            }
                            .buttonStyle(GrokSecondaryButtonStyle())
                            if !persona.isBundled {
                                GrokIconButton(
                                    systemImage: "trash",
                                    size: 28,
                                    iconSize: 12,
                                    cornerRadius: 7,
                                    helpText: l10n.t("Delete", "删除")
                                ) {
                                    model.deletePersona(persona)
                                }
                            }
                        }
                        .padding(12)
                        .grokCard(cornerRadius: 11, interactive: true)
                    }
                }
            }
            .frame(height: 240)
        }
    }
}
