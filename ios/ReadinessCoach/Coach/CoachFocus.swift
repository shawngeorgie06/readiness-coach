import Foundation

/// What the coach screen is about: the overall score or one pillar.
enum CoachFocus: Hashable {
    case readiness
    case pillar(Pillar)
}

/// One metric behind a pillar, with today's server-side comparison.
struct CoachFactor: Equatable, Identifiable {
    let metric: VitalMetric
    let comparison: MetricComparison

    var id: VitalMetric { metric }
}

/// Everything the coach header shows, read from `TodayDTO` only. Without
/// baselines there are no factors, so nothing is invented.
struct CoachFocusModel: Equatable {
    let title: String
    let score: Int
    let weightLabel: String?
    let factors: [CoachFactor]
    let fallbackDrivers: [String]
    let trend: [Double?]
    let pillarScores: [(Pillar, Int)]

    init(focus: CoachFocus, today: TodayDTO) {
        switch focus {
        case .readiness:
            title = "Readiness"
            score = Int(today.readiness.rounded())
            weightLabel = nil
            factors = []
            fallbackDrivers = []
            pillarScores = Pillar.allCases.map { ($0, Int($0.score(in: today.pillars).score.rounded())) }
        case let .pillar(pillar):
            let pillarScore = pillar.score(in: today.pillars)
            title = pillar.title
            score = Int(pillarScore.score.rounded())
            weightLabel = "\(pillar.weightPercent)% of readiness"
            fallbackDrivers = pillarScore.drivers.map(\.text)
            pillarScores = []
            let metrics: [VitalMetric]
            switch pillar {
            case .recovery: metrics = [.hrv, .restingHr]
            case .sleep: metrics = [.sleepHours]
            case .load: metrics = [.load7d]
            }
            let all = MetricComparison.all(from: today.baselines) ?? []
            factors = metrics.compactMap { metric in
                guard let comparison = all.first(where: { $0.metric == metric }), comparison.today != nil else {
                    return nil
                }
                return CoachFactor(metric: metric, comparison: comparison)
            }
        }
        trend = factors.first.map { Array($0.comparison.recent.suffix(7)) } ?? []
    }

    static func == (lhs: CoachFocusModel, rhs: CoachFocusModel) -> Bool {
        lhs.title == rhs.title && lhs.score == rhs.score && lhs.weightLabel == rhs.weightLabel
            && lhs.factors == rhs.factors && lhs.fallbackDrivers == rhs.fallbackDrivers
            && lhs.trend == rhs.trend
            && lhs.pillarScores.map { "\($0.0)\($0.1)" } == rhs.pillarScores.map { "\($0.0)\($0.1)" }
    }
}
