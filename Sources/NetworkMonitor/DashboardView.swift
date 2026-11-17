import AppKit
import Charts
import SwiftUI
import NetworkMonitorCore

public struct DashboardView: View {
    @EnvironmentObject private var model: MonitorModel

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filters
                    metrics
                    chartCard
                    appList
                    footnote
                }
                .padding(26)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 880, minHeight: 700)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Network Monitor")
                    .font(.system(size: 19, weight: .semibold))
                Text("网络流量统计")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(model.statusText.contains("失败") || model.statusText.contains("无法") || model.statusText.contains("退出") || model.statusText.contains("重试") ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(model.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.55), in: Capsule())
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("网络类型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("网络类型", selection: $model.selectedScope) {
                        ForEach(NetworkScope.allCases) { scope in
                            Label(scope.title, systemImage: scope.symbol).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 470)
                }

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 7) {
                    Text("统计周期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("统计周期", selection: $model.selectedPeriod) {
                        ForEach(UsagePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 330)
                }
            }

            if model.selectedPeriod == .custom {
                HStack(spacing: 10) {
                    Text("日期范围")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("开始日期", selection: $model.customStartDate,
                               in: ...model.customEndDate, displayedComponents: .date)
                        .labelsHidden()
                    Text("至")
                        .foregroundStyle(.secondary)
                    DatePicker("结束日期", selection: $model.customEndDate,
                               in: model.customStartDate...Date(), displayedComponents: .date)
                        .labelsHidden()
                }
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("具体网络")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("具体网络", selection: $model.selectedNetworkID) {
                        Text(model.selectedScope == .wifi ? "所有 Wi-Fi" : "所有网络")
                            .tag(MonitorModel.allNetworksID)
                        ForEach(model.availableNetworks) { network in
                            Text("\(network.name) · \(ByteFormat.bytes(network.total))")
                                .tag(network.id)
                        }
                    }
                    .frame(maxWidth: 360)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 7) {
                    Text("当前连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label(model.currentNetwork.name, systemImage: "wifi")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        if model.canRequestWiFiNamePermission {
                            Button("启用 Wi-Fi 名称") {
                                model.requestWiFiNamePermission()
                            }
                            .controlSize(.small)
                        } else if model.needsLocationSettings {
                            Button("定位权限设置") {
                                model.openLocationSettings()
                            }
                            .controlSize(.small)
                        } else {
                            Text("名称读取已授权")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "应用下载", value: ByteFormat.bytes(model.totalDownloaded),
                       detail: model.selectedPeriod.title, symbol: "arrow.down.circle.fill", tint: .blue)
            MetricCard(title: "应用上传", value: ByteFormat.bytes(model.totalUploaded),
                       detail: model.selectedPeriod.title, symbol: "arrow.up.circle.fill", tint: .orange)
            MetricCard(title: "实时应用下载", value: model.downloadRateText,
                       detail: "当前速度", symbol: "arrow.down.to.line", tint: .blue)
            MetricCard(title: "实时应用上传", value: model.uploadRateText,
                       detail: "当前速度", symbol: "arrow.up.to.line", tint: .orange)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("应用流量趋势")
                        .font(.system(size: 16, weight: .semibold))
                    Text("按应用进程归因的下载与上传")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    legend(color: .blue, title: "下载")
                    legend(color: .orange, title: "上传")
                }
            }

            Chart {
                ForEach(model.chartPoints) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("下载", point.downloaded),
                        series: .value("方向", "下载")
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("上传", point.uploaded),
                        series: .value("方向", "上传")
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: 205)
        }
        .padding(19)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1))
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("应用流量排行")
                        .font(.system(size: 16, weight: .semibold))
                    Text("按下载与上传总量排序")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.appSummaries.count) 个应用 / 进程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.appSummaries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂时没有流量记录")
                        .font(.system(size: 14, weight: .medium))
                    Text("产生网络活动后，这里会显示各应用的下载和上传用量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.appSummaries.enumerated()), id: \.element.id) { index, app in
                        AppUsageRow(app: app, maximum: model.maxAppTotal)
                        if index != model.appSummaries.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(19)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1))
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
            Text("应用用量来自 macOS nettop 的进程统计。短连接及部分系统活动可能无法完全归因；网络身份优先使用本机解析到的网关硬件地址。读取 Wi-Fi 名称需要你主动授予定位服务权限，但应用不会请求或保存 GPS 位置。历史数据从本应用开始记录时起算。")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))
    }
}

private struct AppUsageRow: View {
    let app: AppUsageSummary
    let maximum: Int64

    var body: some View {
        HStack(spacing: 12) {
            appIcon
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(ByteFormat.bytes(app.total))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ProgressView(value: Double(app.total), total: Double(maximum))
                    .tint(Color.accentColor)
                    .scaleEffect(x: 1, y: 0.75, anchor: .center)
                HStack(spacing: 13) {
                    Label(ByteFormat.bytes(app.downloaded), systemImage: "arrow.down")
                        .foregroundStyle(.secondary)
                    Label(ByteFormat.bytes(app.uploaded), systemImage: "arrow.up")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10))
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = app.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: app.id == "system" ? "gearshape.2.fill" : "terminal")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
