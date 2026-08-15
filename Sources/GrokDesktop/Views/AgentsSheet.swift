import AppKit
import GrokDesktopCore
import SwiftUI

struct AgentsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(width: 640, onDismiss: { model.showAgents = false }) {
            HStack {
                Text(model.agentsTab == 0 ? l10n.t("Agents", "Agents") : l10n.t("Personas", "人设"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("", selection: $model.agentsTab) {
                    Text(l10n.t("Agents", "Agents")).tag(0)
                    Text(l10n.t("Personas", "人设")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
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
            HStack {
                TextField(l10n.t("name", "名称"), text: $model.newAgentName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                TextField(l10n.t("what it does", "做什么"), text: $model.newAgentDetail)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
                Button(l10n.t("Add", "添加")) { model.createUserAgent() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.agentDefinitions) { agent in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(agent.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(2)
                                Text("\(agent.scope) · \(agent.permissionMode)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Button(l10n.t("Use", "使用")) {
                                model.showAgents = false
                                model.draft = "/agents \(agent.slug) "
                                model.destination = .build
                            }
                            .buttonStyle(GrokSecondaryButtonStyle())
                            if !agent.isBundled {
                                Button(role: .destructive) {
                                    model.deleteAgentDefinition(agent)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
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
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            TextField(l10n.t("short description", "一句话"), text: $model.newPersonaDetail)
                .textFieldStyle(.plain)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            TextField(l10n.t("instructions", "指令"), text: $model.newPersonaBody, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))
            Button(l10n.t("Save persona", "保存人设")) { model.createUserPersona() }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(model.newPersonaName.trimmingCharacters(in: .whitespaces).isEmpty)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.personaDefinitions) { persona in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(persona.detail.isEmpty ? persona.instructions : persona.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(3)
                                Text(persona.scope + (persona.model.isEmpty ? "" : " · \(persona.model)"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Button(l10n.t("Show in Finder", "在 Finder 中显示")) {
                                NSWorkspace.shared.activateFileViewerSelecting([persona.url])
                            }
                            .buttonStyle(GrokSecondaryButtonStyle())
                            if !persona.isBundled {
                                Button(role: .destructive) {
                                    model.deletePersona(persona)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(height: 240)
        }
    }
}
