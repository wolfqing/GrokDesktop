import AppKit
import GrokDesktopCore
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                .frame(width: 200)

                if model.automationsTab == 0 {
                    runsSection
                } else if model.officialWorkflows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t("No saved workflows yet.", "还没有已保存的工作流。"))
                            .font(.system(size: 14, weight: .medium))
                        Text(l10n.t(
                            "Put a .rhai script in ~/.grok/workflows or the project .grok/workflows folder, or create one here.",
                            "把 .rhai 脚本放到 ~/.grok/workflows 或项目 .grok/workflows，也可以在这里新建。"
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        Button(l10n.t("New workflow", "新建工作流")) { model.showAddWorkflow = true }
                            .buttonStyle(GrokPrimaryButtonStyle())
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grokCard(cornerRadius: 14)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.officialWorkflows) { item in
                            workflowCard(item)
                        }
                    }
                }

                if model.automationsTab == 1, !model.automations.isEmpty {
                    Text(l10n.t("Local shortcuts", "本地快捷项"))
                        .font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.automations) { item in
                            automationCard(item)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        .font(.system(size: 14, weight: .medium))
                    Button(l10n.t("Open saved workflows", "打开已保存")) {
                        model.automationsTab = 1
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .grokCard(cornerRadius: 14)
            } else {
                ForEach(model.workflowRuns) { run in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.name)
                                .font(.system(size: 14.5, weight: .semibold))
                            Text(run.status)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                            Text(PromptTimestamp.format(run.startedAt))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.tertiary)
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
                    .grokCard(cornerRadius: 14)
                }
            }
        }
    }

    private func workflowCard(_ item: WorkflowRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Menu {
                    Button(l10n.t("Run", "运行")) { model.runWorkflow(item) }
                    Button(l10n.t("Show in Finder", "在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Divider()
                    Button(l10n.t("Delete", "删除"), role: .destructive) { model.deleteWorkflow(item) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            Text(item.name)
                .font(.system(size: 14.5, weight: .semibold))
            Text(item.detail.isEmpty ? item.scope : item.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(item.scope)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .grokCard(cornerRadius: 14, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { model.runWorkflow(item) }
    }

    private func automationCard(_ item: AutomationRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }
            Text(item.title)
                .font(.system(size: 14.5, weight: .semibold))
            Text(item.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .grokCard(cornerRadius: 14, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { model.runAutomation(item) }
    }
}
