import Foundation

/// The numbers FunnelRadar adds on top of Mixpanel's. Pure functions, so tests can pin them down.
public enum Analytics {
    /// Below this many people a percentage says more about chance than about the product.
    public static let smallSample = 30.0
    public static let retentionColumns = [1, 3, 7, 14, 21, 30]

    // MARK: Trends

    /// Mixpanel fills days before an event existed with zeros. They aren't a quiet start, and would
    /// bend the averages and the trend line of a young project.
    public static func trimmed(_ days: [DatedValue]) -> [DatedValue] {
        Array(days.drop { $0.value == 0 })
    }

    /// Average of the last 7 days against the 7 before. With fewer days, what there is.
    public static func activeUsers(_ days: [DatedValue]) -> (current: Double?, previous: Double?, change: Double?) {
        guard !days.isEmpty else { return (nil, nil, nil) }
        func mean(_ slice: ArraySlice<DatedValue>) -> Double { slice.reduce(0) { $0 + $1.value } / Double(slice.count) }
        let current = mean(days.suffix(7))
        guard days.count >= 14 else { return (current, nil, nil) }
        let previous = mean(days.dropLast(7).suffix(7))
        return (current, previous, previous > 0 ? (current - previous) / previous : nil)
    }

    /// Average of each weekday against the average day, Monday first. Empty without every weekday.
    public static func weekdayIndex<S: Sequence>(_ days: S) -> [Double] where S.Element == DatedValue {
        var sums = [Double](repeating: 0, count: 7), counts = [Double](repeating: 0, count: 7)
        let calendar = Day.utc
        for day in days {
            let index = (calendar.component(.weekday, from: day.date) + 5) % 7
            sums[index] += day.value
            counts[index] += 1
        }
        guard counts.allSatisfy({ $0 > 0 }) else { return [] }
        let averages = zip(sums, counts).map { $0 / $1 }
        let mean = averages.reduce(0, +) / 7
        return mean > 0 ? averages.map { $0 / mean } : []
    }

    /// Least-squares line through `values`, extended `days` past the last point.
    public static func trend<S: Sequence>(_ values: S, days: Int) -> (points: [DatedValue], fit: Double?) where S.Element == DatedValue {
        let values = Array(values)
        guard values.count >= 14, let last = values.last else { return ([], nil) }
        let xs = values.map { $0.date.timeIntervalSince(last.date) / 86400 }, ys = values.map(\.value)
        let n = Double(values.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let syy = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        guard sxx > 0 else { return ([], nil) }
        let slope = sxy / sxx, intercept = meanY - slope * meanX
        let fit: Double = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        let points = stride(from: 0, through: days, by: 5).map { offset in
            DatedValue(date: last.date.addingTimeInterval(Double(offset) * 86400), value: max(0, intercept + slope * Double(offset)))
        }
        return (points, fit)
    }

    /// Days far from the 28 before them, by median absolute deviation, which one big day doesn't skew.
    public static func anomalies(_ days: [DatedValue], threshold: Double = 3.5) -> [Anomaly] {
        guard days.count > 28 else { return [] }
        var found: [Anomaly] = []
        for index in 28..<days.count {
            let window = days[(index - 28)..<index].map(\.value).sorted()
            let median = window[window.count / 2]
            let deviations = window.map { abs($0 - median) }.sorted()
            let mad = deviations[deviations.count / 2]
            guard mad > 0 else { continue }
            let score = 0.6745 * (days[index].value - median) / mad
            if abs(score) >= threshold { found.append(Anomaly(date: days[index].date, value: days[index].value, expected: median)) }
        }
        return found
    }

    /// DAU/MAU per full month: the average day's unique users over the month's unique users. Uniques
    /// can't be summed, so the month's figure has to come from Mixpanel, not from the days.
    public static func stickiness(daily: [DatedValue], monthly: [DatedValue]) -> [DatedValue] {
        guard let lastDay = daily.last?.date else { return [] }
        let calendar = Day.utc
        return monthly.compactMap { month -> DatedValue? in
            guard month.value > 0, let interval = calendar.dateInterval(of: .month, for: month.date),
                  let length = calendar.range(of: .day, in: .month, for: month.date)?.count else { return nil }
            let inside = daily.filter { interval.contains($0.date) }
            // The month has to be over and the days have to cover it.
            guard interval.end.addingTimeInterval(-86400) <= lastDay, inside.count >= length - 1 else { return nil }
            let average = inside.reduce(0) { $0 + $1.value } / Double(inside.count)
            return DatedValue(date: interval.start, value: min(1, average / month.value))
        }
        .sorted { $0.date < $1.date }
    }

    public static func insights(daily: [DatedValue], monthly: [DatedValue]) -> Insights {
        let active = activeUsers(daily)
        let weekday = weekdayIndex(daily.suffix(84))
        let line = trend(daily.suffix(60), days: 30)
        let sticky = stickiness(daily: daily, monthly: monthly)
        return Insights(
            activeUsers: active.current, previousActiveUsers: active.previous, activeChange: active.change,
            stickiness: sticky.last?.value, stickinessMonth: sticky.last?.date, stickinessByMonth: sticky,
            weekdayIndex: weekday, bestWeekday: weekday.isEmpty ? nil : weekday.indices.max { weekday[$0] < weekday[$1] },
            trend: line.points, trendFit: line.fit
        )
    }

    // MARK: Movers

    /// The last 7 full days against the 7 before, largest change first. Events with too little
    /// volume to mean anything are left out; new events follow the rest.
    public static func movers(_ series: [String: [DatedValue]], minimum: Double = 20, limit: Int = 6) -> [Mover] {
        var found: [Mover] = []
        for (event, days) in series where days.count >= 14 {
            let thisWeek = days.suffix(7).reduce(0) { $0 + $1.value }
            let lastWeek = days.dropLast(7).suffix(7).reduce(0) { $0 + $1.value }
            guard max(thisWeek, lastWeek) >= minimum, thisWeek != lastWeek else { continue }
            found.append(Mover(event: event, thisWeek: thisWeek, lastWeek: lastWeek, change: lastWeek > 0 ? (thisWeek - lastWeek) / lastWeek : nil))
        }
        return Array(found.sorted {
            switch ($0.change, $1.change) {
            case let (a?, b?): abs(a) == abs(b) ? $0.event < $1.event : abs(a) > abs(b)
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): $0.event < $1.event
            }
        }
        .prefix(limit))
    }

