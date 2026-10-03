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

struct AskCoachView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var context: AskContext
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var answer: String?
    @State private var answerDecision: Decision?
    @State private var error: String?
    @State private var isAsking = false

    init(today: TodayDTO) {
        _context = State(initialValue: AskContext(today))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // The locked decision is always visible so the user sees the constraint
                    // the coach must respect — it can never be made more aggressive.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Score for \(StatusLineModel.formattedDay(context.date))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        DecisionChip(decision: answerDecision ?? context.decision)
                    }

                    SectionCard(title: "Ask the coach") {
                        TextField("e.g. Can I do a hard lifting session today?", text: $question, axis: .vertical)
                            .lineLimit(2 ... 5)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await ask() }
                        } label: {
                            if isAsking {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Ask").frame(maxWidth: .infinity)
                            }
                        }
                        .primaryAction()
                        .disabled(isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let answer {
                        SectionCard(title: "Coach") {
                            if let answerDecision {
                                DecisionChip(decision: answerDecision)
                            }
                            Text(answer).font(.body)
                        }
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Ask Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func ask() async {
        guard let client = settings.makeClient() else {
            error = APIError.notConfigured.localizedDescription
            return
        }
        isAsking = true
        error = nil
        defer { isAsking = false }
        do {
            let response = try await client.ask(question: question, date: context.date)
            answer = response.answer
            answerDecision = response.decision
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
