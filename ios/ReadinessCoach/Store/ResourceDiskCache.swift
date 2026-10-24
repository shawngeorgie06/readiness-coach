import Foundation

/// On-disk copy of health-derived resources. Files use complete file
/// protection and are excluded from backups. Every envelope records its user
/// and `load` refuses another user's data.
final class ResourceDiskCache {
    private let directory: URL
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL) {
        self.directory = directory
    }

    private func url(for key: ResourceKey) -> URL {
        directory.appendingPathComponent("\(key.fileName).json")
    }

    func load<V: Codable>(_ key: ResourceKey, userId: String, as: V.Type) -> CachedEnvelope<V>? {
        guard let data = try? Data(contentsOf: url(for: key)),
              let envelope = try? Self.decoder.decode(CachedEnvelope<V>.self, from: data),
              envelope.userId == userId
        else { return nil }
        return envelope
    }

    func save<V: Codable>(_ key: ResourceKey, _ envelope: CachedEnvelope<V>) {
        guard let data = try? Self.encoder.encode(envelope) else { return }
        write(data, to: url(for: key))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// One-time: moves legacy `cached-today.json` into the `today` slot for
    /// `userId`, then deletes it. The legacy file holds a bare `TodayDTO`
    /// written with a default `JSONEncoder`, so it is read with a default
    /// decoder. An existing `today` entry for this user is kept.
    func migrateLegacyToday(from legacyURL: URL, userId: String, day: String) {
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        guard let data = try? Data(contentsOf: legacyURL),
              let dto = try? JSONDecoder().decode(TodayDTO.self, from: data),
              load(.today, userId: userId, as: TodayDTO.self) == nil
        else { return }
        let modified = (try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        save(.today, CachedEnvelope(
            userId: userId, day: day, fetchedAt: modified ?? Date(), etag: nil, value: dto
        ))
    }

    private func write(_ data: Data, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var directoryURL = directory
            try directoryURL.setResourceValues(directoryValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var target = fileURL
            try target.setResourceValues(values)
        } catch {
            // Caching is an optimization; the fetched value remains usable.
        }
    }
}
