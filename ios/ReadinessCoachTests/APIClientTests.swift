import XCTest
@testable import ReadinessCoach

final class StubURLProtocol: URLProtocol {
    typealias Responder = (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var responder: Responder?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        requests = []
        self.responder = responder
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let responder = Self.responder
        Self.lock.unlock()
        do {
            guard let responder else { throw URLError(.badServerResponse) }
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private let todayJSON = """
    {"date":"2026-10-23","readiness":72,"decision":"maintain","calibrating":false,
     "pillars":{"sleep":{"score":70,"drivers":[]},"recovery":{"score":70,"drivers":[]},"load":{"score":70,"drivers":[]}},
     "overridesApplied":[],"confidence":"high","missing":[],
     "advisor":{"decision":"maintain","why":[],"prescription":"","ifIgnored":"","source":"template"}
     BASELINES}
    """

    private let baselinesJSON = """
    ,"baselines":{
      "hrv":{"today":55.5,"baseline30d":50,"neutralBand":{"low":45,"high":55},"recent14d":[null,1,2,3,4,5,6,7,8,9,10,11,12,13],"goodDirection":"up"},
      "restingHr":{"today":null,"baseline30d":null,"neutralBand":null,"recent14d":[null,null,null,null,null,null,null,null,null,null,null,null,null,null],"goodDirection":"down"},
      "sleepHours":{"today":7,"baseline30d":7.2,"neutralBand":{"low":6.5,"high":8},"recent14d":[7,7,7,7,7,7,7,7,7,7,7,7,7,7],"goodDirection":"up"},
      "load7d":{"today":100,"baseline30d":90,"neutralBand":{"low":70,"high":110},"recent14d":[1,1,1,1,1,1,1,1,1,1,1,1,1,1],"goodDirection":"none"}}
    """

    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 15
        return APIClient(
            baseURL: URL(string: "https://example.test")!, token: "t", userId: "u",
            session: URLSession(configuration: config)
        )
    }

    private func response(_ request: URLRequest, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testSendsIfNoneMatchAndMaps304ToNotModified() async throws {
        StubURLProtocol.reset { [self] req in (response(req, 304), Data()) }
        let result = try await client().today(etag: "W/\"abc\"")
        guard case .notModified = result else { return XCTFail("expected notModified") }
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
        XCTAssertEqual(StubURLProtocol.requests.first?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testFreshReadReturnsEtagHeader() async throws {
        StubURLProtocol.reset { [self] req in
            (response(req, 200, headers: ["ETag": "W/\"xyz\""]), Data(todayJSON.replacingOccurrences(of: "BASELINES", with: "").utf8))
        }
        guard case let .fresh(dto, etag) = try await client().today(etag: nil) else { return XCTFail("expected fresh") }
        XCTAssertEqual(etag, "W/\"xyz\"")
        XCTAssertEqual(dto.date, "2026-10-23")
    }

    func testNoIfNoneMatchWithoutCachedValue() async throws {
        StubURLProtocol.reset { [self] req in
            (response(req, 200), Data(todayJSON.replacingOccurrences(of: "BASELINES", with: "").utf8))
        }
        _ = try await client().today(etag: nil)
        XCTAssertNil(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testReadTimeoutIs15Seconds() async throws {
        StubURLProtocol.reset { [self] req in
            (response(req, 200), Data(todayJSON.replacingOccurrences(of: "BASELINES", with: "").utf8))
        }
        _ = try await client().today(etag: nil)
        XCTAssertEqual(StubURLProtocol.requests.first?.timeoutInterval, 15)
    }

    func testHistorySendsTz() async throws {
        StubURLProtocol.reset { [self] req in (response(req, 304), Data()) }
        _ = try await client().history(days: 30, etag: "W/\"1\"")
        let items = URLComponents(url: StubURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNotNil(items.first { $0.name == "tz" })
        XCTAssertEqual(items.first { $0.name == "days" }?.value, "30")
    }

    func testTransportErrorRetriesOnceImmediately() async throws {
        nonisolated(unsafe) var calls = 0
        StubURLProtocol.reset { [self] req in
            calls += 1
            if calls == 1 { throw URLError(.networkConnectionLost) }
            return (response(req, 200), Data(todayJSON.replacingOccurrences(of: "BASELINES", with: "").utf8))
        }
        let start = Date()
        _ = try await client().today(etag: nil)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testCancelledRequestIsNotRetried() async {
        StubURLProtocol.reset { _ in throw URLError(.cancelled) }
        do {
            _ = try await client().today(etag: nil)
            XCTFail("expected throw")
        } catch APIError.transport {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testHttpErrorIsNotRetried() async {
        StubURLProtocol.reset { [self] req in (response(req, 500), Data()) }
        do {
            _ = try await client().today(etag: nil)
            XCTFail("expected throw")
        } catch APIError.http(let status, _) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testTodayDecodesWithAndWithoutBaselines() throws {
        let without = try JSONDecoder().decode(TodayDTO.self, from: Data(todayJSON.replacingOccurrences(of: "BASELINES", with: "").utf8))
        XCTAssertNil(without.baselines)
        let with = try JSONDecoder().decode(TodayDTO.self, from: Data(todayJSON.replacingOccurrences(of: "BASELINES", with: baselinesJSON).utf8))
        XCTAssertEqual(with.baselines?.hrv.today, 55.5)
        XCTAssertEqual(with.baselines?.hrv.neutralBand, NeutralBandDTO(low: 45, high: 55))
        XCTAssertEqual(with.baselines?.hrv.recent14d.count, 14)
        XCTAssertNil(with.baselines?.hrv.recent14d[0])
        XCTAssertNil(with.baselines?.restingHr.today)
        XCTAssertNil(with.baselines?.restingHr.neutralBand)
        XCTAssertEqual(with.baselines?.load7d.goodDirection, "none")
    }

    func testDeviceLocalDateUsesSharedFormatter() {
        let ny = TimeZone(identifier: "America/New_York")!
        let saved = NSTimeZone.default
        NSTimeZone.default = ny
        defer { NSTimeZone.default = saved }
        // 2026-10-24 02:30 UTC is 2026-10-23 22:30 in New York.
        let date = Date(timeIntervalSince1970: 1_792_809_000)
        XCTAssertEqual(APIClient.deviceLocalDate(now: date), "2026-10-23")
        XCTAssertEqual(APIClient.deviceLocalDate(now: date), "2026-10-23")
    }
}
