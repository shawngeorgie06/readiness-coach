import Foundation
import HealthKit

/// Reads HealthKit samples and maps them into the backend sync payload shape.
/// Read-only: the app never writes health data.
@MainActor
final class HealthKitService {
    private let store = HKHealthStore()

    /// First sync only reaches back this far so the initial upload stays bounded.
    /// The backend computes 30-day baselines, so this window is sufficient.
    private let initialLookbackDays = 30
    /// Sleep is often finalized or amended by Apple Health after a first read.
    /// Re-check recent nights on every sync so late Watch data is not skipped.
    private let sleepRecheckDays = 3

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Types

    private var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    private var restingHeartRate: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var hrvSDNN: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var oxygen: HKQuantityType { HKQuantityType(.oxygenSaturation) }
    private var sleep: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    private var readTypes: Set<HKObjectType> {
        [heartRate, restingHeartRate, hrvSDNN, oxygen, sleep, HKObjectType.workoutType()]
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        guard Self.isAvailable else {
            throw NSError(
                domain: "ReadinessCoach.HealthKit",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Health data is not available on this device."]
            )
        }
        // The app only reads; the second (share) set is intentionally empty.
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: Fetch

    /// Collects every supported sample newer than `since` (or the initial window)
    /// and returns them as a sync payload for `userId`.
    func fetchSamples(since: Date?, userId: String) async throws -> SyncPayload {
        let start = since ?? Calendar.current.date(
            byAdding: .day, value: -initialLookbackDays, to: Date()
        ) ?? Date().addingTimeInterval(-Double(initialLookbackDays) * 86_400)
        let end = Date()
        let sleepStart = Calendar.current.date(
            byAdding: .day,
            value: -sleepRecheckDays,
            to: end
        ) ?? start

        async let hr = quantitySamples(heartRate, unit: HKUnit(from: "count/min"),
                                       apiType: "heart_rate", unitLabel: "count/min", start: start, end: end)
        async let rhr = quantitySamples(restingHeartRate, unit: HKUnit(from: "count/min"),
                                        apiType: "resting_heart_rate", unitLabel: "count/min", start: start, end: end)
        async let hrv = quantitySamples(hrvSDNN, unit: .secondUnit(with: .milli),
                                        apiType: "hrv_sdnn", unitLabel: "ms", start: start, end: end)
        async let spo2 = quantitySamples(oxygen, unit: .percent(),
                                         apiType: "oxygen_saturation", unitLabel: "%", start: start, end: end, scale: 100)
        async let sleepSamples = self.sleepSamples(start: sleepStart, end: end)
        async let workoutSamples = self.workouts(start: start, end: end)

        let samples = try await hr + rhr + hrv + spo2 + sleepSamples
        let workouts = try await workoutSamples
        return SyncPayload(userId: userId, samples: samples, workouts: workouts)
    }

    // MARK: Quantity samples

    private func quantitySamples(
        _ type: HKQuantityType,
        unit: HKUnit,
        apiType: String,
        unitLabel: String,
        start: Date,
        end: Date,
        scale: Double = 1
    ) async throws -> [SyncSample] {
        let samples = try await execute(sampleType: type, start: start, end: end)
        return samples.compactMap { sample in
            guard let q = sample as? HKQuantitySample else { return nil }
            return SyncSample(
                hkUuid: q.uuid.uuidString,
                type: apiType,
                startAt: DateFormatting.iso(q.startDate),
                endAt: DateFormatting.iso(q.endDate),
                value: q.quantity.doubleValue(for: unit) * scale,
                unit: unitLabel,
                metadata: nil
            )
        }
    }

    // MARK: Sleep

    private func sleepSamples(start: Date, end: Date) async throws -> [SyncSample] {
        let samples = try await execute(sampleType: sleep, start: start, end: end)
        return samples.compactMap { sample in
            guard let c = sample as? HKCategorySample else { return nil }
            return SyncSample(
                hkUuid: c.uuid.uuidString,
                type: "sleep_analysis",
                startAt: DateFormatting.iso(c.startDate),
                endAt: DateFormatting.iso(c.endDate),
                value: nil,
                unit: nil,
                metadata: ["stage": Self.sleepStage(c.value)]
            )
        }
    }

    /// Maps HealthKit sleep category values to the stage keywords the backend
    /// looks for ("awake", "inBed", "deep", "rem" drive its aggregation).
    private static func sleepStage(_ raw: Int) -> String {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: raw) else { return "asleep" }
        switch value {
        case .inBed: return "inBed"
        case .awake: return "awake"
        case .asleepUnspecified: return "asleep"
        case .asleepCore: return "core"
        case .asleepDeep: return "deep"
        case .asleepREM: return "rem"
        @unknown default: return "asleep"
        }
    }

    // MARK: Workouts

    private func workouts(start: Date, end: Date) async throws -> [SyncWorkout] {
        let samples = try await execute(sampleType: HKObjectType.workoutType(), start: start, end: end)
        var result: [SyncWorkout] = []
        for case let workout as HKWorkout in samples {
            let avgHr = await averageHeartRate(start: workout.startDate, end: workout.endDate)
            let energyType = HKQuantityType(.activeEnergyBurned)
            let calories = workout.statistics(for: energyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            result.append(
                SyncWorkout(
                    hkUuid: workout.uuid.uuidString,
                    sport: WorkoutSport.key(for: workout.workoutActivityType),
                    startAt: DateFormatting.iso(workout.startDate),
                    endAt: DateFormatting.iso(workout.endDate),
                    durationMin: workout.duration / 60,
                    avgHrBpm: avgHr,
                    calories: calories
                )
            )
        }
        return result
    }

    private func averageHeartRate(start: Date, end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: heartRate,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                let bpm = stats?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: Query plumbing

    private func execute(sampleType: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}

/// Shared ISO-8601 formatting. The backend accepts UTC "...Z" timestamps.
enum DateFormatting {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func iso(_ date: Date) -> String { iso8601.string(from: date) }

    static func date(fromISO string: String) -> Date? { iso8601.date(from: string) }
}