    // MARK: Funnels

    /// The worst step. Rates come from the counts, because they are what the funnel really did;
    /// a step nobody reached can't leak.
    public static func worstLeak(_ steps: [FunnelStep]) -> FunnelLeak? {
        var worst: FunnelLeak?
        for index in steps.indices.dropFirst() where steps[index - 1].count > 0 {
            let before = steps[index - 1].count
            let kept = min(1, steps[index].count / before)
            let lost = before - min(before, steps[index].count)
            guard lost > 0 else { continue }
            if worst == nil || kept < worst!.kept || (kept == worst!.kept && lost > worst!.lost) {
                worst = FunnelLeak(step: index, fromEvent: steps[index - 1].event, toEvent: steps[index].event, kept: kept, lost: lost)
            }
        }
        return worst
    }

    public static func funnelReport(info: FunnelInfo, current: FunnelResult, previous: FunnelResult?, from: String, to: String) -> FunnelReport {
        let entered = current.steps.first?.count ?? 0
        let previousEntered = previous?.steps.first?.count ?? 0
        return FunnelReport(
            id: info.id, name: info.name, steps: current.steps, conversion: overall(current),
            previousConversion: previousEntered > 0 ? previous.map(overall) : nil,
            entered: entered, previousEntered: previousEntered, leak: worstLeak(current.steps), from: from, to: to
        )
    }

    private static func overall(_ result: FunnelResult) -> Double {
        guard let first = result.steps.first?.count, first > 0, let last = result.steps.last?.count else { return result.conversion }
        return last / first
    }

    // MARK: Retention

    private static func isOldEnough(_ cohort: RetentionCohort, day: Int, lastDay: Date) -> Bool {
        cohort.size > 0 && day < cohort.retention.count && cohort.date.addingTimeInterval(Double(day) * 86400) <= lastDay
    }

