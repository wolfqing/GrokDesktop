import GrokDesktopCore
import SwiftUI

struct QuestionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    let request: UserQuestionRequest
    @State private var selected: [String: Set<String>] = [:]
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.isPlanReview
                 ? l10n.t("Review this plan", "看看这个计划")
                 : l10n.t("Grok has a question", "Grok 在问你"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)

            ForEach(request.questions) { question in
                if case .planReview(let approve) = question.intent {
                    planBlock(question, approve: approve)
                } else {
                    questionBlock(question)
                }
            }

            TextField(l10n.t("Or say something else…", "或者另说一句…"), text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .padding(10)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                Button(l10n.t("Continue", "继续")) {
                    submit()
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                .disabled(!canSubmit && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(l10n.t("Skip", "跳过")) {
                    model.client.answerQuestion(.skipInterview)
                }
                .buttonStyle(GrokSecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private var canSubmit: Bool {
        request.questions.allSatisfy { question in
            !(selected[question.id] ?? []).isEmpty
        }
    }

    private func questionBlock(_ question: UserQuestion) -> some View {
        let picks = selected[question.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            if !question.question.isEmpty {
                Text(question.question)
                    .font(.system(size: 14, weight: .medium))
            }
            if !question.detail.isEmpty {
                Text(question.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            if question.multiSelect {
                Text(l10n.t("Pick any that apply", "可以多选"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(question.options) { option in
                    let on = picks.contains(option.label)
                    Button {
                        toggle(option.label, on: question)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(on: on, multi: question.multiSelect))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? Color.orange : palette.secondary)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .medium))
                                if !option.detail.isEmpty {
                                    Text(option.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.secondary)
                                }
                                if on, let preview = option.preview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(palette.secondary)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            on ? palette.selected : palette.chip,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func planBlock(_ question: UserQuestion, approve: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !question.question.isEmpty {
                Text(question.question)
                    .font(.system(size: 14, weight: .medium))
            }
            if !question.detail.isEmpty {
                Text(question.detail)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(16)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 8) {
                Button(approve) {
                    selected[question.id] = [approve]
                    submit(force: question)
                }
                .buttonStyle(GrokPrimaryButtonStyle())
                ForEach(question.options.filter { $0.label != approve }) { option in
                    Button(option.label) {
                        selected[question.id] = [option.label]
                        submit(force: question)
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                }
            }
        }
    }

    private func icon(on: Bool, multi: Bool) -> String {
        if multi {
            return on ? "checkmark.square.fill" : "square"
        }
        return on ? "largecircle.fill.circle" : "circle"
    }

    private func toggle(_ label: String, on question: UserQuestion) {
        var picks = selected[question.id] ?? []
        if question.multiSelect {
            if picks.contains(label) {
                picks.remove(label)
            } else {
                picks.insert(label)
            }
        } else {
            picks = picks.contains(label) ? [] : [label]
        }
        selected[question.id] = picks
    }

    private func submit(force _: UserQuestion? = nil) {
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !canSubmit, !typed.isEmpty {
            model.client.answerQuestion(.chatAboutThis(typed))
            return
        }
        var answers: [String: [String]] = [:]
        for question in request.questions {
            let labels = Array(selected[question.id] ?? [])
            answers[question.question.isEmpty ? question.header : question.question] = labels
        }
        let missing = request.questions.contains { (selected[$0.id] ?? []).isEmpty }
        if !typed.isEmpty, missing {
            model.client.answerQuestion(.chatAboutThis(typed))
            return
        }
        model.client.answerQuestion(.accepted(answers: answers, partial: missing))
    }
}
