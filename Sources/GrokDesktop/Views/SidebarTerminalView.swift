import SwiftUI

struct SidebarTerminalPane: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            SidebarTerminalHost(shell: model.sidebarShell)
                .frame(height: model.shellHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(palette.sidebar)
        .onAppear {
            model.sidebarShell.sync(
                directory: model.client.workingDirectory.path,
                isDark: palette.isDark
            )
        }
        .onChange(of: model.client.workingDirectory) { _, directory in
            model.sidebarShell.sync(directory: directory.path, isDark: palette.isDark)
        }
        .onChange(of: palette.isDark) { _, isDark in
            model.sidebarShell.apply(isDark: isDark)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(l10n.t("Terminal", "终端"))
                .font(.system(size: 12, weight: .semibold))
            Text(folderName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .help(model.client.workingDirectory.path)
            Spacer(minLength: 4)
            headerButton(l10n.t("Restart", "重启"), help: l10n.t("Restart the shell in this project", "在当前项目里重启终端")) {
                model.sidebarShell.restart(directory: model.client.workingDirectory.path)
            }
            Button {
                model.setInspectorPane(.shell, visible: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(l10n.t("Close terminal", "关闭终端"))
            headerButton(l10n.t("Open", "打开"), help: l10n.t("Open this folder in Terminal", "用系统终端打开这个文件夹")) {
                model.openInTerminal()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(palette.hairline)
                    .frame(width: 36, height: 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = model.shellHeight
                        }
                        model.setShellHeight((dragOrigin ?? model.shellHeight) - value.translation.height)
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                    }
            )
            .onTapGesture(count: 2) {
                model.setShellHeight(GrokTheme.shellHeight)
            }
            .help(l10n.t("Drag to resize. Double-click to reset.", "拖动调整高度。双击恢复默认。"))
    }

    @State private var dragOrigin: CGFloat?

    private var folderName: String {
        let path = model.client.workingDirectory.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return "~" }
        return model.client.workingDirectory.lastPathComponent
    }

    private func headerButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.secondary)
            .help(help)
    }
}

private struct SidebarTerminalHost: NSViewRepresentable {
    let shell: SidebarShell

    func makeNSView(context: Context) -> NSView {
        shell.hostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
