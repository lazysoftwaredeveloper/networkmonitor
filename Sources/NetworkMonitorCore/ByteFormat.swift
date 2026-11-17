import Foundation

public enum ByteFormat {
    public static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1 else { return "0 B/s" }
        let amount = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .memory)
        return "\(amount)/s"
    }
}
