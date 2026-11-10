import Foundation
import Observation

struct CoachMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, coach }
    enum State: Equatable { case done, pending, failed }
    /// Why a coach message failed, so the notice can say something useful.
    enum Failure: Equatable {
        case network, unavailable, other

        init(_ error: Error) {
            var error = error
            if case let APIError.transport(inner) = error { error = inner }
            if error is URLError { self = .network; return }
            if case let APIError.http(status, code) = error, status == 503 || code == "coach_unavailable" {
                self = .unavailable
                return
            }
            self = .other
        }

        var message: String {
            switch self {
            case .network: return "Couldn't reach the coach. Check your connection."
            case .unavailable: return "The coach is unavailable right now."
            case .other: return "Something went wrong."
            }
        }
    }

    let id: UUID
    let role: Role
    /// Prose only; the server's trailing lock directive lives in `lockNote`.
    var text: String
    var state: State
    /// The server's lock paragraph, shown as a styled note.
    var lockNote: String?
    /// Set while `state == .failed`.
    var failure: Failure?

    init(id: UUID = UUID(), role: Role, text: String, state: State, lockNote: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.lockNote = lockNote
    }

    /// What the server originally said, used when sending history back.
    var wireText: String {
        guard let lockNote else { return text }
        return text.isEmpty ? lockNote : text + "\n\n" + lockNote
    }
}

/// In-memory only: nothing is stored on the device.
@MainActor @Observable
final class CoachConversation {
    static let messageCap = 20
    /// The server's limits on a question and on each history entry.
    static let maxQuestionLength = 1500
    static let maxHistoryEntryLength = 4000
    /// The server's limit on the whole history, in UTF-16 units.
    static let maxHistoryTotalLength = 16_000
    /// The exact directives `enforceAnswerDecisionLock` appends in advisorService.ts.
    static let lockDirectives = [
        "Locked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only.",
        "Locked decision: MAINTAIN. No PRs or maximal work; cap intensity at RPE 7.",
    ]

    typealias Send = @Sendable (String, String, [CoachTurnDTO]) async throws -> AskResponse

    let focus: CoachFocus
    private(set) var messages: [CoachMessage] = []
    /// True once an answer arrives for a different decision than the one this
    /// screen opened with: the numbers on screen are out of date.
    private(set) var numbersChanged = false

    @ObservationIgnored private let date: String
    @ObservationIgnored private let decision: Decision
    @ObservationIgnored private let send: Send
    /// Bumped by `reset` so a late answer for an old conversation is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failedRequest: (question: String, history: [CoachTurnDTO])?

    init(today: TodayDTO, focus: CoachFocus, send: @escaping Send) {
        self.focus = focus
        self.date = today.date
        self.decision = today.decision
        self.send = send
    }

    /// Failed pairs are pruned by the next ask, so they must not block that ask.
    var isAtCap: Bool { messages.filter { $0.state != .failed }.count >= Self.messageCap }
    var isPending: Bool { messages.contains { $0.state == .pending } }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= Self.maxQuestionLength, !isAtCap, !isPending else { return }
        failedRequest = nil
        // A failed pair never sits behind a newer question.
        messages.removeAll { $0.state == .failed }
        let history = historyTurns()
        messages.append(CoachMessage(role: .user, text: trimmed, state: .done))
        messages.append(CoachMessage(role: .coach, text: "", state: .pending))
        await deliver(question: trimmed, history: history)
    }

    func retry() async {
        guard !isPending, let failed = failedRequest,
              let coachIndex = messages.lastIndex(where: { $0.role == .coach && $0.state == .failed }),
              coachIndex > 0
        else { return }
        failedRequest = nil
        messages[coachIndex - 1].state = .done
        messages[coachIndex].state = .pending
        messages[coachIndex].failure = nil
        await deliver(question: failed.question, history: failed.history)
    }

    func reset() {
        generation += 1
        messages = []
        failedRequest = nil
        numbersChanged = false
    }

    private func historyTurns() -> [CoachTurnDTO] {
        var turns = completedTurns()
        // Drop the oldest exchange until the whole history fits the server's budget.
        while turns.reduce(0, { $0 + $1.content.utf16.count }) > Self.maxHistoryTotalLength {
            turns.removeFirst()
            while let first = turns.first, first.role != "user" { turns.removeFirst() }
        }
        return turns
    }

    private func completedTurns() -> [CoachTurnDTO] {
        messages.filter { $0.state == .done }.compactMap { message in
            let content = Self.capped(
                message.wireText.trimmingCharacters(in: .whitespacesAndNewlines),
                utf16Limit: Self.maxHistoryEntryLength
            )
            guard !content.isEmpty else { return nil }
            return CoachTurnDTO(role: message.role == .user ? "user" : "assistant", content: content)
        }
    }

    /// The server measures length in UTF-16 units (JavaScript `length`), so cap on that,
    /// cutting only at character boundaries.
    private static func capped(_ text: String, utf16Limit: Int) -> String {
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let units = text[index].utf16.count
            if used + units > utf16Limit { break }
            used += units
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    private func deliver(question: String, history: [CoachTurnDTO]) async {
        let startedIn = generation
        let outcome: Result<AskResponse, Error>
        do {
            outcome = .success(try await send(question, date, history))
        } catch {
            outcome = .failure(error)
        }
        guard startedIn == generation,
              let coachIndex = messages.lastIndex(where: { $0.role == .coach && $0.state == .pending })
        else { return }
        switch outcome {
        case let .success(response):
            if response.decision != decision { numbersChanged = true }
            let (prose, note) = Self.splitLockNote(response.answer)
            messages[coachIndex].text = prose
            messages[coachIndex].lockNote = note
            messages[coachIndex].state = .done
        case let .failure(error):
            messages[coachIndex].state = .failed
            messages[coachIndex].failure = CoachMessage.Failure(error)
            if coachIndex > 0 { messages[coachIndex - 1].state = .failed }
            failedRequest = (question, history)
        }
    }

    /// Splits off the lock note only when the answer ends with one of the
    /// server's exact directives as its own paragraph; a "Locked decision:" in
    /// the middle of the prose stays prose.
    static func splitLockNote(_ answer: String) -> (text: String, lockNote: String?) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        for directive in lockDirectives where trimmed.hasSuffix(directive) {
            let prose = String(trimmed.dropLast(directive.count))
            if prose.isEmpty { return ("", directive) }
            if prose.hasSuffix("\n\n") {
                return (prose.trimmingCharacters(in: .whitespacesAndNewlines), directive)
            }
        }
        return (trimmed, nil)
    }
}

/// The model sometimes answers with inline markdown (`**recover**`). Render the
/// inline styles and keep paragraph breaks, drop links, and fall back to the raw text if parsing fails.
enum CoachMarkdown {
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        // Model output is untrusted: never turn it into tappable links.
        parsed.link = nil
        return parsed
    }

    static func plain(_ text: String) -> String {
        String(render(text).characters)
    }
}
