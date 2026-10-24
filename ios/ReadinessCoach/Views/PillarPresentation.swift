import SwiftUI

// Pure presentation models for the pillar tabs. No views, so they are unit
// tested; every value comes from the server response, nothing is invented.

// MARK: - Recovery

/// The days of a Recovery metric that fall inside the trailing window.
enum RecoveryWindow {
    /// Points from `days` calendar days ending on `end` (inclusive), oldest first.
    static func points(_ metric: BodySeries.Metric, days: Int, endingOn end: Date, calendar: Calendar = .current) -> [BodySeries.Point] {
        let last = calendar.startOfDay(for: end)
        guard days > 0, let first = calendar.date(byAdding: .day, value: -(days - 1), to: last) else { return [] }
        return metric.points.filter { $0.date >= first && $0.date <= last }
    }

    /// A y-domain that fits the values and the normal line with some air.
    static func domain(_ values: [Double], normal: Double?) -> ClosedRange<Double>? {
        let all = values + (normal.map { [$0] } ?? [])
        guard let low = all.min(), let high = all.max() else { return nil }
        let pad = max((high - low) * 0.15, 2)
        return max(0, low - pad)...(high + pad)
    }
}

/// One line of the "Last 7 days" list. A day without a reading stays in the
/// list with no value, so gaps are visible rather than skipped.
struct RecoveryDayRow: Identifiable, Equatable {
    let date: Date
    let hrv: Double?
    let restingHr: Double?
    var id: Date { date }

    /// Newest first, seven calendar days ending on `end`.
    static func lastWeek(_ series: BodySeries, endingOn end: Date, calendar: Calendar = .current) -> [RecoveryDayRow] {
        let today = calendar.startOfDay(for: end)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return RecoveryDayRow(date: day, hrv: series.hrv.row(on: day)?.avg, restingHr: series.rhr.row(on: day)?.avg)
        }
    }
}

// MARK: - Sleep

enum SleepStage: String, CaseIterable, Identifiable {
    case awake, rem, core, deep

    var id: Self { self }

    /// Backend stage names are "deep" | "rem" | "core" | "awake".
    init?(server name: String) {
        self.init(rawValue: name.lowercased())
    }

    var title: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    /// Lighter means lighter sleep; Awake is the only warm colour. Marks only:
    /// stage names are always printed in white or grey beside them.
    var color: Color {
        switch self {
        case .awake: return Color(hex: 0xF5A35C)
        case .rem: return Color(hex: 0x7DD3FC)
        case .core: return Color(hex: 0x3F7FE8)
        case .deep: return Color(hex: 0x6A4BD8)
        }
    }

    func hours(in stages: SleepStages) -> Double {
        switch self {
        case .awake: return stages.awake
        case .rem: return stages.rem
        case .core: return stages.core
        case .deep: return stages.deep
        }
    }

    /// Breakdown order: deepest first.
    static let breakdownOrder: [SleepStage] = [.deep, .rem, .core, .awake]
}

/// One stage's share of a night.
struct SleepStageShare: Identifiable, Equatable {
    let stage: SleepStage
    let hours: Double
    let fraction: Double
    var id: SleepStage { stage }

    /// All four stages in breakdown order, or none when the night has no
    /// stage data (so a zero night never draws an empty bar).
    static func shares(_ stages: SleepStages) -> [SleepStageShare] {
        let hours = SleepStage.breakdownOrder.map { max(0, $0.hours(in: stages)) }
        let total = hours.reduce(0, +)
        guard total > 0 else { return [] }
        return zip(SleepStage.breakdownOrder, hours).map { SleepStageShare(stage: $0, hours: $1, fraction: $1 / total) }
    }
}

/// A hypnogram block with real instants.
struct HypnogramSegment: Identifiable, Equatable {
    let stage: SleepStage
    let start: Date
    let end: Date
    var id: String { "\(stage.rawValue)-\(start.timeIntervalSince1970)" }

    /// Parsed, time-ordered blocks. Unknown stages, unparseable times and
    /// empty blocks are dropped.
    static func segments(_ timeline: [SleepSegment]?) -> [HypnogramSegment] {
        (timeline ?? []).compactMap { segment in
            guard let stage = SleepStage(server: segment.stage),
                  let start = PillarTime.parse(segment.startAt),
                  let end = PillarTime.parse(segment.endAt),
                  end > start
            else { return nil }
            return HypnogramSegment(stage: stage, start: start, end: end)
        }
        .sorted { $0.start < $1.start }
    }
}

/// Which night the Sleep tab shows.
enum NightSelection {
    /// The chosen night when it is in range, otherwise the latest night.
    static func night(_ id: String?, in nights: [SleepDay]) -> SleepDay? {
        if let id, let hit = nights.first(where: { $0.id == id }) { return hit }
        return nights.last
    }

