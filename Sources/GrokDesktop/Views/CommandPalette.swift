import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private var commands: [(String, String)] {
        [
            ("/new", l10n.newChat),
            ("/settings", l10n.settings),
            ("/plan", l10n.t("Enter Plan mode", "进入 Plan 模式")),
            ("/imagine", l10n.imagine),
            ("/usage", l10n.usage),
            ("/home", l10n.t("Home", "回到首页")),
            ("/quit", l10n.t("Quit", "退出"))
        ]
    }

    var body: some View {
        ZStack {
            palette.overlay
                .ignoresSafeArea()
                .onTapGesture { model.showPalette = false }

            VStack(alignment: .leading, spacing: 0) {
                Text(l10n.t("Commands", "命令"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(12)
                ForEach(filtered, id: \.0) { command in
                    Button {
                        model.handleCommand(command.0)
                        model.draft = ""
                    } label: {
                        HStack {
                            Text(command.0)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                            Spacer()
                            Text(command.1)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 420)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
            .offset(y: 120)
        }
    }

    private var filtered: [(String, String)] {
        let query = model.draft.lowercased()
        if query.count <= 1 { return commands }
        return commands.filter { $0.0.contains(query) || $0.1.localizedCaseInsensitiveContains(query) }
    }
}