    /// Share returning on `day`, weighted by cohort size. A cohort too young to have reached that
    /// day stays out: Mixpanel can report it as 0, and it would pull the number down.
    static func retained<S: Sequence>(_ cohorts: S, day: Int, lastDay: Date) -> Double? where S.Element == RetentionCohort {
        var kept = 0.0, total = 0.0
        for cohort in cohorts where isOldEnough(cohort, day: day, lastDay: lastDay) {
            kept += cohort.retention[day] * cohort.size
            total += cohort.size
        }
        return total > 0 ? kept / total : nil
    }

    /// Nil when no cohort has any people in it.
    public static func retention(_ cohorts: [RetentionCohort], born: String, returning: String, lastDay: Date) -> RetentionReport? {
        guard cohorts.contains(where: { $0.size > 0 }) else { return nil }
        let calendar = Day.utc
        let aged = cohorts.filter { isOldEnough($0, day: 7, lastDay: lastDay) }.sorted { $0.date < $1.date }
        let recent = Array(aged.suffix(14)), baseline = Array(aged.dropLast(14).suffix(28))

        let weeks = Dictionary(grouping: cohorts.filter { $0.size > 0 }) { cohort -> Date in
            let weekday = (calendar.component(.weekday, from: cohort.date) + 5) % 7
            return cohort.date.addingTimeInterval(-Double(weekday) * 86400)
        }
        let rows = weeks.keys.sorted().suffix(10).map { week -> RetentionRow in
            let members = weeks[week]!
            return RetentionRow(
                week: week, size: members.reduce(0) { $0 + $1.size },
                cells: retentionColumns.map { retained(members, day: $0, lastDay: lastDay) }
            )
        }
        let curve = (1...30).compactMap { day in
            retained(cohorts, day: day, lastDay: lastDay).map { RetentionReport.DatedDay(day: day, value: $0) }
        }
        return RetentionReport(
            born: born, returning: returning,
            d1: retained(cohorts, day: 1, lastDay: lastDay), d7: retained(cohorts, day: 7, lastDay: lastDay),
            d30: retained(cohorts, day: 30, lastDay: lastDay),
            d7Recent: retained(recent, day: 7, lastDay: lastDay), d7Baseline: retained(baseline, day: 7, lastDay: lastDay),
            d7RecentSize: recent.reduce(0) { $0 + $1.size }, d7BaselineSize: baseline.reduce(0) { $0 + $1.size },
            days: retentionColumns, rows: rows, curve: curve
        )
    }

    // MARK: Across projects

    /// Daily users as a 7-day average, 100 = the first 7-day average in the window. Nil without
    /// enough data, or when a project started from nothing.
    public static func indexed(_ days: [DatedValue], window: Int = 90) -> [DatedValue]? {
        let days = Array(days.suffix(window + 6))
        guard days.count >= 14 else { return nil }
        let smooth = (6..<days.count).map { index in
            DatedValue(date: days[index].date, value: days[(index - 6)...index].reduce(0) { $0 + $1.value } / 7)
        }
        guard let base = smooth.first?.value, base > 0 else { return nil }
        return smooth.map { DatedValue(date: $0.date, value: $0.value / base * 100) }
    }

    public static func portfolio(_ reports: [ProjectReport]) -> Portfolio {
        let sorted = reports.sorted {
            let a = $0.insights.activeUsers ?? -1, b = $1.insights.activeUsers ?? -1
            return a == b ? $0.project.name < $1.project.name : a > b
        }
        let indexed = sorted.compactMap { report in
            Self.indexed(report.dailyUsers).map { IndexedSeries(projectID: report.id, projectName: report.project.name, points: $0) }
        }
        let movers = sorted.flatMap { report in
            report.movers.map { PortfolioMover(projectID: report.id, projectName: report.project.name, mover: $0) }
        }
        .filter { $0.mover.change != nil }
        .sorted { abs($0.mover.change!) > abs($1.mover.change!) }
        let leaks = sorted.flatMap { report in
            report.funnels.filter { $0.leak != nil }.map { PortfolioLeak(projectID: report.id, projectName: report.project.name, funnel: $0) }
        }
        .sorted { $0.funnel.leak!.kept < $1.funnel.leak!.kept }
        return Portfolio(
            reports: sorted, indexed: indexed, movers: Array(movers.prefix(6)), leaks: Array(leaks.prefix(5)),
            updatedAt: reports.compactMap(\.updatedAt).max()
        )
    }
}
