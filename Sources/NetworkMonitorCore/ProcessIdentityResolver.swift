import Foundation
import Darwin

public struct AppIdentity: Equatable, Sendable {
    public let key: String
    public let name: String
    public let bundlePath: String?

    public init(key: String, name: String, bundlePath: String?) {
        self.key = key
        self.name = name
        self.bundlePath = bundlePath
    }
}

/// Resolves nettop's PID to a recognizable app bundle, caching briefly so the
/// process table is not queried for every sample.
final class ProcessIdentityResolver {
    private struct Cached {
        let identity: AppIdentity
        let resolvedAt: Date
    }

    private var cache: [Int32: Cached] = [:]

    func resolve(pid: Int32, processName: String, now: Date = Date()) -> AppIdentity {
        if let cached = cache[pid], now.timeIntervalSince(cached.resolvedAt) < 30 {
            return cached.identity
        }

        let path = Self.executablePath(pid: pid)
        let identity: AppIdentity

        if let path {
            let components = path.split(separator: "/").map(String.init)
            if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                let bundlePath = "/" + components.prefix(appIndex + 1).joined(separator: "/")
                let bundle = Bundle(path: bundlePath)
                let fallback = (components[appIndex] as NSString).deletingPathExtension
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? fallback
                identity = AppIdentity(key: bundlePath, name: displayName, bundlePath: bundlePath)
            } else if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/") {
                identity = AppIdentity(key: "system", name: "macOS 系统进程", bundlePath: nil)
            } else {
                let name = (path as NSString).lastPathComponent
                identity = AppIdentity(key: path, name: name.isEmpty ? processName : name, bundlePath: nil)
            }
        } else {
            identity = AppIdentity(key: "process:\(processName)", name: processName, bundlePath: nil)
        }

        cache[pid] = Cached(identity: identity, resolvedAt: now)
        if cache.count > 2_000 {
            cache = cache.filter { now.timeIntervalSince($0.value.resolvedAt) < 30 }
        }
        return identity
    }

    private static func executablePath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }
}
