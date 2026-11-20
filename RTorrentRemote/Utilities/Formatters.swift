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

    /// Elapsed time such as "3 d 4 h" or "12 min" (two most significant units).
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let d = total / 86_400, h = (total % 86_400) / 3_600, m = (total % 3_600) / 60
        if d > 0 { return h > 0 ? "\(d) d \(h) h" : "\(d) d" }
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
