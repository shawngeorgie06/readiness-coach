import Foundation
import HealthKit

/// Maps HealthKit activity types to API keys + display titles/symbols.
enum WorkoutSport {
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
        case .dance: return "dance"
        case .boxing: return "boxing"
        case .kickboxing: return "kickboxing"
        case .martialArts: return "martial_arts"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .tennis: return "tennis"
        case .golf: return "golf"
        case .climbing: return "climbing"
        case .preparationAndRecovery: return "recovery"
        case .other: return "other"
        default: return "hk_\(type.rawValue)"
        }
    }

    static func title(forKey key: String) -> String {
        let lowered = key.lowercased()
        if lowered.hasPrefix("hk_"), let raw = UInt(lowered.dropFirst(3)),
           let type = HKWorkoutActivityType(rawValue: raw) {
            return titleFromKey(Self.key(for: type))
        }
        return titleFromKey(lowered)
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
        case "dance": return "Dance"
        case "boxing": return "Boxing"
        case "kickboxing": return "Kickboxing"
        case "martial_arts": return "Martial Arts"
        case "soccer": return "Soccer"
        case "basketball": return "Basketball"
        case "tennis", "pickleball": return "Tennis"
        case "golf": return "Golf"
        case "climbing": return "Climbing"
        case "recovery", "preparation_and_recovery": return "Recovery"
        case "other", "hk_3000": return "Custom Workout"
        default:
            return key
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    static func symbolName(forKey key: String) -> String {
        switch key.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "hiking": return "figure.hiking"
        case "swimming": return "figure.pool.swim"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.elliptical"
        case "stairs", "stair_climbing": return "figure.stairs"
        case "strength", "traditional_strength", "functional_strength": return "dumbbell.fill"
        case "core", "hiit": return "flame.fill"
        case "yoga", "pilates", "flexibility", "cooldown", "mind_body", "recovery":
            return "figure.mind.and.body"
        case "cross_training", "mixed_cardio": return "figure.mixed.cardio"
        case "dance": return "figure.dance"
        case "boxing", "kickboxing", "martial_arts": return "figure.boxing"
        default: return "dumbbell.fill"
        }
    }

    static func detailBlurb(forKey key: String) -> String {
        let title = title(forKey: key)
        switch key.lowercased() {
        case "other", "hk_3000":
            return "Apple Health recorded this as a generic workout (no specific sport). Duration, heart rate, calories, and strain still come from that session."
        default:
            return "Pulled from Apple Health as \(title)."
        }
    }

    static func filterCategory(forKey key: String) -> String {
        let s = key.lowercased()
        if s.contains("run") || s.contains("walk") || s.contains("cycl") || s.contains("hik") || s.contains("swim") { return "Run" }
        if s.contains("strength") || s.contains("function") || s.contains("core") || s.contains("hiit") || s.contains("cross") { return "Strength" }
        if s.contains("yoga") || s.contains("mind") || s.contains("flex") || s.contains("cool") || s.contains("recover") || s.contains("pilates") { return "Recovery" }
        return "Other"
    }
}
