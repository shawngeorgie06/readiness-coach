import SwiftUI

/// A metric that has a server baseline on `/v1/today`. Formatting lives here so
/// the vitals strip and comparison rows say the same thing.
enum VitalMetric: CaseIterable, Identifiable {
    case hrv, restingHr, sleepHours, load7d

    var id: Self { self }

    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHr: return "Resting HR"
        case .sleepHours: return "Sleep"
        case .load7d: return "7-day load"
        }
    }

    var spokenTitle: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHr: return "Resting heart rate"
        case .sleepHours: return "Sleep"
        case .load7d: return "Seven-day load"
        }
    }

    /// Unit shown beside the value; nil when the value carries its own (sleep).
    var unit: String? {
        switch self {
        case .hrv: return "ms"
        case .restingHr: return "bpm"
        case .sleepHours: return nil
        case .load7d: return "strain"
        }
    }

    private var spokenUnit: String {
        switch self {
        case .hrv: return " milliseconds"
        case .restingHr: return " beats per minute"
        case .sleepHours: return ""
        case .load7d: return " strain"
        }
    }

    /// The sleep band is centred on the nightly target, not the 30-day average.
    var bandName: String { self == .sleepHours ? "target" : "normal" }

    func baseline(in baselines: TodayBaselinesDTO) -> MetricBaselineDTO {
        switch self {
        case .hrv: return baselines.hrv
        case .restingHr: return baselines.restingHr
        case .sleepHours: return baselines.sleepHours
        case .load7d: return baselines.load7d
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .hrv, .restingHr: return "\(Int(value.rounded()))"
        case .sleepHours: return DurationFormat.short(value)
        case .load7d: return String(format: "%.1f", value)
        }
    }

    func spoken(_ value: Double) -> String {
        switch self {
        case .sleepHours: return DurationFormat.long(value)
        default: return format(value) + spokenUnit
        }
    }

    /// Signed change with its unit, e.g. "+6 ms", "−2 bpm", "+42m", "0.0".
    func formatDelta(_ delta: Double) -> String {
        switch self {
        case .hrv, .restingHr:
            let rounded = Int(delta.rounded())
            return "\(Self.sign(Double(rounded)))\(abs(rounded)) \(unit ?? "")"
        case .sleepHours:
            let minutes = Int((delta * 60).rounded())
            return Self.sign(Double(minutes)) + DurationFormat.short(Double(abs(minutes)) / 60)
        case .load7d:
            let tenths = (delta * 10).rounded() / 10
            return Self.sign(tenths) + String(format: "%.1f", abs(tenths))
        }
    }

    func spokenDelta(_ delta: Double) -> String {
        let magnitude = abs(delta)
        let word = delta > 0 ? "up" : "down"
        switch self {
        case .sleepHours:
            let minutes = Int((magnitude * 60).rounded())
            return minutes == 0 ? "no change" : "\(word) \(DurationFormat.long(Double(minutes) / 60))"
        default:
            let text = format(magnitude)
            return Double(text) == 0 ? "no change" : "\(word) \(text)\(spokenUnit)"
        }
    }

    private static func sign(_ value: Double) -> String {
        value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
    }
}

/// Today's value against the server's 30-day normal and neutral band. Pure, so
/// arrow direction and colour are unit-tested. Nothing here is computed from a
/// client-side average: no band means no arrow.
struct MetricComparison: Equatable, Identifiable {
    enum Position: Equatable { case below, within, above }

    /// What the comparison means for this metric, not which way it moved.
    enum Tone: Equatable {
        case good, bad
        /// Inside the neutral band, or no band to judge against.
        case neutral
        /// Outside the band on a metric with no good direction (load).
        case notable

        var color: Color {
            switch self {
            case .good: return Palette.success
            case .bad: return Palette.danger
            case .neutral: return Palette.textTertiary
            case .notable: return Palette.textPrimary
            }
        }
    }

    let metric: VitalMetric
    /// Nil when there's no data for today.
    let today: Double?
    /// Nil when the server has too few days to form a normal.
    let normal: Double?
    let position: Position?
    let tone: Tone
    /// 14 daily values, oldest first; nil days stay nil.
    let recent: [Double?]

