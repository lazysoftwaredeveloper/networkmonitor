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

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        }
    }

    func start(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        }
    }

    func bucketStarts(now: Date, calendar: Calendar = .current) -> [Date] {
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
        }
    }
}
