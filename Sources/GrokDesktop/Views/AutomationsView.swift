import AppKit
import GrokDesktopCore
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: l10n.automations,
                    subtitle: l10n.t(
                        "Official Grok Build workflows are `.rhai` scripts in ~/.grok/workflows and the project `.grok/workflows` folder. Run one with /workflow <name>.",
                        "官方工作流是 ~/.grok/workflows 和项目 .grok/workflows 里的 .rhai 脚本。用 /workflow <name> 运行。"
                    )
                ) {
                    Button(l10n.t("New workflow", "新建工作流")) { model.showAddWorkflow = true }
                        .buttonStyle(GrokPrimaryButtonStyle())
                }

                if model.officialWorkflows.isEmpty {
                    Text(l10n.t("No saved workflows yet.", "还没有已保存的工作流。"))
                        .foregroundStyle(palette.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.officialWorkflows) { item in
                            workflowCard(item)
                        }
                    }
                }

                if !model.automations.isEmpty {
                    Text(l10n.t("Local shortcuts", "本地快捷项"))
                        .font(.system(size: 16, weight: .semibold))
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.automations) { item in
                            automationCard(item, suggested: false)
                        }
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvas)
        .onAppear {
            model.officialWorkflows = model.workflowCatalog.load(cwd: model.client.workingDirectory)
        }
    }

    private func workflowCard(_ item: WorkflowRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: Circle())
                Spacer()
                Menu {
                    Button(l10n.t("Run", "运行")) { model.runWorkflow(item) }
                    Button(l10n.t("Show in Finder", "在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Button(l10n.t("Delete", "删除"), role: .destructive) { model.deleteWorkflow(item) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(palette.secondary)
                }
                .menuStyle(.borderlessButton)
            }
            Text(item.name)
                .font(.system(size: 15, weight: .semibold))
            Text(item.detail.isEmpty ? item.scope : item.detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
            Text(item.scope)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { model.runWorkflow(item) }
    }

    private func automationCard(_ item: AutomationRecord, suggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: Circle())
                Spacer()
            }
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
            Text(item.detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { model.runAutomation(item) }
    }
}
