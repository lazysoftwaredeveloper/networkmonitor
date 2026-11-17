import Foundation

public enum ByteFormat {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        let amount = ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .memory)
        return "\(amount)/s"
    }
}
