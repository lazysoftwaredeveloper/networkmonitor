# Network Monitor for macOS

A small native macOS app focused only on network traffic statistics.

## What it does

- Live download and upload rates in the app and menu bar.
- Per-application download/upload totals.
- Today, last 7 days, last 30 days, and a custom date range.
- Network-type filters: all external traffic, Wi-Fi, wired, and macOS-marked expensive interfaces.
- **Per-network history:** distinguish the Wi-Fi networks you connect to, show their SSID names when permitted, and inspect each network's app-by-app usage.
- Local hourly history stored in Application Support. No account, cloud service, or analytics.

## Data collection

The app uses macOS `nettop` in per-process delta mode. It starts one lightweight stream for each network-type filter, attributes process IDs to their containing `.app` bundle when possible, and aggregates samples into hourly local records.

Network attribution follows the approach used by [kevinabouhanna/NetworkMonitor](https://github.com/kevinabouhanna/NetworkMonitor): the router's gateway hardware address identifies a network, while its Wi-Fi SSID is used as the display name. This avoids merging unrelated routers that happen to use the same SSID and keeps a network together while the Mac roams between access points. If macOS does not expose the gateway hardware address, the app falls back to the active interface and gateway IP.

macOS requires Location permission before an app can read the Wi-Fi SSID. This app asks only after you choose **启用 Wi-Fi 名称** in the dashboard. It reads the network name only; it does not request, collect, or store GPS coordinates. If you decline, traffic is still separated using the router/interface identity and shown with a fallback label such as `Wi-Fi · 1a2b`.

macOS does not expose a public per-process network-usage API. Per-app totals therefore follow the process counters reported by `nettop`; very short-lived sockets and some system activity may not be attributed perfectly. The “Expensive” filter follows macOS's interface classification and is not a guarantee that every carrier hotspot is marked that way.

History starts when the app starts recording. It cannot reconstruct traffic from before installation. Data is kept locally for 120 days. Records created by earlier versions remain available as **旧记录（未按网络区分）**; network-specific attribution begins after this update.

## Build

Requires macOS 13 or later and Xcode Command Line Tools.

```bash
swift build -c release
./Scripts/build-app.sh
open build/NetworkMonitor.app
```

The app is not sandboxed because it launches the macOS `/usr/bin/nettop` utility. It does not require administrator privileges.

## Reference

The collection approach is informed by [kevinabouhanna/NetworkMonitor](https://github.com/kevinabouhanna/NetworkMonitor). This repository is a separate, reduced implementation and does not include that project's firewall, content-filter, connection-map, updater-management, or speed-test features.
