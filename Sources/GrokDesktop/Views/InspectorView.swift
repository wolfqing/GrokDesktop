import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l10n.t("Session", "会话"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.showInspector = false
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.inspector)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(palette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextSection
                    if model.client.mode == .plan {
                        planSection
                    }
                    toolsSection
                    subagentSection
                }
                .padding(14)
            }
        }
        .background(palette.sidebar)
        .onAppear { model.refreshWorkspace() }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Context", "上下文"))
            HStack {
                Text("\(model.workspace.contextPercent)%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
                Text(model.client.buildModel.title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.chip)
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(min(max(model.workspace.contextPercent, 0), 100)) / 100)
                }
            }
            .frame(height: 6)
            Text(model.client.workingDirectory.path)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Plan")
            Text(l10n.t("Plan mode is on. The agent writes plan.md and waits for approval.", "Plan 模式已开。agent 只写 plan.md，等你批准后再改代码。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            Text(model.client.mode.title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.chip, in: Capsule())
        }
    }

    private var toolsSection: some View {
        let tools = model.client.items.compactMap { item -> (String, String, String)? in
            if case .tool(let id, let title, let status, _) = item {
                return (id, title, status)
            }
            return nil
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("Tools", "工具"))
            if tools.isEmpty {
                Text(l10n.t("No tool calls in this turn.", "本轮还没有工具调用。"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(tools, id: \.0) { tool in
                    HStack {
                        Text(tool.1)
                            .lineLimit(1)
                        Spacer()
                        Text(tool.2)
                            .foregroundStyle(palette.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private var subagentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.subagents)
            HStack {
                Text("\(model.client.runningTools) \(l10n.running)")
                Spacer()
                Text("\(model.client.finishedTools) \(l10n.completed)")
                    .foregroundStyle(palette.secondary)
            }
            .font(.system(size: 13))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }
}
