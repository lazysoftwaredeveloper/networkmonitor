import Foundation

public struct AppUsageDelta: Equatable, Sendable {
    public let appKey: String
    public let appName: String
    public let bundlePath: String?
    public let downloaded: Int64
    public let uploaded: Int64

    public init(appKey: String, appName: String, bundlePath: String?,
                downloaded: Int64, uploaded: Int64) {
        self.appKey = appKey
        self.appName = appName
        self.bundlePath = bundlePath
        self.downloaded = max(0, downloaded)
        self.uploaded = max(0, uploaded)
    }
}

public struct AppUsageSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var bundlePath: String?
    public var downloaded: Int64
    public var uploaded: Int64
    public var total: Int64 { downloaded + uploaded }
}

public struct UsageTotals: Equatable, Sendable {
    public let downloaded: Int64
    public let uploaded: Int64
    public var total: Int64 { downloaded + uploaded }
}

public struct UsageChartPoint: Identifiable, Equatable, Sendable {
    public let date: Date
    public let downloaded: Int64
    public let uploaded: Int64
    public var id: Date { date }
}

private struct UsageRecord: Codable {
    let id: String
    let bucketStart: Date
    let scope: NetworkScope
    let appKey: String
    var appName: String
    var bundlePath: String?
    var downloaded: Int64
    var uploaded: Int64
}

private struct UsageArchive: Codable {
    var records: [UsageRecord]
}

/// Hourly local history. The file is deliberately plain JSON so users can
/// inspect, back up, or delete their own traffic history without a database tool.
public final class UsageStore {
    private var records: [String: UsageRecord] = [:]
    private let fileURL: URL
    private let calendar: Calendar
    private var lastPrunedDay: Date?

    public init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(UsageArchive.self, from: data) else { return }
        records = Dictionary(archive.records.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        pruneIfNeeded(now: Date())
    }

    public func record(_ deltas: [AppUsageDelta], scope: NetworkScope, at date: Date = Date()) {
        guard !deltas.isEmpty else { return }
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date

        for delta in deltas where delta.downloaded > 0 || delta.uploaded > 0 {
            let key = "\(Int64(hour.timeIntervalSince1970))|\(scope.rawValue)|\(delta.appKey)"
            if var existing = records[key] {
                existing.downloaded += delta.downloaded
                existing.uploaded += delta.uploaded
                existing.appName = delta.appName
                existing.bundlePath = delta.bundlePath ?? existing.bundlePath
                records[key] = existing
            } else {
                records[key] = UsageRecord(
                    id: key,
                    bucketStart: hour,
                    scope: scope,
                    appKey: delta.appKey,
                    appName: delta.appName,
                    bundlePath: delta.bundlePath,
                    downloaded: delta.downloaded,
                    uploaded: delta.uploaded
                )
            }
        }
        pruneIfNeeded(now: date)
    }

    public func totals(scope: NetworkScope, period: UsagePeriod, now: Date = Date(),
                       customStart: Date? = nil, customEnd: Date? = nil) -> UsageTotals {
        let start = period.start(now: now, calendar: calendar, customStart: customStart)
        let end = period.endExclusive(now: now, calendar: calendar, customEnd: customEnd)
        var downloaded: Int64 = 0
        var uploaded: Int64 = 0
        for record in records.values where record.scope == scope && record.bucketStart >= start && record.bucketStart < end {
            downloaded += record.downloaded
            uploaded += record.uploaded
        }
        return UsageTotals(downloaded: downloaded, uploaded: uploaded)
    }

    public func apps(scope: NetworkScope, period: UsagePeriod, now: Date = Date(),
                     customStart: Date? = nil, customEnd: Date? = nil) -> [AppUsageSummary] {
        let start = period.start(now: now, calendar: calendar, customStart: customStart)
        let end = period.endExclusive(now: now, calendar: calendar, customEnd: customEnd)
        var grouped: [String: AppUsageSummary] = [:]

        for record in records.values where record.scope == scope && record.bucketStart >= start && record.bucketStart < end {
            if var current = grouped[record.appKey] {
                current.downloaded += record.downloaded
                current.uploaded += record.uploaded
                current.name = record.appName
                current.bundlePath = record.bundlePath ?? current.bundlePath
                grouped[record.appKey] = current
            } else {
                grouped[record.appKey] = AppUsageSummary(
                    id: record.appKey,
                    name: record.appName,
                    bundlePath: record.bundlePath,
                    downloaded: record.downloaded,
                    uploaded: record.uploaded
                )
            }
        }

        return grouped.values.sorted {
            if $0.total == $1.total { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.total > $1.total
        }
    }

    public func chart(scope: NetworkScope, period: UsagePeriod, now: Date = Date(),
                      customStart: Date? = nil, customEnd: Date? = nil) -> [UsageChartPoint] {
        let start = period.start(now: now, calendar: calendar, customStart: customStart)
        let end = period.endExclusive(now: now, calendar: calendar, customEnd: customEnd)
        var buckets: [Date: (downloaded: Int64, uploaded: Int64)] = [:]

        for record in records.values where record.scope == scope && record.bucketStart >= start && record.bucketStart < end {
            let bucket = period == .today
                ? (calendar.dateInterval(of: .hour, for: record.bucketStart)?.start ?? record.bucketStart)
                : calendar.startOfDay(for: record.bucketStart)
            var totals = buckets[bucket, default: (0, 0)]
            totals.downloaded += record.downloaded
            totals.uploaded += record.uploaded
            buckets[bucket] = totals
        }

        return period.bucketStarts(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd).map { date in
            let value = buckets[date] ?? (0, 0)
            return UsageChartPoint(date: date, downloaded: value.downloaded, uploaded: value.uploaded)
        }
    }

    public func save() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let archive = UsageArchive(records: records.values.sorted { $0.bucketStart < $1.bucketStart })
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(archive)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NetworkMonitor: could not save usage history: %@", error.localizedDescription)
        }
    }

    private func pruneIfNeeded(now: Date) {
        let today = calendar.startOfDay(for: now)
        guard lastPrunedDay != today else { return }
        lastPrunedDay = today
        let cutoff = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        records = records.filter { $0.value.bucketStart >= cutoff }
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("NetworkMonitor", isDirectory: true)
            .appendingPathComponent("usage.json")
    }
}
