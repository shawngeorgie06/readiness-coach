import Foundation

/// Canned copy for the coach screen. Numbers come from `TodayDTO` only.
enum CoachPrompts {
    /// The weakest pillar, when it is below 50 and at least 15 points under the
    /// next lowest. Otherwise nil, and the copy speaks to the decision.
    static func notablyLowPillar(_ today: TodayDTO) -> (pillar: Pillar, score: Int)? {
        let scored = Pillar.allCases
            .map { ($0, $0.score(in: today.pillars).score) }
            .sorted { $0.1 < $1.1 }
        guard scored.count >= 2, scored[0].1 < 50, scored[1].1 - scored[0].1 >= 15 else { return nil }
        return (scored[0].0, Int(scored[0].1.rounded()))
    }

    static func openingLine(_ today: TodayDTO) -> String {
        if let low = notablyLowPillar(today) {
            return "Your \(low.pillar.title.lowercased()) is at \(low.score), well below your other pillars. Ask me what is behind it."
        }
        switch today.decision {
        case .push: return "You are primed to push today. Ask me how to spend it."
        case .maintain: return "A steady day. Ask me what to do with it."
        case .recover: return "Your body is asking for a lighter day. Ask me why."
        }
    }

    /// Exactly two tappable questions; the view adds "Ask something…".
    static func suggestions(_ today: TodayDTO) -> [String] {
        if let low = notablyLowPillar(today) {
            return ["Why is my \(low.pillar.title.lowercased()) low?", "What should I do about it today?"]
        }
        switch today.decision {
        case .push: return ["How hard can I train today?", "What is driving my readiness?"]
        case .maintain: return ["What should I do today?", "What is holding me back from a push day?"]
        case .recover: return ["Why am I told to recover?", "What can I do instead of training?"]
        }
    }

    static func autoQuestion(for focus: CoachFocus, today: TodayDTO) -> String {
        switch focus {
        case .readiness:
            return "Why is my readiness \(Int(today.readiness.rounded())) today?"
        case let .pillar(pillar):
            return "Why is my \(pillar.title.lowercased()) \(Int(pillar.score(in: today.pillars).score.rounded())) today?"
        }
    }

    /// Two or three follow-ups shown after an answer.
    static func followUps(for focus: CoachFocus, decision: Decision) -> [String] {
        switch focus {
        case .readiness:
            switch decision {
            case .push: return ["What should I train today?", "What could change this tomorrow?"]
            case .maintain: return ["What would move me to a push day?", "What should I do today?"]
            case .recover: return ["What can I do today instead?", "How do I bounce back faster?", "When will I be ready to push?"]
            }
        case let .pillar(pillar):
            let name = pillar.title.lowercased()
            return ["How do I improve my \(name)?", "How does \(name) affect today's plan?"]
        }
    }
}
