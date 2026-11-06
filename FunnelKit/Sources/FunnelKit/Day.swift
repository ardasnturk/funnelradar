import Foundation

/// Calendar days as Mixpanel writes them, `yyyy-MM-dd`. A day in a series is its UTC midnight, so
/// the numbers never shift with the Mac's time zone. "Today" is the project's own day.
public enum Day {
    public static let utcZone = TimeZone(identifier: "UTC")!

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcZone
        return calendar
    }

    public static func string(_ date: Date, in zone: TimeZone = utcZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Reads `2025-01-31`, `2025-01-31T00:00:00` and `2025-01`, which is the first of the month.
    public static func date(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").map(String.init)
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        let day = parts.count > 2 ? Int(parts[2]) ?? 1 : 1
        return utc.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func adding(_ days: Int, to text: String) -> String {
        guard let date = date(text), let moved = utc.date(byAdding: .day, value: days, to: date) else { return text }
        return string(moved)
    }

    /// The last day that has ended in `zone`. Today is still filling up, so nothing is computed from it.
    public static func lastComplete(now: Date, in zone: TimeZone) -> String {
        adding(-1, to: string(now, in: zone))
    }

    /// The first day of the month `months` before the one `text` is in.
    public static func monthStart(of text: String, monthsBack months: Int) -> String {
        guard let date = date(text) else { return text }
        var parts = utc.dateComponents([.year, .month], from: date)
        parts.day = 1
        guard let start = utc.date(from: parts), let moved = utc.date(byAdding: .month, value: -months, to: start) else { return text }
        return string(moved)
    }
}