    var id: VitalMetric { metric }

    init(metric: VitalMetric, baseline: MetricBaselineDTO) {
        self.metric = metric
        today = baseline.today
        normal = baseline.baseline30d
        recent = baseline.recent14d
        if let today = baseline.today, baseline.baseline30d != nil, let band = baseline.neutralBand {
            let position: Position = today < band.low ? .below : (today > band.high ? .above : .within)
            self.position = position
            tone = Self.tone(position, goodDirection: baseline.goodDirection)
        } else {
            position = nil
            tone = .neutral
        }
    }

    /// Every metric in display order, or nil when the server sent no baselines
    /// (older production builds): callers hide the section rather than invent one.
    static func all(from baselines: TodayBaselinesDTO?) -> [MetricComparison]? {
        guard let baselines else { return nil }
        return VitalMetric.allCases.map { MetricComparison(metric: $0, baseline: $0.baseline(in: baselines)) }
    }

    static func tone(_ position: Position, goodDirection: String) -> Tone {
        switch (position, goodDirection) {
        case (.within, _): return .neutral
        case (.above, "up"), (.below, "down"): return .good
        case (.above, "down"), (.below, "up"): return .bad
        default: return .notable
        }
    }

    var todayText: String { today.map(metric.format) ?? "—" }
    var normalText: String? { normal.map(metric.format) }

    /// Change from the 30-day normal; nil without both values.
    var delta: Double? {
        guard let today, let normal else { return nil }
        return today - normal
    }

    var deltaText: String? { delta.map(metric.formatDelta) }

    /// Arrow follows band position, never colour alone. Nil inside the band or
    /// when there is no band to judge against.
    var arrowSymbol: String? {
        switch position {
        case .above: return "arrowtriangle.up.fill"
        case .below: return "arrowtriangle.down.fill"
        case .within, nil: return nil
        }
    }

    var summary: String {
        guard today != nil else { return "No data today" }
        guard let position else { return normal == nil ? "Not enough data yet" : "No range yet" }
        switch position {
        case .below: return "Below \(metric.bandName)"
        case .within: return metric == .sleepHours ? "On target" : "Normal"
        case .above: return "Above \(metric.bandName)"
        }
    }

    /// One short line for a narrow column: the signed change when it agrees with
    /// the arrow, otherwise the band word. (Sleep's band sits on the target, so
    /// a night can beat the average and still fall short of the target.)
    var compactText: String {
        guard let position, let delta, let deltaText else { return summary }
        let agrees: Bool
        switch position {
        case .above: agrees = delta > 0
        case .below: agrees = delta < 0
        case .within: agrees = true
        }
        return agrees ? deltaText : summary
    }

    var accessibilityText: String {
        guard let today else { return "\(metric.spokenTitle): no data today." }
        var parts = ["\(metric.spokenTitle) \(metric.spoken(today))"]
        if let normal, let delta {
            parts.append("30-day normal \(metric.spoken(normal)), \(metric.spokenDelta(delta))")
        }
        parts.append(summary)
        return parts.joined(separator: ". ") + "."
    }
}

/// Splits a daily series into runs of consecutive values so missing days draw
/// as gaps, never as interpolated lines.
enum SparklineGeometry {
    struct Point: Equatable {
        let index: Int
        let value: Double
    }

    static func runs(_ values: [Double?]) -> [[Point]] {
        var runs: [[Point]] = []
        var current: [Point] = []
        for (index, value) in values.enumerated() {
            if let value, value.isFinite {
                current.append(Point(index: index, value: value))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Min and max of the present values, widened when flat so a steady series
    /// draws as a centred line.
    static func domain(_ values: [Double?]) -> ClosedRange<Double>? {
        let present = values.compactMap { $0 }.filter(\.isFinite)
        guard let low = present.min(), let high = present.max() else { return nil }
        if high - low < .ulpOfOne { return (low - 1)...(high + 1) }
        return low...high
    }
}
