import Foundation

public struct NettopRow: Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let bytesIn: Int64
    public let bytesOut: Int64

    public init(pid: Int32, processName: String, bytesIn: Int64, bytesOut: Int64) {
        self.pid = pid
        self.processName = processName
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Reads the CSV rows emitted by nettop in per-process, delta mode.
public struct NettopParser {
    private var buffer = ""
    private var pending: [NettopRow] = []
    private var discardedInitialSample = false

    public init() {}

    public mutating func consume(_ text: String) -> [[NettopRow]] {
        buffer += text
        var completed: [[NettopRow]] = []

        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: newline)...])

            if Self.isHeader(line) {
                if let sample = closeSample() {
                    completed.append(sample)
                }
            } else if let row = Self.parseRow(line) {
                pending.append(row)
            }
        }
        return completed
    }

    /// Closes a sample after nettop's output has been quiet for a short interval.
    /// A partial CSV line is kept until the next read rather than being truncated.
    public mutating func flush() -> [NettopRow]? {
        guard buffer.isEmpty else { return nil }
        return closeSample()
    }

    public mutating func reset() {
        buffer = ""
        pending = []
        discardedInitialSample = false
    }

    private mutating func closeSample() -> [NettopRow]? {
        guard !pending.isEmpty else { return nil }
        defer { pending = [] }

        // With -d, nettop's first non-empty sample is the baseline, not a delta.
        guard discardedInitialSample else {
            discardedInitialSample = true
            return nil
        }
        return pending
    }

    public static func isHeader(_ line: String) -> Bool {
        line.hasPrefix("time,") || line.hasPrefix(",bytes_in")
    }

    /// Process identifiers are emitted as "process-name.pid". Read the byte
    /// counters from the right so commas in a process name do not shift columns.
    public static func parseRow(_ line: String) -> NettopRow? {
        guard !line.isEmpty else { return nil }
        var fields = line.components(separatedBy: ",")
        while fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count >= 4 else { return nil }

        let bytesOut = Int64(fields.removeLast().trimmingCharacters(in: .whitespaces)) ?? 0
        let bytesIn = Int64(fields.removeLast().trimmingCharacters(in: .whitespaces)) ?? 0
        let identifier = fields.dropFirst().joined(separator: ",")
            .trimmingCharacters(in: .whitespaces)
        guard let dot = identifier.lastIndex(of: "."),
              let pid = Int32(identifier[identifier.index(after: dot)...]),
              pid > 0
        else { return nil }

        let name = String(identifier[..<dot])
        guard !name.isEmpty else { return nil }
        return NettopRow(pid: pid, processName: name, bytesIn: max(0, bytesIn), bytesOut: max(0, bytesOut))
    }
}
