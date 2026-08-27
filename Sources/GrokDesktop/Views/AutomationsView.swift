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
                        "Runs are live workflow jobs. Saved scripts live in ~/.grok/workflows and the project .grok/workflows folder.",
                        "运行是正在进行的工作流。已保存脚本在 ~/.grok/workflows 和项目 .grok/workflows。"
                    )
                ) {
                    Button(l10n.t("New workflow", "新建工作流")) {
                        model.automationsTab = 1
                        model.showAddWorkflow = true
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())
                }

                Picker("", selection: $model.automationsTab) {
                    Text(l10n.t("Runs", "运行")).tag(0)
                    Text(l10n.t("Saved", "已保存")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                if model.automationsTab == 0 {
                    runsSection
                } else if model.officialWorkflows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t("No saved workflows yet.", "还没有已保存的工作流。"))
                            .foregroundStyle(palette.secondary)
                        Text(l10n.t(
                            "Put a .rhai script in ~/.grok/workflows or the project .grok/workflows folder, or create one here.",
                            "把 .rhai 脚本放到 ~/.grok/workflows 或项目 .grok/workflows，也可以在这里新建。"
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        Button(l10n.t("New workflow", "新建工作流")) { model.showAddWorkflow = true }
                            .buttonStyle(GrokPrimaryButtonStyle())
                    }
                    .padding(.top, 8)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.officialWorkflows) { item in
                            workflowCard(item)
                        }
                    }
                }

                if model.automationsTab == 1, !model.automations.isEmpty {
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
            model.refreshWorkflowRuns()
        }
    }

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.workflowRuns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.t("No workflow runs yet.", "还没有运行。"))
                        .foregroundStyle(palette.secondary)
                    Button(l10n.t("Open saved workflows", "打开已保存")) {
                        model.automationsTab = 1
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                }
            } else {
                ForEach(model.workflowRuns) { run in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text(run.status)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                            Text(PromptTimestamp.format(run.startedAt))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        if run.status == "running" {
                            Button(l10n.t("Pause", "暂停")) { model.controlWorkflow(name: run.name, verb: "pause") }
                                .buttonStyle(GrokSecondaryButtonStyle())
                            Button(l10n.t("Stop", "停止")) { model.controlWorkflow(name: run.name, verb: "stop") }
                                .buttonStyle(GrokSecondaryButtonStyle())
                        } else if run.status == "paused" {
                            Button(l10n.t("Resume", "继续")) { model.controlWorkflow(name: run.name, verb: "resume") }
                                .buttonStyle(GrokSecondaryButtonStyle())
                            Button(l10n.t("Stop", "停止")) { model.controlWorkflow(name: run.name, verb: "stop") }
                                .buttonStyle(GrokSecondaryButtonStyle())
                        }
                    }
                    .padding(16)
                    .background(palette.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
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
