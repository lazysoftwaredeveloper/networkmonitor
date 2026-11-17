import Foundation

public enum NetworkScope: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case all
    case wifi
    case wired
    case metered

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部网络"
        case .wifi: return "Wi-Fi"
        case .wired: return "有线网络"
        case .metered: return "计费网络"
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "network"
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        case .metered: return "antenna.radiowaves.left.and.right"
        }
    }

    /// nettop's interface-type filters. "Expensive" is macOS's classification;
    /// it commonly covers personal hotspots, but is not guaranteed to cover all.
    var nettopType: String {
        switch self {
        case .all: return "external"
        case .wifi: return "wifi"
        case .wired: return "wired"
        case .metered: return "expensive"
        }
    }
}

public enum UsagePeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case week
    case month
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        case .custom: return "自定义"
        }
    }

    func start(now: Date, calendar: Calendar = .current, customStart: Date? = nil) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .custom:
            let requested = calendar.startOfDay(for: customStart ?? calendar.date(byAdding: .day, value: -6, to: today) ?? today)
            let oldestKept = calendar.date(byAdding: .day, value: -119, to: today) ?? today
            return max(requested, oldestKept)
        }
    }

    func endExclusive(now: Date, calendar: Calendar = .current, customEnd: Date? = nil) -> Date {
        guard self == .custom else { return now.addingTimeInterval(1) }
        let requestedEnd = calendar.startOfDay(for: customEnd ?? now)
        let endDay = min(requestedEnd, calendar.startOfDay(for: now))
        return calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
    }

    func bucketStarts(now: Date, calendar: Calendar = .current,
                      customStart: Date? = nil, customEnd: Date? = nil) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            let currentHour = calendar.component(.hour, from: now)
            return (0...currentHour).compactMap {
                calendar.date(byAdding: .hour, value: $0, to: startOfToday)
            }
        case .week:
            let first = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        case .month:
            let first = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return (0..<30).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        case .custom:
            let first = start(now: now, calendar: calendar, customStart: customStart)
            let requestedEnd = calendar.startOfDay(for: customEnd ?? now)
            let endDay = min(requestedEnd, startOfToday)
            let days = max(1, (calendar.dateComponents([.day], from: first, to: endDay).day ?? 0) + 1)
            return (0..<min(days, 120)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        }
    }
}
