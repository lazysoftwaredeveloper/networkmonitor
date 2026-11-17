import AppKit
import Combine
import Foundation

@MainActor
public final class MonitorModel: ObservableObject {
    @Published public var selectedScope: NetworkScope = .all {
        didSet {
            statusText = streamStatuses[selectedScope] ?? "正在记录 · 数据仅保存在本机"
            refresh()
        }
    }
    @Published public var selectedPeriod: UsagePeriod = .week {
        didSet { refresh() }
    }
    @Published public var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date() {
        didSet { refresh() }
    }
    @Published public var customEndDate: Date = Date() {
        didSet { refresh() }
    }

    @Published public private(set) var totalDownloaded: Int64 = 0
    @Published public private(set) var totalUploaded: Int64 = 0
    @Published public private(set) var downloadRate: Double = 0
    @Published public private(set) var uploadRate: Double = 0
    @Published public private(set) var appSummaries: [AppUsageSummary] = []
    @Published public private(set) var chartPoints: [UsageChartPoint] = []
    @Published public private(set) var statusText = "正在启动监控…"

    private let store = UsageStore()
    private let identityResolver = ProcessIdentityResolver()
    private var streams: [NettopStream] = []
    private var streamStatuses: [NetworkScope: String] = [:]
    private var lastSampleAt: [NetworkScope: Date] = [:]
    private var rates: [NetworkScope: (download: Double, upload: Double)] = [:]
    private var saveTimer: Timer?
    private var terminationObserver: NSObjectProtocol?

    public init() {
        store.load()
        refresh()
        startMonitoring()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopMonitoring() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    public var downloadRateText: String { ByteFormat.rate(downloadRate) }
    public var uploadRateText: String { ByteFormat.rate(uploadRate) }
    public var maxAppTotal: Int64 { max(appSummaries.map(\.total).max() ?? 0, 1) }

    public func stopMonitoring() {
        saveTimer?.invalidate()
        saveTimer = nil
        streams.forEach { $0.stop() }
        streams.removeAll()
        store.save()
        statusText = "已停止"
    }

    private func startMonitoring() {
        for scope in NetworkScope.allCases {
            let stream = NettopStream(scope: scope)
            stream.onSample = { [weak self] rows in
                Task { @MainActor [weak self] in
                    self?.receive(rows, for: scope)
                }
            }
            stream.onStatus = { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.streamStatuses[scope] = message
                    if self.selectedScope == scope {
                        self.statusText = message
                    }
                }
            }
            streams.append(stream)
            stream.start()
        }

        saveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.save()
            }
        }
        statusText = "正在记录 · 数据仅保存在本机"
    }

    private func receive(_ rows: [NettopRow], for scope: NetworkScope) {
        let now = Date()
        let previous = lastSampleAt[scope] ?? now.addingTimeInterval(-2)
        let elapsed = max(0.5, now.timeIntervalSince(previous))
        lastSampleAt[scope] = now

        let deltas = rows.compactMap { row -> AppUsageDelta? in
            guard row.bytesIn > 0 || row.bytesOut > 0 else { return nil }
            let identity = identityResolver.resolve(pid: row.pid, processName: row.processName, now: now)
            return AppUsageDelta(
                appKey: identity.key,
                appName: identity.name,
                bundlePath: identity.bundlePath,
                downloaded: row.bytesIn,
                uploaded: row.bytesOut
            )
        }

        let downloaded = deltas.reduce(Int64(0)) { $0 + $1.downloaded }
        let uploaded = deltas.reduce(Int64(0)) { $0 + $1.uploaded }
        rates[scope] = (Double(downloaded) / elapsed, Double(uploaded) / elapsed)
        store.record(deltas, scope: scope, at: now)

        if selectedScope == scope {
            refresh()
        }
    }

    private func refresh() {
        let now = Date()
        let totals = store.totals(scope: selectedScope, period: selectedPeriod, now: now, customStart: customStartDate, customEnd: customEndDate)
        totalDownloaded = totals.downloaded
        totalUploaded = totals.uploaded
        appSummaries = store.apps(scope: selectedScope, period: selectedPeriod, now: now, customStart: customStartDate, customEnd: customEndDate)
        chartPoints = store.chart(scope: selectedScope, period: selectedPeriod, now: now, customStart: customStartDate, customEnd: customEndDate)
        let rate = rates[selectedScope] ?? (0, 0)
        downloadRate = rate.download
        uploadRate = rate.upload
    }
}
