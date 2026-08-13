import GrokDesktopCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            header

            if let reason = model.firstRunReason, model.client.items.isEmpty {
                FirstRunView(reason: reason)
                composerBlock
            } else if model.client.items.isEmpty {
                emptyState
            } else {
                if let other = model.client.backgroundPermissions.first {
                    Button {
                        _ = model.client.focusIfLoaded(other.id)
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text(l10n.t("Another session is waiting for approval", "另一个会话在等你批准"))
                            Spacer()
                            Text(other.title.isEmpty ? String(other.id.prefix(8)) : other.title)
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.system(size: 12))
                        .padding(10)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: model.compactChat ? 10 : 22) {
                            ForEach(displayedItems) { item in
                                messageRow(item)
                                    .id(item.id)
                            }
                        }
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.vertical, model.compactChat ? 14 : 28)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: model.client.items.count) { _, _ in
                        if model.autoScroll, let last = model.client.items.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: model.jumpTarget) { _, target in
                        if let target {
                            proxy.scrollTo(target, anchor: .center)
                            model.jumpTarget = nil
                        }
                    }
                }

                if let permission = model.client.permission {
                    PermissionBar(request: permission)
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.bottom, 8)
                }

                composerBlock
            }

            if let error = model.client.lastError, model.firstRunReason == nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .textSelection(.enabled)
                    Spacer()
                    Button(l10n.t("Dismiss", "关闭")) { model.client.dismissError() }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(10)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }

    private var composerBlock: some View {
        VStack(spacing: 10) {
            ComposerView()
                .frame(maxWidth: 760)
            if model.isPrivateChat {
                HStack(spacing: 6) {
                    Image(systemName: "eyeglasses")
                    Text(l10n.privateBanner)
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.sidebarCollapsed {
                Button { model.sidebarCollapsed = false } label: {
                    GrokMark(size: 18)
                }
                .buttonStyle(.plain)
            }
            if !model.client.items.isEmpty {
                Button(model.client.workingDirectory.path) {
                    model.chooseWorkingDirectory()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                Button(model.client.mode.title) { model.cycleMode() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .help("Shift+Tab")
                Text(model.client.modelTier.menuTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                Button {
                    model.openUsage()
                } label: {
                    Text(model.accountUsage.isLoaded ? "\(model.accountUsage.displayPercent)%" : "\(model.workspace.contextPercent)%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .help("/usage")
            }
            Spacer()
            Button {
                model.isPrivateChat.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eyeglasses")
                    Text(l10n.privateChat)
                }
                .font(.system(size: 13))
                .foregroundStyle(model.isPrivateChat ? Color.blue : palette.secondary)
            }
            .buttonStyle(.plain)
            Button {
                model.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(model.showInspector ? palette.text : palette.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.inspector)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            SuperGrokWordmark(markSize: 48, title: model.account.plan.wordmark)
            composerBlock
            Spacer()
            Spacer(minLength: 24)
        }
    }

    private var displayedItems: [ConversationItem] {
        var result: [ConversationItem] = []
        for item in model.client.items {
            if case .thought = item, !model.showThinkingBlocks { continue }
            if model.mergeToolRows,
               case .tool(_, let title, _, _) = item,
               case .tool(_, let previous, _, _) = result.last,
               previous == title {
                continue
            }
            result.append(item)
        }
        return result
    }

    @ViewBuilder
    private func timestamp(_ id: String, always: Bool = false) -> some View {
        if always || model.showTimestamps, let date = model.client.itemDates[id] {
            Text(PromptTimestamp.format(date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondary)
        }
    }

    @ViewBuilder
    private func messageRow(_ item: ConversationItem) -> some View {
        switch item {
        case .user(let id, let text):
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    timestamp(id, always: true)
                    Text(text)
                        .font(.system(size: model.compactChat ? 14 : 16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, model.compactChat ? 8 : 12)
                        .background(palette.selected, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .assistant(let id, let text, _):
            VStack(alignment: .leading, spacing: 4) {
                timestamp(id)
                Text(text.isEmpty ? "…" : text)
                    .font(.system(size: model.compactChat ? 14 : 16))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .thought(_, let text):
            DisclosureGroup(l10n.think) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, model.compactChat ? 16 : 28)
        case .tool(let id, let title, let status, let detail):
            DisclosureGroup {
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    Text(title)
                    Spacer()
                    Text(status)
                        .foregroundStyle(palette.secondary)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(12)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)
            .help(id)
        case .notice(_, let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 28)
        }
    }
}
