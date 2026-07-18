import Foundation
import HealthKit

/// Wakes the app when Apple Health records new samples so we can upload them
/// without the user opening Today. Uses HealthKit background delivery — no
/// BGAppRefreshTask scheduling required.
final class HealthBackgroundDelivery {
    private let store = HKHealthStore()
    private var started = false

    func start(onUpdate: @escaping @MainActor () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable(), !started else { return }
        started = true

        let types: [HKSampleType] = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }

            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task { @MainActor in
                    await onUpdate()
                    completionHandler()
                }
            }
            store.execute(query)
        }
    }
}
