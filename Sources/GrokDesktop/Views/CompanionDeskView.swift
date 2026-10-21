import GrokDesktopCore
import SwiftUI

struct CompanionDeskView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @State private var dictate = ""

    private var phase: CompanionPhase {
        CompanionDesk.phase(
            turnRunning: model.client.isTurnRunning,
            needsPermission: model.client.permission != nil,
            needsQuestion: model.client.userQuestion != nil,
            unseen: !model.unseenTurns.isEmpty
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                activityMark
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desk")
                        .font(.system(size: 13, weight: .semibold))
                    Text(phaseLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                Spacer()
            }
            TextField(l10n.t("Dictate", "口述"), text: $dictate)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(l10n.t("Add", "加入")) { dictateNow() }
                Button(l10n.t("Send", "发送")) { sendNow() }
                Button(l10n.t("Stop", "停止")) { stopNow() }
            }
            .font(.system(size: 12, weight: .medium))
            if !desk.companionDraft.isEmpty {
                Text(desk.companionDraft)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.elevated)
    }

    private var activityMark: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(phase == .working ? Color.orange : palette.text)
                    .frame(width: 5, height: 8 + CGFloat(index) * 4)
            }
        }
        .frame(width: 24, height: 22, alignment: .bottom)
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: return l10n.t("Idle", "空闲")
        case .working: return l10n.t("Working", "进行中")
        case .needsInput: return l10n.t("Needs you", "需要你")
        case .done: return l10n.t("Finished", "已完成")
        }
    }

    private func dictateNow() {
        if case .draft(let text) = CompanionDesk.apply(.dictate(dictate), draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            desk.companionDraft = text
        }
        dictate = ""
    }

    private func sendNow() {
        if case .send(let text) = CompanionDesk.apply(.send, draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            model.draft = text
            desk.companionDraft = ""
            model.sendDraft()
        }
    }

    private func stopNow() {
        if case .stop = CompanionDesk.apply(.stop, draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            model.client.stopWork()
        }
    }
}
