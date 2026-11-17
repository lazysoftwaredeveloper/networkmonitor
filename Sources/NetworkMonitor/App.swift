import AppKit
import SwiftUI
import NetworkMonitorCore

@main
struct NetworkMonitorApp: App {
    @StateObject private var model = MonitorModel()

    var body: some Scene {
        WindowGroup("Network Monitor", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
        }
        .defaultSize(width: 1020, height: 780)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.arrow.up")
                Text(model.downloadRateText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPanel: View {
    @EnvironmentObject private var model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(Color.accentColor)
                Text("Network Monitor")
                    .font(.headline)
                Spacer()
                Circle().fill(.green).frame(width: 7, height: 7)
            }

            HStack(spacing: 12) {
                rateCard("应用下载", value: model.downloadRateText, symbol: "arrow.down", tint: .blue)
                rateCard("应用上传", value: model.uploadRateText, symbol: "arrow.up", tint: .orange)
            }

            Divider()
            HStack {
                Text("\(model.selectedPeriod.title)应用下载")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.bytes(model.totalDownloaded))
                    .monospacedDigit()
            }
            HStack {
                Text("\(model.selectedPeriod.title)应用上传")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.bytes(model.totalUploaded))
                    .monospacedDigit()
            }

            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开流量统计", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func rateCard(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
