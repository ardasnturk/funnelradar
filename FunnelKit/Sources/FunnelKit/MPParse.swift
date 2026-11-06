import Foundation

/// Reads `mp`'s JSON. The CLI is a pre-release, so nothing here assumes more than it has to:
/// a missing field gives an empty value and an unknown one is ignored.
enum MPParse {
    /// Lines of chatter before the JSON don't matter.
    static func object(_ data: Data) throws -> Any {
        if let value = try? JSONSerialization.jsonObject(with: data) { return value }
        let text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(where: { $0 == "[" || $0 == "{" }),
           let value = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) {
            return value
        }
        throw FunnelError.failed("mp's answer could not be read.")
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text)
        default: nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    static func rows(_ value: Any) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    static func projects(_ data: Data) throws -> [MPProject] {
        rows(try object(data)).compactMap { row in
            guard let id = string(row["id"]) else { return nil }
            return MPProject(id: id, name: string(row["name"]).flatMap { $0.isEmpty ? nil : $0 } ?? id, timezone: string(row["timezone"]))
        }
    }

    static func topEvents(_ data: Data) throws -> [TopEvent] {
        rows(try object(data)).compactMap { row in
            guard let event = string(row["event"]) else { return nil }
            return TopEvent(event: event, count: number(row["count"]) ?? number(row["amount"]) ?? 0)
        }
    }

    static func eventNames(_ data: Data) throws -> [String] {
        ((try object(data)) as? [Any] ?? []).compactMap { string($0) }
    }

    static func funnels(_ data: Data) throws -> [FunnelInfo] {
        rows(try object(data)).compactMap { row in
            guard let id = number(row["funnel_id"]) ?? number(row["id"]) else { return nil }
            return FunnelInfo(id: Int(id), name: string(row["name"]) ?? "Funnel \(Int(id))")
        }
    }

    /// `mp inspect bookmarks --type funnels`: a saved funnel's id is its bookmark's id.
    static func modifiedDates(_ data: Data) throws -> [Int: String] {
        var dates: [Int: String] = [:]
        for row in rows(try object(data)) {
            if let id = number(row["id"]), let modified = string(row["modified"]) { dates[Int(id)] = modified }
        }
        return dates
    }

    /// Newest first when dates are known. A funnel without one keeps its place after those that have one.
    static func byRecency(_ funnels: [FunnelInfo], modified: [Int: String]) -> [FunnelInfo] {
        let dated = funnels.map { funnel -> FunnelInfo in
            var copy = funnel
            copy.modified = modified[funnel.id]
            return copy
        }
        return dated.filter { $0.modified != nil }.sorted { $0.modified! > $1.modified! } + dated.filter { $0.modified == nil }
    }

    static func funnel(_ data: Data) throws -> FunnelResult {
        guard let root = try object(data) as? [String: Any] else { throw FunnelError.failed("mp's answer could not be read.") }
        let steps = rows(root["steps"] ?? []).enumerated().map { index, row in
            FunnelStep(
                event: string(row["event"]) ?? "Step \(index + 1)",
                count: number(row["count"]) ?? 0,
                conversion: number(row["conversion_rate"]) ?? (index == 0 ? 1 : 0)
            )
        }
        return FunnelResult(conversion: number(root["conversion_rate"]) ?? 0, steps: steps)
    }

    static func retention(_ data: Data) throws -> [RetentionCohort] {
        guard let root = try object(data) as? [String: Any] else { throw FunnelError.failed("mp's answer could not be read.") }
        return rows(root["cohorts"] ?? []).compactMap { row in
            guard let date = string(row["date"]).flatMap(Day.date) else { return nil }
            let cells = (row["retention"] as? [Any] ?? []).map { number($0) ?? 0 }
            return RetentionCohort(date: date, size: number(row["size"]) ?? 0, retention: cells)
        }
        .sorted { $0.date < $1.date }
    }

    static func eventCounts(_ data: Data) throws -> [String: [DatedValue]] {
        guard let root = try object(data) as? [String: Any], let series = root["series"] as? [String: Any] else { return [:] }
        var result: [String: [DatedValue]] = [:]
        for (event, value) in series {
            guard let days = value as? [String: Any] else { continue }
            result[event] = days.compactMap { key, count -> DatedValue? in
                guard let date = Day.date(key) else { return nil }
                return DatedValue(date: date, value: number(count) ?? 0)
            }
            .sorted { $0.date < $1.date }
        }
        return result
    }
}
