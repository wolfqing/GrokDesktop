import GrokDesktopCore
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text(l10n.automations)
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                    Button(l10n.newAutomation) { model.createAutomation() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                }

                if !model.automations.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.automations) { item in
                            automationCard(item, suggested: false)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(l10n.suggested)
                        .font(.system(size: 16, weight: .semibold))
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.automationStore.suggested(language: model.language.resolved() == .chinese ? "zh" : "en")) { item in
                            automationCard(item, suggested: true)
                        }
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvas)
    }

    private func automationCard(_ item: AutomationRecord, suggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: suggested ? suggestedIcon(item) : "bolt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(palette.chip, in: Circle())
                Spacer()
                if suggested {
                    Button(l10n.add) { model.addAutomation(item) }
                        .buttonStyle(GrokSecondaryButtonStyle())
                } else {
                    Menu {
                        Button(l10n.runAutomation) { model.runAutomation(item) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(palette.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
            Text(item.detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            if !suggested { model.runAutomation(item) }
        }
    }

    private func suggestedIcon(_ item: AutomationRecord) -> String {
        if item.id.contains("email") { return "envelope" }
        if item.id.contains("stock") { return "dollarsign" }
        return "checkmark.circle"
    }
}
