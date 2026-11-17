import XCTest
@testable import NetworkMonitorCore

final class UsageStoreTests: XCTestCase {
    func testRecordsAndReloadsHourlyAppUsage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter().date(from: "2026-11-17T10:30:00Z")!
        let store = UsageStore(fileURL: file, calendar: calendar)
        store.record([
            AppUsageDelta(appKey: "/Applications/Safari.app", appName: "Safari",
                          bundlePath: "/Applications/Safari.app", downloaded: 1_024, uploaded: 512)
        ], scope: .wifi, at: date)
        store.save()

        let reloaded = UsageStore(fileURL: file, calendar: calendar)
        reloaded.load()
        let totals = reloaded.totals(scope: .wifi, period: .today, now: date)
        XCTAssertEqual(totals.downloaded, 1_024)
        XCTAssertEqual(totals.uploaded, 512)
        XCTAssertEqual(reloaded.apps(scope: .wifi, period: .today, now: date).first?.name, "Safari")
    }

    func testSeparatesNetworkScopes() {
        let date = Date()
        let store = UsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 100, uploaded: 10)
        ], scope: .wifi, at: date)
        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 200, uploaded: 20)
        ], scope: .wired, at: date)

        XCTAssertEqual(store.totals(scope: .wifi, period: .today).downloaded, 100)
        XCTAssertEqual(store.totals(scope: .wired, period: .today).downloaded, 200)
        XCTAssertEqual(store.totals(scope: .all, period: .today).downloaded, 0)
    }
}
