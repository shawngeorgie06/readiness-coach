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

/// A value plus the bookkeeping needed to decide when to refetch it.
struct Resource<Value> {
    var value: Value?
    var day: String?
    var fetchedAt: Date?
    var etag: String?
    var dataVersion = 0
    var isRefreshing = false
    var error: String?

    /// Missing, older than `maxAge`, from another local day, or fetched before
    /// the latest sample upload.
    func needsRevalidation(
        now: Date,
        today: String,
        currentDataVersion: Int,
        maxAge: TimeInterval = 300
    ) -> Bool {
        guard value != nil, let fetchedAt, let day else { return true }
        if day != today { return true }
        if dataVersion < currentDataVersion { return true }
        return now.timeIntervalSince(fetchedAt) > maxAge
    }
}

struct CachedEnvelope<Value: Codable>: Codable {
    let userId: String
    let day: String
    let fetchedAt: Date
    let etag: String?
    let value: Value
}
