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

    func testSeparatesTrafficByWiFiNetworkAndListsNetworkTotals() {
        let date = Date()
        let store = UsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let home = NetworkIdentity(id: "gw:aa:bb:cc:dd:ee:01", name: "Home_WiFi")
        let office = NetworkIdentity(id: "gw:aa:bb:cc:dd:ee:02", name: "Office_WiFi")
        let safari = AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                                   downloaded: 100, uploaded: 10)

        store.record([safari], scope: .wifi, network: home, at: date)
        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 250, uploaded: 25)
        ], scope: .wifi, network: office, at: date)

        XCTAssertEqual(
            store.totals(scope: .wifi, period: .today, networkID: home.id, now: date).downloaded,
            100
        )
        XCTAssertEqual(
            store.totals(scope: .wifi, period: .today, networkID: office.id, now: date).downloaded,
            250
        )
        XCTAssertEqual(store.totals(scope: .wifi, period: .today, now: date).downloaded, 350)

        let networks = store.networks(scope: .wifi, period: .today, now: date)
        XCTAssertEqual(Set(networks.map(\.name)), Set(["Home_WiFi", "Office_WiFi"]))
        XCTAssertEqual(networks.first?.name, "Office_WiFi")
        XCTAssertEqual(networks.first?.total, 275)
    }

    func testLoadsLegacyRecordsWithoutNetworkMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        let json = """
        {
          "records": [{
            "id": "legacy-record",
            "bucketStart": "2026-11-17T10:00:00Z",
            "scope": "wifi",
            "appKey": "safari",
            "appName": "Safari",
            "bundlePath": null,
            "downloaded": 321,
            "uploaded": 45
          }]
        }
        """
        try Data(json.utf8).write(to: file)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-11-17T10:30:00Z")!
        let store = UsageStore(fileURL: file, calendar: calendar)
        store.load()

        XCTAssertEqual(store.totals(scope: .wifi, period: .today, now: now).downloaded, 321)
        XCTAssertEqual(store.networks(scope: .wifi, period: .today, now: now).first?.name,
                       "旧记录（未按网络区分）")
        XCTAssertEqual(
            store.totals(scope: .wifi, period: .today, networkID: "legacy", now: now).uploaded,
            45
        )
    }

    func testCustomDateRangeIncludesOnlySelectedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        let firstDay = formatter.date(from: "2026-11-15T12:00:00Z")!
        let secondDay = formatter.date(from: "2026-11-16T12:00:00Z")!
        let outsideDay = formatter.date(from: "2026-11-17T10:00:00Z")!
        let store = UsageStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            calendar: calendar
        )

        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 100, uploaded: 10)
        ], scope: .wifi, at: firstDay)
        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 200, uploaded: 20)
        ], scope: .wifi, at: secondDay)
        store.record([
            AppUsageDelta(appKey: "safari", appName: "Safari", bundlePath: nil,
                          downloaded: 400, uploaded: 40)
        ], scope: .wifi, at: outsideDay)

        let totals = store.totals(
            scope: .wifi,
            period: .custom,
            now: outsideDay,
            customStart: firstDay,
            customEnd: secondDay
        )
        XCTAssertEqual(totals.downloaded, 300)
        XCTAssertEqual(totals.uploaded, 30)
        XCTAssertEqual(store.chart(
            scope: .wifi,
            period: .custom,
            now: outsideDay,
            customStart: firstDay,
            customEnd: secondDay
        ).count, 2)
    }
}
