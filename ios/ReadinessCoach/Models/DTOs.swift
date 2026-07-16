import Foundation

/// The locked readiness decision. The score determines this deterministically on
/// the backend; the LLM advisor can never make it more aggressive.
enum Decision: String, Codable, CaseIterable {
    case push
    case maintain
    case recover

    var title: String {
        switch self {
        case .push: return "Push"
        case .maintain: return "Maintain"
        case .recover: return "Recover"
        }
    }
}

// MARK: - Today

struct Driver: Codable, Hashable {
    let text: String
    let detail: String?
}

struct PillarScore: Codable, Hashable {
    let score: Double
    let drivers: [Driver]
}

struct Pillars: Codable {
    let sleep: PillarScore
    let recovery: PillarScore
    let load: PillarScore
}

struct AdvisorNote: Codable {
    let decision: Decision
    let why: [String]
    let prescription: String
    let ifIgnored: String
    /// "llm" when written by the cloud model, "template" when generated locally.
    let source: String
}

struct TodayDTO: Codable {
    let date: String
    let readiness: Double
    let decision: Decision
    let calibrating: Bool
    let pillars: Pillars
    let overridesApplied: [String]
    /// "high" when all core signals are present, otherwise "low".
    let confidence: String
    let missing: [String]
    /// True when tonight's night hasn't happened yet, so this score reflects the
    /// last completed night. Optional so older cached payloads still decode.
    let sleepPending: Bool?
    let advisor: AdvisorNote

    var isLowConfidence: Bool { confidence == "low" }
    /// Whether the app should show "Haven't slept yet" for the sleep tile.
    var isSleepPending: Bool { sleepPending ?? false }
}

// MARK: - Detail tabs

struct SleepDetailResponse: Codable {
    let days: Int
    let data: [SleepDay]
}

struct SleepStages: Codable, Hashable {
    let deep: Double
    let rem: Double
    let core: Double
    let awake: Double
}

struct SleepSegment: Codable, Hashable, Identifiable {
    let stage: String
    let startAt: String
    let endAt: String
    let hours: Double
    var id: String { "\(stage)-\(startAt)-\(endAt)" }
}

struct SleepDay: Codable, Identifiable {
    let date: String
    let durationHours: Double
    let restorativeHours: Double
    let sleepStart: String?
    let sleepEnd: String?
    let stages: SleepStages
    /// Ordered stage blocks for the night hypnogram (may be empty on older servers).
    let timeline: [SleepSegment]?
    var id: String { date }
}

struct TrainResponse: Codable {
    let days: Int
    let data: [WorkoutDTO]
}

struct WorkoutDTO: Codable, Identifiable {
    let id: String
    let sport: String
    let startAt: String
    let endAt: String
    let durationMin: Double
    let avgHrBpm: Double?
    let maxHrBpm: Double?
    let calories: Double?
    let strain: Double
    /// Estimated minutes in HR zones Z1–Z5, or nil when no HR was recorded.
    let hrZonesMin: [Double]?
}

struct BodyResponse: Codable {
    let days: Int
    let daily: [BodyDaily]
}

/// Per-day min/avg/max for a single metric type (hrv_sdnn, resting_heart_rate, heart_rate).
struct BodyDaily: Codable, Identifiable {
    let type: String
    let date: String
    let min: Double
    let avg: Double
    let max: Double
    let count: Int
    var id: String { type + date }
}

// MARK: - Readiness history

struct ReadinessHistoryResponse: Codable {
    let days: Int
    let data: [ReadinessPoint]
}

struct ReadinessPoint: Codable, Identifiable {
    let date: String
    let readiness: Double
    let decision: Decision
    let sleepScore: Double
    let recoveryScore: Double
    let loadScore: Double
    let calibrating: Bool
    var id: String { date }
}

// MARK: - Ask Coach

struct AskRequest: Codable {
    let userId: String
    let question: String
    let date: String?
}

struct AskResponse: Codable {
    let decision: Decision
    let answer: String
}

// MARK: - Sync (request payload posted to POST /v1/sync)

struct SyncSample: Codable {
    let hkUuid: String
    let type: String
    let startAt: String
    let endAt: String
    let value: Double?
    let unit: String?
    let metadata: [String: String]?
}

struct SyncWorkout: Codable {
    let hkUuid: String
    let sport: String
    let startAt: String
    let endAt: String
    let durationMin: Double
    let avgHrBpm: Double?
    let calories: Double?
}

struct SyncPayload: Codable {
    let userId: String
    let samples: [SyncSample]
    let workouts: [SyncWorkout]

    var isEmpty: Bool { samples.isEmpty && workouts.isEmpty }
}

struct SyncResult: Codable {
    let ok: Bool
    let samples: Int
    let workouts: Int
}
