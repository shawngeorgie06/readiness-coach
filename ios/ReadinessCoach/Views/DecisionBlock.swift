import SwiftUI

/// Today's head: the readiness numeral and the locked decision. Renders
/// `today.readiness` and `today.decision` verbatim; the verdict is coloured by
/// the decision, never by the score, so an override can't look greener than
/// the call.
struct DecisionBlock: View {
    let today: TodayDTO
    let onScoreTap: () -> Void

    var body: some View {
        ScoreHead(
            score: today.readiness,
            verdict: today.decision.title,
            verdictColor: TodayHeadModel.verdictBand(today).color,
            meaning: "Readiness · \(today.decision.shortMeaning)",
            note: today.isSleepPending ? "Showing last night — you haven't slept yet tonight" : nil,
            noteSystemImage: "moon.zzz",
            accessibilityLabel: TodayHeadModel.accessibilityLabel(today),
            accessibilityHint: "Opens readiness history",
            action: onScoreTap
        )
    }
}

/// Pure presentation for Today's head, kept out of the view so it can be tested.
enum TodayHeadModel {
    static func verdictBand(_ today: TodayDTO) -> ScoreBand { today.decision.band }

    static func accessibilityLabel(_ today: TodayDTO) -> String {
        var label = "Readiness \(Int(today.readiness.rounded())) of 100. Decision: \(today.decision.title). \(today.decision.meaning)"
        if today.isSleepPending { label += " Showing last night; you haven't slept yet tonight." }
        return label
    }
}

extension Decision {
    /// One clause for the head, beside "Readiness ·".
    var shortMeaning: String {
        switch self {
        case .push: return "Recovered. A hard session is on the table."
        case .maintain: return "Train at moderate intensity, no max efforts."
        case .recover: return "Back off. Rest or light movement only."
        }
    }
}
