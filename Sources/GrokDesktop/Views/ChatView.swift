import GrokDesktopCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if let reason = model.firstRunReason, model.client.items.isEmpty {
                FirstRunView(reason: reason)
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
            }

            if let permission = model.client.permission {
                PermissionBar(request: permission)
                    .frame(maxWidth: GrokTheme.contentWidth)
                    .padding(.bottom, 8)
            }

            ComposerView()
                .frame(maxWidth: GrokTheme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GrokTheme.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(model.client.workingDirectory.path) {
                model.chooseWorkingDirectory()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(GrokTheme.secondary)
            .lineLimit(1)

            Spacer()

            Button(model.client.mode.title) {
                model.client.mode = model.client.mode.next
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(GrokTheme.chip, in: Capsule())

            Button {
                model.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(GrokTheme.secondary)
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
            Text("Grok")
                .font(.system(size: 44, weight: .medium, design: .serif))
            Text("向 Grok 提任何问题")
                .font(.system(size: 16))
                .foregroundStyle(GrokTheme.secondary)
            HStack(spacing: 10) {
                suggestion("解释这个仓库")
                suggestion("/plan 下一步怎么改")
                suggestion("审查最近的提交")
            }
            Spacer()
        }
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) {
            model.draft = text
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GrokTheme.chip, in: Capsule())
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
                    .background(GrokTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .foregroundStyle(GrokTheme.secondary)
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
                        .foregroundStyle(GrokTheme.secondary)
                }
                .font(.system(size: 13, weight: .medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(GrokTheme.secondary)
                        .lineLimit(8)
                }
            }
            .padding(12)
            .background(GrokTheme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)
        case .notice(_, let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(GrokTheme.secondary)
                .padding(.horizontal, 28)
        }
    }
}
