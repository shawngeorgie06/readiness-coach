import Foundation

/// Identifies one cacheable server resource.
enum ResourceKey: Hashable {
    case today, body, train
    case sleep(days: Int)
    case history(days: Int)

    var fileName: String {
        switch self {
        case .today: return "today"
        case .body: return "body"
        case .train: return "train"
        case .sleep(let days): return "sleep-\(days)"
        case .history(let days): return "history-\(days)"
        }
    }
}

/// `.task(id:)` identity for a screen's resource: the refresh re-runs when the
/// key changes and when the local day or UTC offset changes while it is shown.
struct ResourceTaskID: Hashable {
    let key: ResourceKey
    let day: LocalDay
}

/// A value plus the bookkeeping needed to decide when to refetch it.
struct Resource<Value> {
    var value: Value?
    var day: String?
    /// The UTC offset the value was fetched under; `nil` for a cache written
    /// before offsets were stored, which still shows but always revalidates.
    var utcOffsetMinutes: Int?
    var fetchedAt: Date?
    var etag: String?
    var dataVersion = 0
    var isRefreshing = false
    var error: String?

    /// Missing, older than `maxAge`, from another local day or UTC offset, or
    /// fetched before the latest sample upload.
    func needsRevalidation(
        now: Date,
        today: LocalDay,
        currentDataVersion: Int,
        maxAge: TimeInterval = 300
    ) -> Bool {
        guard value != nil, let fetchedAt, let day else { return true }
        if day != today.date || utcOffsetMinutes != today.utcOffsetMinutes { return true }
        if dataVersion < currentDataVersion { return true }
        return now.timeIntervalSince(fetchedAt) > maxAge
    }
}

struct CachedEnvelope<Value: Codable>: Codable {
    let userId: String
    let day: String
    /// Optional so caches written before offsets were stored still decode.
    let utcOffsetMinutes: Int?
    let fetchedAt: Date
    let etag: String?
    let value: Value
}
