import GrokDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if model.sidebarCollapsed {
                collapsedRail
            } else {
                expandedContent
            }
        }
        .background(palette.sidebar)
    }

    private var header: some View {
        HStack {
            if model.sidebarCollapsed {
                Button { model.sidebarCollapsed = false } label: {
                    GrokMark(size: 20)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                GrokMark(size: 22)
                Spacer()
                Button {
                    model.sidebarCollapsed = true
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("收起侧栏")
            }
        }
    }

    private var collapsedRail: some View {
        VStack(spacing: 8) {
            iconButton("magnifyingglass") { model.sidebarCollapsed = false; model.showSearchField = true }
            iconButton("square.and.pencil") { model.startNewSession() }
            iconButton("photo") { model.draft = "/imagine " }
            iconButton("bolt") {
                model.showInspector = true
            }
            iconButton("square.grid.2x2") {
                model.settingsSection = .extensions
                model.showSettings = true
            }
            Spacer()
            iconButton("gearshape") { model.showSettings = true }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            navRow("Search", systemImage: "magnifyingglass", selected: model.showSearchField) {
                model.showSearchField.toggle()
            }
            navRow("New Chat", systemImage: "square.and.pencil", selected: model.isEmptyChat) {
                model.startNewSession()
            }
            navRow("Imagine", systemImage: "photo") {
                model.draft = "/imagine "
            }
            navRow("Automations", systemImage: "bolt") {
                model.showInspector = true
            }
            navRow("Skills and Connectors", systemImage: "square.grid.2x2") {
                model.settingsSection = .extensions
                model.showSettings = true
            }

            if model.showSearchField {
                searchField
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    disclosure(title: "Projects", expanded: $model.projectsExpanded) {
                        if model.projectPaths.isEmpty {
                            Text("No projects yet")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(model.projectPaths, id: \.path) { project in
                                Button {
                                    model.client.workingDirectory = URL(fileURLWithPath: project.path)
                                    model.startNewSession()
                                } label: {
                                    Label(project.name, systemImage: "folder")
                                        .labelStyle(.titleAndIcon)
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
                            model.chooseWorkingDirectory()
                        } label: {
                            Label("Add project", systemImage: "plus")
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    disclosure(title: "History", expanded: $model.historyExpanded) {
                        if model.client.isTurnRunning {
                            historyRow(title: model.client.workingDirectory.lastPathComponent, subtitle: "Running", selected: true) {}
                        }
                        ForEach(model.filteredSessions) { session in
                            historyRow(
                                title: session.title,
                                subtitle: nil,
                                selected: model.client.sessionID == session.id
                            ) {
                                model.open(session)
                            }
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondary)
            TextField("Search", text: $model.search)
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

    private func historyRow(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if subtitle == "Running" {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .foregroundStyle(palette.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
