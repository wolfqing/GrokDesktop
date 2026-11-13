import GrokDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var sidebarScroll = ChatScrollMetrics()
    @State private var sidebarDriver = ChatScrollDriver()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, model.sidebarCollapsed ? 8 : 12)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Group {
                if model.sidebarCollapsed {
                    collapsedRail
                } else {
                    expandedContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            accountFooter
                .layoutPriority(1)
        }
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.hairline)
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if model.sidebarCollapsed {
                Spacer(minLength: 0)
                GrokMark(size: 20)
                Spacer(minLength: 0)
            } else {
                GrokMark(size: 19)
                    .padding(.leading, 2)
                productSwitcher
                Spacer(minLength: 4)
                if model.destination.isBuildSurface {
                    GrokIconButton(
                        systemImage: "magnifyingglass",
                        size: 28,
                        iconSize: 12.5,
                        selected: model.showSearchField,
                        helpText: "\(l10n.search) (⌘⇧R)"
                    ) {
                        model.showSearchField.toggle()
                        if model.showSearchField {
                            DispatchQueue.main.async { searchFocused = true }
                        }
                    }
                }
            }
        }
    }

    private var productSwitcher: some View {
        HStack(spacing: 2) {
            productTab(l10n.productChat, shortcut: "⌘1", selected: model.destination == .webChat) {
                model.openWebChat()
            }
            productTab(l10n.productBuild, shortcut: "⌘2", selected: model.destination.isBuildSurface) {
                model.openBuildSurface()
            }
        }
        .padding(3)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private func productTab(_ title: String, shortcut: String, selected: Bool, action: @escaping () -> Void) -> some View {
        ProductTabButton(title: title, shortcut: shortcut, selected: selected, action: action)
    }

    private var collapsedRail: some View {
        VStack(spacing: 6) {
            railIconButton("bubble.left.and.bubble.right", help: "\(l10n.productChat) (⌘1)", selected: model.destination == .webChat) {
                model.openWebChat()
            }
            railIconButton("hammer", help: "\(l10n.productBuild) (⌘2)", selected: model.destination.isBuildSurface) {
                model.openBuildSurface()
            }
            if model.destination.isBuildSurface {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 24, height: 1)
                    .padding(.vertical, 4)
                railIconButton("magnifyingglass", help: l10n.search, selected: model.showSearchField) {
                    model.sidebarCollapsed = false
                    model.showSearchField = true
                }
                railIconButton("square.and.pencil", help: "\(l10n.newChat) (⌘N)", selected: model.destination == .build) {
                    model.openChat()
                }
                railIconButton(
                    "circle.hexagongrid",
                    help: "\(l10n.liveAgents) (⌃\\)",
                    selected: model.destination == .dashboard,
                    badgeCount: model.attentionBadgeCount
                ) {
                    model.destination = .dashboard
                }
                railIconButton("photo", help: l10n.imagine, selected: model.destination == .imagine) {
                    model.destination = .imagine
                }
                railIconButton("bolt", help: l10n.automations, selected: model.destination == .automations) {
                    model.destination = .automations
                }
                railIconButton("square.grid.2x2", help: l10n.skillsAndConnectors, selected: model.destination == .skills) {
                    model.destination = .skills
                }
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.destination == .webChat {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.webChatHint)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                Spacer()
            } else {
                if model.showSearchField {
                    searchField
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    navRow(
                        l10n.newChat,
                        systemImage: "square.and.pencil",
                        shortcut: "⌘N",
                        selected: model.destination == .build,
                        prominent: true
                    ) {
                        model.openChat()
                    }
                    navRow(
                        l10n.liveAgents,
                        systemImage: "circle.hexagongrid",
                        shortcut: "⌃\\",
                        selected: model.destination == .dashboard,
                        badgeCount: model.attentionBadgeCount
                    ) {
                        model.destination = .dashboard
                    }
                    navRow(l10n.imagine, systemImage: "photo", selected: model.destination == .imagine) {
                        model.destination = .imagine
                    }
                    navRow(l10n.automations, systemImage: "bolt", selected: model.destination == .automations) {
                        model.destination = .automations
                    }
                    navRow(l10n.skillsAndConnectors, systemImage: "square.grid.2x2", selected: model.destination == .skills) {
                        model.destination = .skills
                    }
                }

                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        disclosure(title: l10n.projects, expanded: $model.projectsExpanded) {
                            GrokIconButton(
                                systemImage: "plus",
                                size: 22,
                                iconSize: 11,
                                cornerRadius: 6,
                                helpText: l10n.addProject
                            ) {
                                model.showCreateProject = true
                            }
                        } content: {
                            if model.visibleProjects.isEmpty {
                                Text(l10n.noProjects)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(model.visibleProjects) { project in
                                        let current = model.isCurrentProject(project)
                                        let waiting = model.attentionCount(forPath: project.path)
                                        Button {
                                            model.openProject(project)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: current ? "folder.fill" : "folder")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(current ? palette.text : palette.secondary)
                                                    .frame(width: 16)
                                                Text(project.name)
                                                    .font(.system(size: 13, weight: current ? .medium : .regular))
                                                    .foregroundStyle(current ? palette.text : palette.text.opacity(0.9))
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                                attentionCount(waiting)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .grokHover(cornerRadius: 8, selected: current)
                                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 8)
                                        .help(waiting > 0
                                            ? l10n.t("\(waiting) to handle in this project", "这个项目有 \(waiting) 件要处理")
                                            : project.path)
                                        .contextMenu {
                                            Button(l10n.t("Trust", "信任")) { model.trustProject(project) }
                                            Button(l10n.t("Remove from list", "从列表移除")) { model.removeProject(project) }
                                        }
                                    }
                                }
                            }
                        }

                        if !model.liveSessions.isEmpty {
                            disclosure(title: l10n.t("Running", "进行中"), expanded: .constant(true)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(model.liveSessions) { session in
                                        historyRow(session, selected: model.client.sessionID == session.id, live: true) {
                                            model.open(session)
                                        }
                                    }
                                }
                            }
                        }

                        if let notice = model.sidebarNotice {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 11, weight: .medium))
                                Text(notice)
                                    .font(.system(size: 11.5))
                                    .lineLimit(2)
                            }
                            .foregroundStyle(palette.warning)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, 10)
                        }

                        disclosure(title: l10n.history, expanded: $model.historyExpanded) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.historyFolders) { folder in
                                    historyFolder(folder)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.never)
                .background(
                    ChatScrollBottomMonitor(
                        ignoreUntil: .distantPast,
                        isDark: palette.isDark,
                        onNearBottomChange: { _ in },
                        onMetrics: { sidebarScroll = $0 },
                        driver: sidebarDriver
                    )
                )
                .overlay(alignment: .trailing) {
                    OverlayScrollbar(
                        metrics: sidebarScroll,
                        isDark: palette.isDark,
                        driver: sidebarDriver,
                        onSeek: { sidebarDriver.seek(to: $0) }
                    )
                    .frame(width: 14)
                }
            }
        }
    }

    private var accountFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
            if model.sidebarCollapsed {
                Button(action: openAccount) {
                    GrokAvatar(initial: accountInitial, size: 28, fontSize: 12)
                        .padding(4)
                        .grokHover(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help(accountTitle)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    Button(action: openAccount) {
                        HStack(spacing: 9) {
                            GrokAvatar(initial: accountInitial, size: 28, fontSize: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(accountTitle)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .lineLimit(1)
                                if let email = model.account.email, !email.isEmpty {
                                    Text(email)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .grokHover(cornerRadius: 8)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(l10n.account)

                    GrokIconButton(
                        systemImage: "rectangle.inset.filled",
                        size: 28,
                        iconSize: 13,
                        helpText: l10n.t("Desk", "桌面条")
                    ) {
                        model.openCompanion()
                    }
                    GrokIconButton(
                        systemImage: "gearshape",
                        size: 28,
                        iconSize: 13.5,
                        helpText: "\(model.shell(.navSettings)) (⌘,)"
                    ) {
                        openSettings()
                    }
                    .accessibilityLabel(model.shell(.navSettings))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    private var accountTitle: String {
        model.account.displayName.isEmpty ? l10n.account : model.account.displayName
    }

    private var accountInitial: String {
        model.account.initial.isEmpty ? "G" : model.account.initial
    }

    private func openAccount() {
        model.settingsSection = .account
        model.showSettings = true
    }

    private func openSettings() {
        model.showSettings = true
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
            TextField(l10n.t("Title, folder, or time", "标题、目录或时间"), text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !model.search.isEmpty {
                Button {
                    model.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .grokFieldChrome(cornerRadius: 9, focused: searchFocused)
    }

    private func navRow(
        _ title: String,
        systemImage: String,
        shortcut: String? = nil,
        selected: Bool = false,
        prominent: Bool = false,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        SidebarNavRow(
            title: title,
            systemImage: systemImage,
            shortcut: shortcut,
            selected: selected,
            prominent: prominent,
            badgeCount: badgeCount,
            action: action
        )
    }

    private func disclosure<Content: View>(
        title: String,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        disclosure(title: title, expanded: expanded, accessory: { EmptyView() }, content: content)
    }

    private func disclosure<Content: View, Accessory: View>(
        title: String,
        expanded: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(palette.tertiary)
                            .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                accessory()
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            if expanded.wrappedValue {
                content()
            }
        }
    }

    private func historyFolder(_ folder: HistoryFolder) -> some View {
        let expanded = model.isHistoryFolderExpanded(folder)
        let current = model.isCurrentHistoryFolder(folder)
        let waiting = model.attentionCount(forPath: folder.path)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleHistoryFolder(folder)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.tertiary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .frame(width: 10)
                    Image(systemName: current ? "folder.fill" : "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text(folder.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    attentionCount(waiting)
                }
                .foregroundStyle(current ? palette.text : palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .grokHover(cornerRadius: 7)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help(waiting > 0
                ? l10n.t("\(waiting) to handle in this project", "这个项目有 \(waiting) 件要处理")
                : (folder.path.isEmpty ? folder.name : folder.path))
            .contextMenu {
                Button(l10n.openProject) {
                    model.openProject(NamedProject(id: folder.id, name: folder.name, path: folder.path))
                }
                .disabled(folder.path.isEmpty)
            }
            if expanded {
                ForEach(folder.sessions) { session in
                    historyRow(session, selected: model.client.sessionID == session.id, indented: true) {
                        model.open(session)
                    }
                    .contextMenu {
                        Button(l10n.t("Rename", "重命名")) {
                            model.renamingSession = session
                            model.renameDraft = session.title
                        }
                        Button(l10n.t("Export", "导出")) { model.export(session) }
                        Button(l10n.t("Archive", "归档")) { model.archiveSession(session) }
                        Divider()
                        Button(l10n.t("Delete", "删除"), role: .destructive) { model.delete(session) }
                    }
                }
            }
        }
    }

    private func historyRow(
        _ session: SessionRecord,
        selected: Bool,
        live: Bool = false,
        indented: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let chinese = model.showsChinese
        return Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                if live {
                    Circle()
                        .fill(palette.warning)
                        .frame(width: 6, height: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(selected ? palette.text : palette.text.opacity(0.92))
                    if !session.preview.isEmpty, session.preview != session.title {
                        Text(session.preview)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Text(RelativeTime.meta(session, chinese: chinese, includeFolder: !indented))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, indented ? 22 : 10)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .grokHover(cornerRadius: 8, selected: selected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func railIconButton(
        _ systemImage: String,
        help: String,
        selected: Bool = false,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            GrokIconButton(
                systemImage: systemImage,
                size: 36,
                iconSize: 14.5,
                selected: selected,
                cornerRadius: 10,
                helpText: help,
                action: action
            )
            attentionCount(badgeCount)
                .offset(x: 5, y: -5)
        }
    }

    @ViewBuilder
    private func attentionCount(_ count: Int) -> some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .frame(minWidth: 16, minHeight: 16)
                .background(palette.warning, in: Capsule())
        }
    }
}

private struct ProductTabButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let shortcut: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected || hovering ? palette.text : palette.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4.5)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(palette.elevated)
                            .shadow(color: .black.opacity(palette.isDark ? 0.35 : 0.08), radius: 2, y: 1)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(palette.hover)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(title) (\(shortcut))")
    }
}

private struct SidebarNavRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    let shortcut: String?
    let selected: Bool
    let prominent: Bool
    let badgeCount: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13.5, weight: selected || prominent ? .semibold : .medium))
                    .foregroundStyle(selected || prominent || hovering ? palette.text : palette.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13.5, weight: selected || prominent ? .medium : .regular))
                    .foregroundStyle(selected || prominent || hovering ? palette.text : palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, badgeCount > 9 ? 4 : 0)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(palette.warning, in: Capsule())
                } else if hovering, let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected ? palette.selected : (hovering ? palette.hover : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }
}
