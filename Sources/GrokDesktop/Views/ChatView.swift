import GrokDesktopCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if !model.isEmptyChat || model.firstRunReason != nil {
                header
            }

            if let reason = model.firstRunReason, model.client.items.isEmpty {
                FirstRunView(reason: reason)
                ComposerView()
                    .frame(maxWidth: GrokTheme.contentWidth)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
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
                        if let last = model.client.items.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                if let permission = model.client.permission {
                    PermissionBar(request: permission)
                        .frame(maxWidth: GrokTheme.contentWidth)
                        .padding(.bottom, 8)
                }

                ComposerView()
                    .frame(maxWidth: GrokTheme.contentWidth)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.sidebarCollapsed {
                Button { model.sidebarCollapsed = false } label: {
                    GrokMark(size: 18)
                }
                .buttonStyle(.plain)
            }
            Button(model.client.workingDirectory.path) {
                model.chooseWorkingDirectory()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)

            Spacer()

            Button(model.client.mode.title) {
                model.client.mode = model.client.mode.next
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(palette.chip, in: Capsule())

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help("设置")

            Button {
                model.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help("检查器")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()
            SuperGrokWordmark(markSize: 48)
            ComposerView()
                .frame(maxWidth: 680)
                .padding(.horizontal, 24)
            Spacer()
            Spacer(minLength: 40)
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
            DisclosureGroup("思考") {
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
                        .lineLimit(8)
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
