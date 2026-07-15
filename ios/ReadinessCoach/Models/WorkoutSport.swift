import Foundation
import HealthKit

/// Maps HealthKit workout activity types ↔ API sport keys ↔ user-facing titles/symbols.
enum WorkoutSport {
    /// Canonical API key written during HealthKit sync.
    static func key(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairs"
        case .traditionalStrengthTraining: return "strength"
        case .functionalStrengthTraining: return "functional_strength"
        case .coreTraining: return "core"
        case .highIntensityIntervalTraining: return "hiit"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .flexibility: return "flexibility"
        case .cooldown: return "cooldown"
        case .mindAndBody: return "mind_body"
        case .crossTraining: return "cross_training"
        case .mixedMetabolicCardioTraining: return "mixed_cardio"
        case .jumpRope: return "jump_rope"
        case .dance, .danceInspiredTraining, .socialDance, .cardioDance: return "dance"
        case .boxing: return "boxing"
        case .kickboxing: return "kickboxing"
        case .martialArts: return "martial_arts"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .tennis: return "tennis"
        case .pickleball: return "pickleball"
        case .golf: return "golf"
        case .americanFootball: return "football"
        case .baseball: return "baseball"
        case .volleyball: return "volleyball"
        case .badminton: return "badminton"
        case .tableTennis: return "table_tennis"
        case .squash: return "squash"
        case .racquetball: return "racquetball"
        case .handball: return "handball"
        case .hockey: return "hockey"
        case .lacrosse: return "lacrosse"
        case .rugby: return "rugby"
        case .softball: return "softball"
        case .climbing: return "climbing"
        case .equestrianSports: return "equestrian"
        case .fishing: return "fishing"
        case .hunting: return "hunting"
        case .play: return "play"
        case .preparationAndRecovery: return "recovery"
        case .trackAndField: return "track"
        case .waterFitness, .waterPolo, .waterSports: return "water"
        case .wheelchairRunPace, .wheelchairWalkPace: return "wheelchair"
        case .other: return "other"
        default:
            return "hk_\(type.rawValue)"
        }
    }

    /// Prefer a Human HealthKit type; fall back to raw-value keys from older syncs.
    static func title(forKey key: String) -> String {
        let lowered = key.lowercased()
        if lowered.hasPrefix("hk_"), let raw = UInt(lowered.dropFirst(3)),
           let type = HKWorkoutActivityType(rawValue: raw) {
            return title(for: type)
        }
        return titleFromKey(lowered)
    }

    static func title(for type: HKWorkoutActivityType) -> String {
        titleFromKey(key(for: type))
    }

    private static func titleFromKey(_ key: String) -> String {
        switch key {
        case "running": return "Running"
        case "walking": return "Walking"
        case "cycling": return "Cycling"
        case "hiking": return "Hiking"
        case "swimming": return "Swimming"
        case "rowing": return "Rowing"
        case "elliptical": return "Elliptical"
        case "stairs", "stair_climbing": return "Stairs"
        case "strength", "traditional_strength": return "Strength Training"
        case "functional_strength": return "Functional Strength"
        case "core": return "Core Training"
        case "hiit": return "HIIT"
        case "yoga": return "Yoga"
        case "pilates": return "Pilates"
        case "flexibility": return "Flexibility"
        case "cooldown": return "Cooldown"
        case "mind_body": return "Mind & Body"
        case "cross_training": return "Cross Training"
        case "mixed_cardio": return "Mixed Cardio"
        case "jump_rope": return "Jump Rope"
        case "dance", "cardio_dance", "social_dance": return "Dance"
        case "boxing": return "Boxing"
        case "kickboxing": return "Kickboxing"
        case "martial_arts": return "Martial Arts"
        case "soccer": return "Soccer"
        case "basketball": return "Basketball"
        case "tennis": return "Tennis"
        case "pickleball": return "Pickleball"
        case "golf": return "Golf"
        case "football", "american_football": return "Football"
        case "baseball": return "Baseball"
        case "volleyball": return "Volleyball"
        case "badminton": return "Badminton"
        case "table_tennis": return "Table Tennis"
        case "squash": return "Squash"
        case "racquetball": return "Racquetball"
        case "handball": return "Handball"
        case "hockey": return "Hockey"
        case "lacrosse": return "Lacrosse"
        case "rugby": return "Rugby"
        case "softball": return "Softball"
        case "climbing": return "Climbing"
        case "equestrian": return "Equestrian"
        case "fishing": return "Fishing"
        case "hunting": return "Hunting"
        case "play": return "Play"
        case "recovery", "preparation_and_recovery": return "Recovery"
        case "track": return "Track & Field"
        case "water": return "Water Sports"
        case "wheelchair": return "Wheelchair"
        case "other", "hk_3000":
            return "Custom Workout"
        default:
            if key.hasPrefix("hk_") {
                return "Workout"
            }
            return key
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    static func symbolName(forKey key: String) -> String {
        let lowered = key.lowercased()
        let resolved: String = {
            if lowered.hasPrefix("hk_"), let raw = UInt(lowered.dropFirst(3)),
               let type = HKWorkoutActivityType(rawValue: raw) {
                return key(for: type)
            }
            return lowered
        }()

        switch resolved {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "hiking": return "figure.hiking"
        case "swimming": return "figure.pool.swim"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.elliptical"
        case "stairs", "stair_climbing": return "figure.stairs"
        case "strength", "traditional_strength", "functional_strength": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "hiit": return "flame.fill"
        case "yoga", "pilates", "flexibility", "cooldown", "mind_body", "recovery",
             "preparation_and_recovery":
            return "figure.mind.and.body"
        case "cross_training", "mixed_cardio": return "figure.mixed.cardio"
        case "jump_rope": return "figure.jump.rope"
        case "dance", "cardio_dance", "social_dance": return "figure.dance"
        case "boxing", "kickboxing", "martial_arts": return "figure.boxing"
        case "soccer": return "figure.soccer"
        case "basketball": return "figure.basketball"
        case "tennis", "pickleball", "squash", "racquetball", "badminton", "table_tennis":
            return "figure.tennis"
        case "golf": return "figure.golf"
        case "football", "american_football": return "figure.american.football"
        case "baseball", "softball": return "figure.baseball"
        case "volleyball": return "figure.volleyball"
        case "climbing": return "figure.climbing"
        case "water": return "drop.fill"
        case "wheelchair": return "figure.roll"
        default: return "figure.strengthtraining.traditional"
        }
    }

    static func detailBlurb(forKey key: String) -> String {
        let title = title(forKey: key)
        switch key.lowercased() {
        case "other", "hk_3000":
            return "Apple Health recorded this as a generic workout (no specific sport). Duration, heart rate, calories, and strain below still come from that session."
        default:
            return "Pulled from Apple Health as \(title). Heart rate, calories, and strain are measured for this session."
        }
    }
}
