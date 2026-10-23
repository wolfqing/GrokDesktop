import GrokDesktopCore
import SwiftUI

struct CompanionDeskView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskController
    @Environment(\.palette) private var palette
    @StateObject private var speech = DictateCapture()
    @State private var dictate = ""

    private var copy: L10n { model.copy }

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
            TextField(copy.t("Dictate", "口述"), text: $dictate)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(copy.t("Add", "加入")) { dictateNow() }
                Button(speech.listening ? copy.t("Stop speaking", "说完") : copy.t("Speak", "口述")) { speakNow() }
                Button(copy.t("Send", "发送")) { sendNow() }
                Button(copy.t("Stop", "停止")) { stopNow() }
            }
            .font(.system(size: 12, weight: .medium))
            if !speech.status.isEmpty {
                Text(speech.status)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            if phase == .needsInput {
                Button(copy.t("Open the session", "打开这个会话")) { revealSession() }
                    .font(.system(size: 12, weight: .medium))
            }
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
        .onDisappear { speech.stop() }
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
        case .idle: return copy.t("Idle", "空闲")
        case .working: return copy.t("Working", "进行中")
        case .needsInput: return copy.t("Needs you", "需要你")
        case .done: return copy.t("Finished", "已完成")
        }
    }

    private func speakNow() {
        speech.toggle(
            localeID: desk.localeID,
            deniedSpeech: copy.t("Speech recognition is off.", "语音识别没有打开。"),
            deniedMic: copy.t("The microphone is off.", "麦克风没有打开。"),
            unavailable: copy.t("Speech recognition is not available.", "这台 Mac 不能做语音识别。"),
            onPartial: { dictate = $0 },
            onFinal: { text in
                dictate = text
                dictateNow()
            }
        )
    }

    private func dictateNow() {
        if case .draft(let text) = CompanionDesk.apply(.dictate(dictate), draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            desk.companionDraft = text
        }
        dictate = ""
    }

    private func sendNow() {
        if case .send(let text) = CompanionDesk.apply(.send, draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            desk.companionDraft = ""
            model.sendText(text)
            revealSession()
        }
    }

    private func revealSession() {
        model.destination = .build
        NSApp.activate(ignoringOtherApps: true)
    }

    private func stopNow() {
        if case .stop = CompanionDesk.apply(.stop, draft: desk.companionDraft, turnRunning: model.client.isTurnRunning) {
            model.client.stopWork()
        }
    }
}
