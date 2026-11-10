import Foundation
import Observation

struct CoachMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, coach }
    enum State: Equatable { case done, pending, failed }

    let id: UUID
    let role: Role
    /// Prose only; a trailing "Locked decision:" paragraph lives in `lockNote`.
    var text: String
    var state: State
    /// The server's lock paragraph, shown as a styled note.
    var lockNote: String?

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
    private static let lockPrefix = "Locked decision:"

    typealias Send = (String, String, [CoachTurnDTO]) async throws -> String

    let focus: CoachFocus
    private(set) var messages: [CoachMessage] = []

    @ObservationIgnored private let date: String
    @ObservationIgnored private let send: Send
    /// Bumped by `reset` so a late answer for an old conversation is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failedRequest: (question: String, history: [CoachTurnDTO])?

    init(today: TodayDTO, focus: CoachFocus, send: @escaping Send) {
        self.focus = focus
        self.date = today.date
        self.send = send
    }

    var isAtCap: Bool { messages.count >= Self.messageCap }
    var isPending: Bool { messages.contains { $0.state == .pending } }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAtCap, !isPending else { return }
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
        await deliver(question: failed.question, history: failed.history)
    }

    func reset() {
        generation += 1
        messages = []
        failedRequest = nil
    }

    private func historyTurns() -> [CoachTurnDTO] {
        messages.filter { $0.state == .done }.map {
            CoachTurnDTO(role: $0.role == .user ? "user" : "assistant", content: $0.wireText)
        }
    }

    private func deliver(question: String, history: [CoachTurnDTO]) async {
        let startedIn = generation
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await send(question, date, history))
        } catch {
            outcome = .failure(error)
        }
        guard startedIn == generation,
              let coachIndex = messages.lastIndex(where: { $0.role == .coach && $0.state == .pending })
        else { return }
        switch outcome {
        case let .success(answer):
            let (prose, note) = Self.splitLockNote(answer)
            messages[coachIndex].text = prose
            messages[coachIndex].lockNote = note
            messages[coachIndex].state = .done
        case .failure:
            messages[coachIndex].state = .failed
            if coachIndex > 0 { messages[coachIndex - 1].state = .failed }
            failedRequest = (question, history)
        }
    }

    static func splitLockNote(_ answer: String) -> (text: String, lockNote: String?) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(lockPrefix) { return ("", trimmed) }
        guard let range = trimmed.range(of: "\n\n" + lockPrefix, options: .backwards) else {
            return (trimmed, nil)
        }
        let prose = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, note)
    }
}
