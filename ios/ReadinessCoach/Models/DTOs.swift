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

struct PillarScore: Codable, Hashable {
    let score: Double
    let drivers: [String]
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
    let advisor: AdvisorNote

    var isLowConfidence: Bool { confidence == "low" }
}

// MARK: - Detail tabs

struct SleepDetailResponse: Codable {
    let days: Int
    let data: [SleepDay]
}

struct SleepDay: Codable, Identifiable {
    let date: String
    let durationHours: Double
    let restorativeHours: Double
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
    let calories: Double?
    let strain: Double
}

struct BodyResponse: Codable {
    let days: Int
    let data: [BodySample]
}

struct BodySample: Codable, Identifiable {
    let type: String
    let startAt: String
    let endAt: String
    let value: Double?
    let unit: String?
    var id: String { type + startAt }
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
