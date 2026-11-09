import XCTest
@testable import ReadinessCoach

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRetiredServerURLMovesToDefaultAndResetsWatermark() {
        defaults.set("https://readiness-coach-api-shawngeorgie06.georgenijo.com/", forKey: "apiBaseURL")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastSyncAt")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.apiBaseURL, AppSettings.defaultBaseURL)
        XCTAssertEqual(defaults.string(forKey: "apiBaseURL"), AppSettings.defaultBaseURL)
        XCTAssertNil(settings.lastSyncAt)
    }

    func testUnsavedLegacyDefaultResetsWatermarkOnce() {
        defaults.set(Date().timeIntervalSince1970, forKey: "lastSyncAt")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "apiBaseURL"), AppSettings.defaultBaseURL)
        XCTAssertNil(settings.lastSyncAt)

        settings.lastSyncAt = Date()
        let relaunched = AppSettings(defaults: defaults)
        XCTAssertNotNil(relaunched.lastSyncAt, "the migration runs only once")
    }

    func testCustomServerURLIsKept() {
        defaults.set("https://example.test", forKey: "apiBaseURL")
        defaults.set(1_700_000_000, forKey: "lastSyncAt")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.apiBaseURL, "https://example.test")
        XCTAssertNotNil(settings.lastSyncAt)
    }

    func testChangingServerURLResetsWatermark() {
        let settings = AppSettings(defaults: defaults)
        settings.lastSyncAt = Date()

        settings.apiBaseURL = AppSettings.defaultBaseURL + "/"
        XCTAssertNotNil(settings.lastSyncAt, "same server, different spelling")

        settings.apiBaseURL = "https://example.test"
        XCTAssertNil(settings.lastSyncAt)
    }
}
