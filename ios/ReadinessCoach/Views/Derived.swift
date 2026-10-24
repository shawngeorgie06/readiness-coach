import Foundation

/// Caches a value derived from a store resource (chart series, sorted lists,
/// averages) so `body` rebuilds it only when the resource changes, not on
/// every render. Hold it in `@State`; it is deliberately not observable.
final class Derived<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func get(_ key: Key, _ make: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let made = make()
        self.key = key
        value = made
        return made
    }
}

/// Identifies one build of a chart series. Chart dates are midnights in a time
/// zone, so the zone is part of the identity: after travel the series rebuilds
/// and its dates match the rebased selection.
struct SeriesStamp: Equatable {
    let days: Int
    let fetchedAt: Date?
    let timeZone: TimeZone
}

extension Derived where Key == SeriesStamp {
    /// The series for this response, built with `timeZone` and reused until the
    /// range, the fetch, or the zone changes.
    func series(days: Int = 0, fetchedAt: Date?, timeZone: TimeZone = .current, _ make: (TimeZone) -> Value) -> Value {
        get(SeriesStamp(days: days, fetchedAt: fetchedAt, timeZone: timeZone)) { make(timeZone) }
    }
}
