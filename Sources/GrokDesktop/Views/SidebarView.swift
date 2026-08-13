import GrokDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if model.sidebarCollapsed {
                collapsedRail
            } else {
                expandedContent
            }

            accountFooter
        }
        .background(palette.sidebar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            GrokMark(size: 20)
            if !model.sidebarCollapsed {
                Text("Grok build")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    model.showSearchField.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(model.showSearchField ? palette.text : palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            model.showSearchField ? palette.selected : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(l10n.search)
            }
        }
    }

    private var collapsedRail: some View {
        VStack(spacing: 8) {
            iconButton("magnifyingglass") { model.sidebarCollapsed = false; model.showSearchField = true }
            iconButton("square.and.pencil") { model.openChat() }
            iconButton("circle.hexagongrid") { model.destination = .dashboard }
            iconButton("photo") { model.destination = .imagine }
            iconButton("bolt") { model.destination = .automations }
            iconButton("square.grid.2x2") { model.destination = .skills }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.showSearchField {
                searchField
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            navRow(l10n.newChat, systemImage: "square.and.pencil", selected: model.destination == .chat) {
                model.openChat()
            }
            navRow(l10n.liveAgents, systemImage: "circle.hexagongrid", selected: model.destination == .dashboard || model.client.isLive) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    disclosure(title: l10n.projects, expanded: $model.projectsExpanded) {
                        if model.visibleProjects.isEmpty {
                            Text(l10n.noProjects)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(model.visibleProjects) { project in
                                Button {
                                    model.client.workingDirectory = URL(fileURLWithPath: project.path)
                                    model.startNewSession()
                                } label: {
                                    Text(project.name)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(palette.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            model.showCreateProject = true
                        } label: {
                            Text(l10n.addProject)
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    if !model.liveSessions.isEmpty {
                        disclosure(title: l10n.liveAgents, expanded: .constant(true)) {
                            ForEach(model.liveSessions) { session in
                                historyRow(title: session.title, selected: true) {
                                    model.open(session)
                                }
                            }
                        }
                    }

                    if let notice = model.sidebarNotice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    disclosure(title: l10n.history, expanded: $model.historyExpanded) {
                        ForEach(model.filteredSessions) { session in
                            historyRow(title: session.title, selected: model.client.sessionID == session.id) {
                                model.open(session)
                            }
                            .contextMenu {
                                Button(l10n.t("Rename", "重命名")) {
                                    model.renamingSession = session
                                    model.renameDraft = session.title
                                }
                                Button(l10n.t("Export", "导出")) { model.export(session) }
                                Button(l10n.t("Delete", "删除"), role: .destructive) { model.delete(session) }
                            }
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 16)
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
                    avatar
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(accountTitle)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button(action: openAccount) {
                        HStack(spacing: 10) {
                            avatar
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(accountTitle)
                                    .font(.system(size: 13, weight: .medium))
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n.account)

                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.settings)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.purple)
            Text(accountInitial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondary)
            TextField(l10n.search, text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func navRow(_ title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func disclosure<Content: View>(title: String, expanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                    Spacer()
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                content()
            }
        }
    }

    private func historyRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: 30)
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.text)
                .frame(width: 36, height: 36)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
