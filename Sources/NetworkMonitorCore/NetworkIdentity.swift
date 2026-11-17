import CoreLocation
import CoreWLAN
import Foundation
import Network
import SystemConfiguration

/// The network a traffic sample belongs to.
///
/// The ID is based on the router's gateway hardware address when macOS can
/// resolve it. The Wi-Fi SSID is a display label, not the identity: this keeps
/// the same network together while roaming between access points and prevents
/// two unrelated routers with the same SSID from being merged.
public struct NetworkIdentity: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let interfaceName: String?

    public init(id: String, name: String, interfaceName: String? = nil) {
        self.id = id
        self.name = name
        self.interfaceName = interfaceName
    }

    public static let unknown = NetworkIdentity(id: "unknown", name: "未识别网络")
    public static let offline = NetworkIdentity(id: "offline", name: "未连接网络")
}

public enum WiFiNamePermission: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// Reads the SSID only after the user grants macOS Location permission.
/// No location coordinates are requested or stored.
public final class WiFiNameProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let lock = NSLock()
    private var storedPermission: WiFiNamePermission = .notDetermined

    public var onChange: (() -> Void)?

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        refreshPermission()
    }

    public var permission: WiFiNamePermission {
        lock.lock()
        defer { lock.unlock() }
        return storedPermission
    }

    /// Called only after the user explicitly chooses to enable Wi-Fi names.
    @MainActor
    public func requestPermission() {
        refreshPermission()
        guard permission == .notDetermined else { return }
        manager.requestAlwaysAuthorization()
    }

    /// Safe to call from the network monitor's serial queue.
    public func name(onInterface interfaceName: String) -> String? {
        lock.lock()
        let allowed = storedPermission == .authorized
        lock.unlock()
        guard allowed else { return nil }
        return CWWiFiClient.shared().interface(withName: interfaceName)?.ssid()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshPermission()
    }

    private func refreshPermission() {
        let status = manager.authorizationStatus
        let next: WiFiNamePermission
        switch status {
        case .authorizedAlways:
            next = .authorized
        case .notDetermined:
            next = .notDetermined
        default:
            next = .denied
        }

        lock.lock()
        let changed = storedPermission != next
        storedPermission = next
        lock.unlock()

        if changed {
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }
}

/// Watches the active macOS network and emits a stable identity when it changes.
public final class NetworkIdentityMonitor {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.networkmonitor.network-identity")
    private let wifiNames: WiFiNameProvider
    private let lock = NSLock()

    private var lastPath: NWPath?
    private var debounce: DispatchWorkItem?
    private var serviceStore: SCDynamicStore?
    private var storedIdentity = NetworkIdentity.unknown

    public var onChange: ((NetworkIdentity) -> Void)?

    public init(wifiNames: WiFiNameProvider) {
        self.wifiNames = wifiNames
    }

