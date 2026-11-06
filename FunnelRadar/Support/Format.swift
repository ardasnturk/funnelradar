import Foundation
import FunnelKit

typealias FunnelDay = Day

enum Format {
    static func count(_ value: Double) -> String {
        if abs(value) >= 100_000 {
            return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(0...digits)))
    }

    static func signedPercent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func month(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.wide))
    }

    static func day(_ text: String) -> String {
        guard let date = FunnelDay.date(text) else { return text }
        return date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
    }
}
