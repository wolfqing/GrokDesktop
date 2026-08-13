import AppKit
import GrokDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider().overlay(palette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    environmentSection
                    subagentSection
                    sourcesSection
                    if model.client.mode == .plan {
                        planHint
                    }
                }
                .padding(14)
            }
        }
        .background(palette.sidebar)
        .onAppear { model.refreshWorkspace() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            toolIcon("terminal", help: "Terminal") { model.openInTerminal() }
            toolIcon("folder", help: l10n.files) { model.openInFinder() }
            toolIcon("globe", help: l10n.webSearch) {
                NSWorkspace.shared.open(URL(string: "https://grok.com")!)
            }
            Menu {
                Button(l10n.artifacts) { model.destination = .automations }
                Button(l10n.files) { model.openInFinder() }
                Button(l10n.backgroundTasks) { model.destination = .automations }
                Divider()
                Button(l10n.t("Rename session", "重命名会话")) {
                    model.draft = "/rename "
                    model.destination = .chat
                }
                Button(l10n.t("Fork session", "分叉会话")) {
                    model.draft = "/fork"
                    model.sendDraft()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
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
    }

    private func toolIcon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.text)
                .frame(width: 28, height: 28)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(l10n.environment)
            row(icon: "plus.square.on.square", title: l10n.changes) {
                HStack(spacing: 6) {
                    Text("+\(model.workspace.insertions)").foregroundStyle(.green)
                    Text("-\(model.workspace.deletions)").foregroundStyle(.red)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            row(icon: "laptopcomputer", title: l10n.local) {
                Image(systemName: "chevron.down").foregroundStyle(palette.secondary).font(.system(size: 10))
            }
            row(icon: "arrow.triangle.branch", title: model.workspace.branch ?? "—") {
                Image(systemName: "chevron.down").foregroundStyle(palette.secondary).font(.system(size: 10))
            }
            row(icon: "eye.slash", title: l10n.commitOrPush) {
                EmptyView()
            }
            .opacity(0.55)
            row(icon: "arrow.left.arrow.right", title: l10n.compareBranch) {
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
        }
    }

    private var subagentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(l10n.subagents)
            HStack {
                Image(systemName: "circle.hexagongrid")
                    .foregroundStyle(Color.cyan)
                Text("\(max(model.client.runningTools, model.client.isTurnRunning ? 1 : 0)) \(l10n.running)")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(model.client.finishedTools) \(l10n.completed)")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(l10n.sources, plus: true)
            if model.workspace.remotes.isEmpty {
                row(icon: "globe", title: l10n.webSearch) { EmptyView() }
            } else {
                ForEach(model.workspace.remotes.prefix(4), id: \.self) { remote in
                    row(icon: "circle.hexagonpath", title: remote) { EmptyView() }
                }
                row(icon: "globe", title: l10n.webSearch) { EmptyView() }
            }
            Button(l10n.viewAll) {
                model.openInFinder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(palette.secondary)
        }
    }

    private var planHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan")
                .font(.system(size: 13, weight: .semibold))
            Text(l10n.t("Plan mode is on. Approve before implementation.", "当前是 Plan 模式，批准后才会改代码。"))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionHeader(_ title: String, plus: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            Spacer()
            if plus {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func row<Trailing: View>(icon: String, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundStyle(palette.secondary)
            Text(title)
                .font(.system(size: 13.5))
                .lineLimit(1)
            Spacer()
            trailing()
        }
    }
}
