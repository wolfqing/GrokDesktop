import GrokDesktopCore
import SwiftUI

struct ModelEffortPicker: View {
    @Binding var isOpen: Bool
    @Binding var buildModel: BuildModel
    @Binding var effort: EffortLevel
    let chinese: Bool
    let applyTier: (ModelTier) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    @State private var page: Page = .home
    @State private var showAdvanced = false
    @State private var hovered: String?

    private enum Page {
        case home
        case model
        case effort
    }

    var body: some View {
        chip
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                panel
                    .padding(.vertical, 4)
                    .frame(width: 260)
            }
            .onChange(of: isOpen) { _, open in
                if open {
                    page = .home
                } else {
                    showAdvanced = false
                }
            }
    }

    private var chip: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(buildModel.shortTitle)
                Text(effort.title(chinese: chinese))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(palette.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("\(buildModel.menuTitle) · \(effort.title(chinese: chinese))")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch page {
            case .home:
                homePage
            case .model:
                drillPage(title: l10n.t("Model", "模型")) {
                    ForEach(BuildModel.allCases) { item in
                        optionRow(
                            id: "model-\(item.id)",
                            title: item.menuTitle,
                            selected: buildModel == item
                        ) {
                            buildModel = item
                            page = .home
                        }
                    }
                }
            case .effort:
                drillPage(title: l10n.t("Reasoning", "推理强度")) {
                    ForEach(EffortLevel.allCases) { level in
                        optionRow(
                            id: "effort-\(level.id)",
                            title: level.title(chinese: chinese),
                            selected: effort == level
                        ) {
                            effort = level
                            page = .home
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var homePage: some View {
        drillRow(
            id: "row-model",
            title: l10n.t("Model", "模型"),
            value: buildModel.shortTitle
        ) {
            page = .model
        }
        drillRow(
            id: "row-effort",
            title: l10n.t("Reasoning", "推理强度"),
            value: effort.title(chinese: chinese)
        ) {
            page = .effort
        }
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        Button {
            showAdvanced.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(l10n.t("Advanced", "高级"))
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showAdvanced ? 0 : 180))
                Spacer()
            }
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showAdvanced {
            ForEach(ModelTier.allCases) { tier in
                optionRow(
                    id: "tier-\(tier.id)",
                    title: tier.menuTitle,
                    detail: tier.menuSubtitle,
                    selected: false
                ) {
                    applyTier(tier)
                }
            }
        }
    }

    private func drillPage<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                page = .home
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            content()
        }
    }

    private func drillRow(id: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer(minLength: 12)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(hovered == id ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            hovered = hovering ? id : (hovered == id ? nil : hovered)
        }
    }

    private func optionRow(id: String, title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(hovered == id ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            hovered = hovering ? id : (hovered == id ? nil : hovered)
        }
    }
}
