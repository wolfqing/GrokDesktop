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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(model.client.items) { item in
                                messageRow(item)
                                    .id(item.id)
                            }
                        }
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: model.client.items.count) { _, _ in
                        if model.autoScroll, let last = model.client.items.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }

    private var composerBlock: some View {
        VStack(spacing: 10) {
            ComposerView()
                .frame(maxWidth: 680)
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
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.settings)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            SuperGrokWordmark(markSize: 48)
            composerBlock
            Spacer()
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func messageRow(_ item: ConversationItem) -> some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(palette.selected, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 28)
        case .assistant(_, let text, _):
            Text(text.isEmpty ? "…" : text)
                .font(.system(size: 16))
                .textSelection(.enabled)
                .padding(.horizontal, 28)
        case .thought(_, let text):
            DisclosureGroup(l10n.think) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 28)
        case .tool(_, let title, let status, let detail):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    Text(title)
                    Spacer()
                    Text(status)
                        .foregroundStyle(palette.secondary)
                }
                .font(.system(size: 13, weight: .medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(model.wrapCodeLines ? 20 : 8)
                }
            }
            .padding(12)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)
        case .notice(_, let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 28)
        }
    }
}
