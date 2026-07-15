import SwiftUI

struct AskCoachView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var question = ""
    @State private var answer: String?
    @State private var answerDecision: Decision?
    @State private var error: String?
    @State private var isAsking = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // The locked decision is always visible so the user sees the constraint
                    // the coach must respect — it can never be made more aggressive.
                    if let decision = sync.today?.decision {
                        HStack {
                            Text("Today is locked to")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            DecisionChip(decision: decision)
                        }
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
                        .buttonStyle(.borderedProminent)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .pageWidthLocked()
                .padding()
            }
            .verticalScrollLocked()
            .navigationTitle("Ask Coach")
            .task {
                if sync.today == nil { await sync.refreshToday(settings) }
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
            let response = try await client.ask(question: question)
            answer = response.answer
            answerDecision = response.decision
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
