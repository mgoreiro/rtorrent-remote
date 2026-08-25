import Foundation

enum Formatters {
    static let byteCounter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        byteCounter.string(fromByteCount: value)
    }

    static func rate(_ bytesPerSecond: Int64) -> String {
        "\(byteCounter.string(fromByteCount: bytesPerSecond))/s"
    }

    static func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    /// Rough remaining-time estimate given bytes left and current rate.
    static func eta(bytesRemaining: Int64, ratePerSecond: Int64) -> String {
        guard ratePerSecond > 0 else { return "—" }
        let seconds = Double(bytesRemaining) / Double(ratePerSecond)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds > 3600 ? [.day, .hour, .minute] : [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "—"
    }
}
