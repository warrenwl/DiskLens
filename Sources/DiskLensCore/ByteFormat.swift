import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func gib(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GiB", value)
    }
}
