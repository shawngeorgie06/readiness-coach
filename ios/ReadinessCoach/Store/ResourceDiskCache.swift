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
