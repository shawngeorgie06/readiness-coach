import SwiftUI

/// Freeze the dated snapshot so a refresh cannot change a question's context.
struct AskContext {
    let date: String
    let decision: Decision

    init(_ today: TodayDTO) {
        date = today.date
        decision = today.decision
    }
}

/// Ask the coach about the locked call. The call sits at the top in its
/// decision colour; the coach's answer is AI-generated and can only explain
/// it, never make it more aggressive.
struct AskCoachView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var context: AskContext
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var askedQuestion: String?
    @State private var answer: String?
    @State private var answerDecision: Decision?
    @State private var error: String?
    @State private var isAsking = false
    @State private var askTask: Task<Void, Never>?
    @FocusState private var questionFocused: Bool

    init(today: TodayDTO) {
        _context = State(initialValue: AskContext(today))
    }

    private var trimmedQuestion: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    lockedCall
                    questionField
                    if let askedQuestion, isAsking || answer != nil || error != nil {
                        conversation(askedQuestion)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheetSurface()
            .navigationTitle("Ask Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onDisappear { askTask?.cancel() }
        }
    }

    // MARK: Locked call

    /// The locked decision is always visible so the user sees the constraint
    /// the coach must respect.
    private var lockedCall: some View {
        let decision = answerDecision ?? context.decision
        return VStack(alignment: .leading, spacing: 6) {
            Text("Score for \(StatusLineModel.formattedDay(context.date))")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textTertiary)
                Text(decision.title.uppercased())
                    .font(Typeface.verdict)
                    .tracking(Typeface.verdictTracking)
                    .foregroundStyle(decision.band.color)
            }
            Text(decision.meaning)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The coach explains this call; it can't make it more aggressive.")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked decision for \(StatusLineModel.formattedDay(context.date)): \(decision.title). \(decision.meaning) The coach explains this call; it can't make it more aggressive.")
    }

    // MARK: Question

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your question")
                .font(Typeface.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityHidden(true)
            TextField("e.g. Can I do a hard lifting session today?", text: $question, axis: .vertical)
                .lineLimit(2 ... 6)
                .focused($questionFocused)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: Space.target)
                .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Your question for the coach")
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isAsking { ProgressView().tint(Palette.canvas) }
                    Text(isAsking ? "Asking…" : "Ask")
                }
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .primaryAction()
            .disabled(isAsking || trimmedQuestion.isEmpty)
        }
    }

    // MARK: Conversation

    private func conversation(_ asked: String) -> some View {
        OpenSection("Coach") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You asked")
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                    Text(asked)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if isAsking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("The coach is answering…")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(minHeight: Space.target)
                    .accessibilityElement(children: .combine)
                } else if let error {
                    InlineNotice(
                        title: "Couldn't get an answer",
                        message: error,
                        actionTitle: "Try again",
                        action: retry
                    )
                } else if let answer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(answer)
                            .font(.body)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Label("AI-generated · can't change the locked call", systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill((answerDecision ?? context.decision).band.color)
                            .frame(width: 2)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Actions

    private func submit() {
        let text = trimmedQuestion
        guard !text.isEmpty, !isAsking else { return }
        questionFocused = false
        start(text)
    }

    private func retry() {
        guard let askedQuestion, !isAsking else { return }
        start(askedQuestion)
    }

    private func start(_ text: String) {
        askedQuestion = text
        askTask = Task { await ask(text) }
    }

    private func ask(_ text: String) async {
        guard let client = settings.makeClient() else {
            answer = nil
            error = APIError.notConfigured.localizedDescription
            return
        }
        isAsking = true
        error = nil
        answer = nil
        defer { isAsking = false }
        do {
            let response = try await client.ask(question: text, date: context.date)
            guard !Task.isCancelled else { return }
            answer = response.answer
            answerDecision = response.decision
            if question.trimmingCharacters(in: .whitespacesAndNewlines) == text { question = "" }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
