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