    public var currentIdentity: NetworkIdentity {
        lock.lock()
        defer { lock.unlock() }
        return storedIdentity
    }

    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lastPath = path
            self.scheduleEvaluation(path)
        }
        pathMonitor.start(queue: queue)
        watchServices()
    }

    public func stop() {
        debounce?.cancel()
        if let serviceStore {
            SCDynamicStoreSetDispatchQueue(serviceStore, nil)
        }
        serviceStore = nil
        pathMonitor.cancel()
    }

    /// Re-evaluates the last path when Location permission changes.
    public func refresh() {
        queue.async { [weak self] in
            guard let self, let path = self.lastPath else { return }
            self.evaluate(path)
        }
    }

    private func scheduleEvaluation(_ path: NWPath) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate(path) }
        debounce = work
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// A DHCP lease or gateway can change without NWPathMonitor reporting a
    /// different path, so also watch configd's IPv4/DHCP service state.
    private func watchServices() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(nil, "NetworkMonitor" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<NetworkIdentityMonitor>.fromOpaque(info).takeUnretainedValue().servicesChanged()
        }, &context) else { return }

        SCDynamicStoreSetNotificationKeys(
            store,
            nil,
            ["State:/Network/Service/[^/]+/(IPv4|DHCP)"] as CFArray
        )
        SCDynamicStoreSetDispatchQueue(store, queue)
        serviceStore = store
    }

    /// Called on the monitor's serial queue.
    private func servicesChanged() {
        guard let lastPath else { return }
        scheduleEvaluation(lastPath)
    }

    private func evaluate(_ path: NWPath) {
        guard path.status == .satisfied else {
            publish(.offline)
            return
        }

        let route = GatewayProbe.defaultRoute()
        let interface = route.interfaceName.flatMap { routeName in
            path.availableInterfaces.first { $0.name == routeName }
        } ?? path.availableInterfaces.first {
            path.usesInterfaceType($0.type) &&
            ($0.type == .wifi || $0.type == .wiredEthernet || $0.type == .cellular)
        }
        let interfaceName = route.interfaceName ?? interface?.name
        let gatewayIP = route.gatewayIP
        let gatewayMAC = gatewayIP.flatMap(GatewayProbe.macAddress(forGateway:))

        let id: String
        if let gatewayMAC {
            id = "gw:\(gatewayMAC)"
        } else if let interfaceName {
            id = gatewayIP.map { "if:\(interfaceName)@\($0)" } ?? "if:\(interfaceName)"
        } else {
            id = "unknown"
        }

        let isWiFi = interface.map { $0.type == .wifi } ?? path.usesInterfaceType(.wifi)
        let isWired = interface.map { $0.type == .wiredEthernet } ?? path.usesInterfaceType(.wiredEthernet)
        let isCellular = interface.map { $0.type == .cellular } ?? path.usesInterfaceType(.cellular)
        let ssid = isWiFi ? interfaceName.flatMap { wifiNames.name(onInterface: $0) } : nil
        let baseName: String
        if isWiFi {
            baseName = "Wi-Fi"
        } else if isWired {
            baseName = "有线网络"
        } else if isCellular {
            baseName = "个人热点"
        } else {
            baseName = "网络"
        }

        let fallbackName: String
        if let gatewayMAC {
            fallbackName = "\(baseName) · \(gatewayMAC.replacingOccurrences(of: ":", with: "").suffix(4))"
        } else if let interfaceName {
            fallbackName = "\(baseName) · \(interfaceName)"
        } else {
            fallbackName = baseName
        }

        let displayName = ssid?.isEmpty == false ? ssid! : fallbackName
        publish(NetworkIdentity(id: id, name: displayName, interfaceName: interfaceName))
    }

    private func publish(_ identity: NetworkIdentity) {
        lock.lock()
        let changed = storedIdentity != identity
        storedIdentity = identity
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in self?.onChange?(identity) }
    }
}

/// Resolves the default router without sending network information to a service.
private enum GatewayProbe {
    struct DefaultRoute {
        let gatewayIP: String?
        let interfaceName: String?
    }

    static func defaultRoute() -> DefaultRoute {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return DefaultRoute(gatewayIP: nil, interfaceName: nil)
            }

            var gatewayIP: String?
            var interfaceName: String?
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if key == "gateway", !value.isEmpty { gatewayIP = value }
                if key == "interface", !value.isEmpty { interfaceName = value }
            }
            return DefaultRoute(gatewayIP: gatewayIP, interfaceName: interfaceName)
        } catch {
            return DefaultRoute(gatewayIP: nil, interfaceName: nil)
        }
    }

    static func macAddress(forGateway gateway: String) -> String? {
        // configd can take a moment to resolve the router after Wi-Fi associates.
        for attempt in 0..<5 {
            if let address = configdMACAddress(forGateway: gateway) { return address }
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.2) }
        }
        return nil
    }

    private static func configdMACAddress(forGateway gateway: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "NetworkMonitor" as CFString, nil, nil),
              let states = SCDynamicStoreCopyMultiple(
                store, nil, ["State:/Network/Service/[^/]+/IPv4"] as CFArray
              ) as? [String: Any] else { return nil }

        for value in states.values {
            guard let state = value as? [String: Any],
                  state["ARPResolvedIPAddress"] as? String == gateway,
                  let address = state["ARPResolvedHardwareAddress"] as? String,
                  address.contains(":") else { continue }
            return address.lowercased()
        }
        return nil
    }
}
