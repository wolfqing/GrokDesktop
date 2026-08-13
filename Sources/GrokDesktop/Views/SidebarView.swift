import GrokDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(GrokTheme.text)
                    .frame(width: 18, height: 18)
                Text("Grok")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            sidebarButton(title: "新会话", systemImage: "square.and.pencil") {
                model.startNewSession()
            }
            sidebarButton(title: "Imagine", systemImage: "sparkles") {
                model.draft = "/imagine "
            }

            searchField
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    liveSection
                    ForEach(model.groupedSessions, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.key)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(GrokTheme.secondary)
                                .padding(.horizontal, 16)
                            ForEach(group.values) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }

            Divider().overlay(GrokTheme.hairline)
            HStack {
                Button {
                    model.settingsSection = .account
                    model.showSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                        Text("账号")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(GrokTheme.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(GrokTheme.secondary)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(14)
        }
        .background(GrokTheme.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GrokTheme.secondary)
            TextField("搜索", text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GrokTheme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var liveSection: some View {
        if model.client.isTurnRunning {
            VStack(alignment: .leading, spacing: 4) {
                Text("进行中")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GrokTheme.secondary)
                    .padding(.horizontal, 16)
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(model.client.workingDirectory.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        Button {
            model.open(session)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(session.cwdName)
                    .font(.system(size: 11))
                    .foregroundStyle(GrokTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                model.client.sessionID == session.id ? GrokTheme.chip : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
