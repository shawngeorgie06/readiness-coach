import Foundation

enum TrendDirection { case up, down, flat }

/// Which way is healthy for a metric.
enum GoodDirection { case higher, lower }

struct MetricTrend {
    let direction: TrendDirection
    let recentAvg: Double
    /// Ready-to-print verdict, e.g. "trending up vs last week, a good sign".
    let phrase: String
}

/// Trend of a daily series: average of the last 7 values vs the prior 7.
/// `values` must be sorted oldest→newest, one value per day.
/// Returns nil when there is not enough data to judge a trend.
func metricTrend(values: [Double], goodDirection: GoodDirection, threshold: Double) -> MetricTrend? {
    let recent = Array(values.suffix(7))
    let prior = Array(values.dropLast(recent.count).suffix(7))
    guard recent.count >= 3, !prior.isEmpty else { return nil }

    let recentAvg = recent.reduce(0, +) / Double(recent.count)
    let priorAvg = prior.reduce(0, +) / Double(prior.count)
    let delta = recentAvg - priorAvg

    let direction: TrendDirection = abs(delta) < threshold ? .flat : (delta > 0 ? .up : .down)
    return MetricTrend(direction: direction, recentAvg: recentAvg, phrase: phrase(direction, goodDirection))
}

private func phrase(_ direction: TrendDirection, _ good: GoodDirection) -> String {
    switch (direction, good) {
    case (.flat, _):        return "holding steady vs last week"
    case (.up, .higher):    return "trending up vs last week, a good sign"
    case (.down, .higher):  return "trending down vs last week, worth watching"
    case (.up, .lower):     return "creeping up vs last week, worth watching"
    case (.down, .lower):   return "trending down vs last week, a good sign"
    }
}
