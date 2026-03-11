import Foundation

enum NetScopeFormatters {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let shortNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter
    }()

    static func rate(bitsPerSecond: Double) -> String {
        let value = max(bitsPerSecond, 0)

        if value >= 1_000_000_000 {
            return "\(numberString(value / 1_000_000_000)) Gbps"
        }
        if value >= 1_000_000 {
            return "\(numberString(value / 1_000_000)) Mbps"
        }
        if value >= 1_000 {
            return "\(numberString(value / 1_000)) Kbps"
        }
        return "\(Int(value.rounded())) bps"
    }

    static func compactRate(bitsPerSecond: Double) -> String {
        let value = max(bitsPerSecond, 0) / 1_000_000
        return "\(shortNumberString(value))M"
    }

    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func ping(_ ms: Double) -> String {
        "\(numberString(ms)) ms"
    }

    static func megabits(_ mbps: Double) -> String {
        "\(numberString(mbps)) Mbps"
    }

    private static func numberString(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private static func shortNumberString(_ value: Double) -> String {
        shortNumberFormatter.string(from: NSNumber(value: value)) ?? "0.0"
    }
}
