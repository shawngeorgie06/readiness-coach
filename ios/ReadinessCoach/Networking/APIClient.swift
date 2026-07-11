import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, code: String?)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API URL, token, and user ID must be set in Settings."
        case .invalidURL:
            return "The API URL is not valid."
        case let .http(status, code):
            if let code, !code.isEmpty {
                return "Server error (\(status)): \(code)"
            }
            return "Server returned status \(status)."
        case let .transport(error):
            return error.localizedDescription
        case .decoding:
            return "The server response could not be read."
        }
    }
}

/// Thin async client for the Readiness Coach API. All `/v1` routes require a
/// bearer token; the deterministic decision is owned by the backend.
struct APIClient {
    let baseURL: URL
    let token: String
    let userId: String

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    // MARK: Reads

    func getToday(date: String? = nil) async throws -> TodayDTO {
        try await get("v1/today", query: dateQuery(date))
    }

    func getSleep(days: Int = 30, date: String? = nil) async throws -> SleepDetailResponse {
        try await get("v1/sleep", query: [URLQueryItem(name: "days", value: String(days))] + dateQuery(date))
    }

    func getTrain(days: Int = 28, date: String? = nil) async throws -> TrainResponse {
        try await get("v1/train", query: [URLQueryItem(name: "days", value: String(days))] + dateQuery(date))
    }

    func getBody(days: Int = 14, date: String? = nil) async throws -> BodyResponse {
        try await get("v1/body", query: [URLQueryItem(name: "days", value: String(days))] + dateQuery(date))
    }

    // MARK: Writes

    func sync(_ payload: SyncPayload) async throws -> SyncResult {
        try await send("v1/sync", method: "POST", body: payload)
    }

    func ask(question: String, date: String? = nil) async throws -> AskResponse {
        let body = AskRequest(userId: userId, question: question, date: date)
        return try await send("v1/coach/ask", method: "POST", body: body)
    }

    /// Deletes the user and all associated health data (GDPR-style erase).
    func deleteAccount() async throws {
        _ = try await requestData(path: "v1/user", method: "DELETE", query: [], body: Optional<SyncPayload>.none)
    }

    // MARK: - Internals

    private func dateQuery(_ date: String?) -> [URLQueryItem] {
        guard let date else { return [] }
        return [URLQueryItem(name: "date", value: date)]
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await requestData(path: path, method: "GET", query: query, body: Optional<SyncPayload>.none)
        return try decode(data)
    }

    private func send<Body: Encodable, T: Decodable>(_ path: String, method: String, body: Body) async throws -> T {
        let data = try await requestData(path: path, method: method, query: [], body: body)
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func requestData<Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        var items = query
        // userId travels as a query param on reads/deletes; POST bodies carry it too.
        items.append(URLQueryItem(name: "userId", value: userId))
        components?.queryItems = items
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, code: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, code: Self.errorCode(from: data))
        }
        return data
    }

    /// Pulls the `error` field from a JSON error body when present.
    private static func errorCode(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let string = object["error"] as? String { return string }
        return nil
    }
}