    /// Keeps a choice across range changes while that night is still shown;
    /// nil (meaning "latest") once it isn't.
    static func keep(_ id: String?, in nights: [SleepDay]) -> String? {
        guard let id, nights.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The night `offset` steps from the shown one, clamped to the range.
    static func step(from id: String?, by offset: Int, in nights: [SleepDay]) -> String? {
        guard let current = night(id, in: nights),
              let index = nights.firstIndex(where: { $0.id == current.id })
        else { return nil }
        return nights[min(max(index + offset, 0), nights.count - 1)].id
    }

    /// Mean duration of the nights shown, labelled as a range average.
    static func averageHours<S: Collection>(_ nights: S) -> Double? where S.Element == SleepDay {
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0) { $0 + $1.durationHours } / Double(nights.count)
    }
}

/// Names the night behind Sleep's "Compared with normal" row. That row is
/// the server's comparison for today's score; other nights have none, so a
/// different selection is called out rather than compared client-side.
enum SleepComparisonSource {
    static func caption(scoreDate: String, selectedNight: String?, currentDay: String) -> String {
        let day = short(scoreDate)
        var text = scoreDate == currentDay
            ? "Last night (\(day)), from today's score."
            : "Night of \(day), from your \(day) score."
        if let selectedNight, selectedNight != scoreDate {
            text += " The selected night (\(short(selectedNight))) isn't compared here."
        }
        return text
    }

    private static func short(_ day: String) -> String {
        ChartDate.parse(day)?.formatted(.dateTime.month(.abbreviated).day()) ?? day
    }
}

// MARK: - Train

/// One day of the Train week bars. A day with no sessions is a rest day.
struct TrainDay: Identifiable, Equatable {
    let date: Date
    let strain: Double
    let minutes: Double
    let sessions: Int
    var id: Date { date }
    var isRest: Bool { sessions == 0 }
}

/// Train's "Compared with normal" row is a daily average; the head's figure
/// is a 7-day total, so the row says which it is.
enum TrainLoadCopy {
    static let dailyAverageNote = "Average strain per day over the last 7 days, against your 28-day daily average. This isn't the 7-day total."
}

/// Workouts under one day label, newest first.
struct WorkoutDayGroup: Identifiable {
    /// Local start of day; nil for workouts whose start time didn't parse.
    let day: Date?
    let title: String
    let workouts: [WorkoutDTO]
    var id: String { day.map { "\($0.timeIntervalSince1970)" } ?? "undated" }

    /// Groups newest-first workouts by local calendar day.
    static func groups(_ workouts: [WorkoutDTO], now: Date = Date(), calendar: Calendar = .current) -> [WorkoutDayGroup] {
        var order: [Date] = []
        var byDay: [Date: [WorkoutDTO]] = [:]
        var undated: [WorkoutDTO] = []
        for workout in workouts {
            guard let start = PillarTime.parse(workout.startAt) else {
                undated.append(workout)
                continue
            }
            let day = calendar.startOfDay(for: start)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(workout)
        }
        var groups = order.sorted(by: >).map { day in
            WorkoutDayGroup(day: day, title: title(for: day, now: now, calendar: calendar), workouts: byDay[day] ?? [])
        }
        if !undated.isEmpty {
            groups.append(WorkoutDayGroup(day: nil, title: "Date unknown", workouts: undated))
        }
        return groups
    }

    static func title(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    /// The same groups keeping only workouts that pass `include`.
    static func filter(_ groups: [WorkoutDayGroup], _ include: (WorkoutDTO) -> Bool) -> [WorkoutDayGroup] {
        groups.compactMap { group in
            let kept = group.workouts.filter(include)
            return kept.isEmpty ? nil : WorkoutDayGroup(day: group.day, title: group.title, workouts: kept)
        }
    }
}

/// One heart-rate zone of a workout.
struct HRZoneSegment: Identifiable, Equatable {
    let index: Int
    let minutes: Double
    let fraction: Double
    var id: Int { index }

    static let names = ["Easy", "Light", "Moderate", "Hard", "Max"]

    /// The server buckets each heart-rate sample by its share of a fixed
    /// 190 bpm maximum; it doesn't know the user's own max or resting rate.
    static let estimateNote = "Estimated from heart-rate samples as a share of an assumed 190 bpm maximum: under 60% is Z1, 90% and up is Z5. Your own maximum and resting heart rate aren't used."

    var name: String { Self.names[min(index, Self.names.count - 1)] }
    var label: String { "Z\(index + 1) \(name)" }

    /// Zones with time in them, or none when the workout recorded no heart
    /// rate or every zone is empty.
    static func segments(_ zones: [Double]?) -> [HRZoneSegment] {
        let minutes = (zones ?? []).map { max(0, $0) }
        let total = minutes.reduce(0, +)
        guard total > 0 else { return [] }
        return minutes.enumerated().compactMap { index, value in
            value > 0 ? HRZoneSegment(index: index, minutes: value, fraction: value / total) : nil
        }
    }
}
