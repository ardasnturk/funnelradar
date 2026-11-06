import Foundation
import Testing
@testable import FunnelKit

private let dayLength: TimeInterval = 86400
private let lastDay = Day.date("2026-06-30")!
private func days(_ values: [Double], end: Date = lastDay) -> [DatedValue] {
    values.enumerated().map { DatedValue(date: end.addingTimeInterval(Double($0.offset - values.count + 1) * dayLength), value: $0.element) }
}
private func step(_ event: String, _ count: Double) -> FunnelStep { FunnelStep(event: event, count: count, conversion: 0) }

@Suite struct TrendTests {
    @Test func trendFollowsAStraightLine() {
        let line = Analytics.trend(days((0..<60).map { 100 + Double($0) * 2 }), days: 10)
        #expect(line.fit! > 0.999)
        #expect(abs(line.points.last!.value - (218 + 20)) < 0.01)
    }

    @Test func trendNeedsTwoWeeks() {
        #expect(Analytics.trend(days([1, 2, 3]), days: 14).points.isEmpty)
    }

    @Test func trendStopsAtZero() {
        #expect(Analytics.trend(days((0..<30).map { 300 - Double($0) * 10 }), days: 90).points.allSatisfy { $0.value >= 0 })
    }

    @Test func anomalyFindsTheOutlierAndIgnoresNoise() {
        var values = (0..<40).map { 100 + Double($0 % 5) }
        values[35] = 400
        let found = Analytics.anomalies(days(values))
        #expect(found.count == 1)
        #expect(found[0].value == 400)
    }

    @Test func anomaliesWaitForFourWeeks() {
        #expect(Analytics.anomalies(days([1, 900, 1])).isEmpty)
    }

    @Test func weekdayIndexAveragesToOne() {
        let index = Analytics.weekdayIndex(days((0..<28).map { Double($0 % 7 + 1) }))
        #expect(index.count == 7)
        #expect(abs(index.reduce(0, +) / 7 - 1) < 0.0001)
    }

    @Test func weekdayIndexNeedsEveryDay() {
        #expect(Analytics.weekdayIndex(days([1, 2, 3])).isEmpty)
    }

    @Test func activeUsersComparesWeeks() {
        let result = Analytics.activeUsers(days([Double](repeating: 100, count: 7) + [Double](repeating: 110, count: 7)))
        #expect(result.current == 110)
        #expect(result.previous == 100)
        #expect(abs(result.change! - 0.1) < 0.0001)
    }

    @Test func zerosBeforeTheFirstEventAreNotData() {
        #expect(Analytics.trimmed(days([0, 0, 5, 0, 7])).map(\.value) == [5, 0, 7])
        #expect(Analytics.trimmed(days([0, 0])).isEmpty)
    }

    @Test func sparseActiveUsersHasNoChange() {
        let result = Analytics.activeUsers(days([5, 7]))
        #expect(result.current == 6)
        #expect(result.change == nil)
        #expect(Analytics.activeUsers([]).current == nil)
    }
}

@Suite struct StickinessTests {
    private let june = Day.date("2026-06-01")!
    private let july = Day.date("2026-07-01")!

    @Test func isAverageDayOverTheMonth() {
        let result = Analytics.stickiness(daily: days([Double](repeating: 200, count: 30)), monthly: [DatedValue(date: june, value: 1000)])
        #expect(result.count == 1)
        #expect(result[0].value == 0.2)
    }

    @Test func aMonthStillRunningDoesntCount() {
        let daily = days([Double](repeating: 200, count: 40), end: Day.date("2026-07-10")!)
        let result = Analytics.stickiness(daily: daily, monthly: [DatedValue(date: june, value: 1000), DatedValue(date: july, value: 500)])
        #expect(result.map(\.date) == [june])
    }

    @Test func aMonthWithoutItsDaysDoesntCount() {
        #expect(Analytics.stickiness(daily: days([200, 200, 200]), monthly: [DatedValue(date: june, value: 1000)]).isEmpty)
    }

    @Test func noMAUGivesNothing() {
        #expect(Analytics.stickiness(daily: days([0, 0]), monthly: [DatedValue(date: june, value: 0)]).isEmpty)
        #expect(Analytics.stickiness(daily: [], monthly: []).isEmpty)
    }
}

@Suite struct MoverTests {
    private func series(_ last: Double, _ this: Double) -> [DatedValue] {
        days([Double](repeating: last, count: 7) + [Double](repeating: this, count: 7))
    }

    @Test func largestChangeFirst() {
        let result = Analytics.movers(["A": series(100, 110), "B": series(100, 50), "C": series(100, 170)])
        #expect(result.map(\.event) == ["C", "B", "A"])
        #expect(abs(result[1].change! + 0.5) < 0.0001)
    }

    @Test func tinyEventsStayOut() {
        #expect(Analytics.movers(["A": series(1, 2)]).isEmpty)
    }

    @Test func newEventsComeLast() {
        let result = Analytics.movers(["New": series(0, 50), "Old": series(100, 110)])
        #expect(result.map(\.event) == ["Old", "New"])
        #expect(result[1].change == nil)
    }

    @Test func tooFewDaysGivesNothing() {
        #expect(Analytics.movers(["A": days([1000, 2000])]).isEmpty)
    }
}

@Suite struct FunnelTests {
    @Test func theWorstStepIsTheLowestRate() {
        let leak = Analytics.worstLeak([step("A", 1000), step("B", 800), step("C", 200), step("D", 150)])
        #expect(leak?.step == 2)
        #expect(leak?.fromEvent == "B")
        #expect(leak?.toEvent == "C")
        #expect(leak?.kept == 0.25)
        #expect(leak?.lost == 600)
    }

    @Test func equalRatesPickTheMorePeople() {
        #expect(Analytics.worstLeak([step("A", 1000), step("B", 500), step("C", 250)])?.step == 1)
    }

    @Test func noLeakWithoutLoss() {
        #expect(Analytics.worstLeak([step("A", 10), step("B", 10)]) == nil)
        #expect(Analytics.worstLeak([step("A", 0), step("B", 0)]) == nil)
        #expect(Analytics.worstLeak([step("A", 10)]) == nil)
        #expect(Analytics.worstLeak([]) == nil)
    }

    @Test func comparesWithThePeriodBefore() {
        let current = FunnelResult(conversion: 0, steps: [step("A", 100), step("B", 8)])
        let previous = FunnelResult(conversion: 0, steps: [step("A", 100), step("B", 10)])
        let report = Analytics.funnelReport(info: FunnelInfo(id: 1, name: "F"), current: current, previous: previous, from: "a", to: "b")
        #expect(report.conversion == 0.08)
        #expect(report.previousConversion == 0.1)
        #expect(abs(report.change! + 0.2) < 0.0001)
    }

    @Test func aPeriodNobodyEnteredHasNoComparison() {
        let current = FunnelResult(conversion: 0, steps: [step("A", 100), step("B", 8)])
        let previous = FunnelResult(conversion: 0, steps: [step("A", 0), step("B", 0)])
        let report = Analytics.funnelReport(info: FunnelInfo(id: 1, name: "F"), current: current, previous: previous, from: "a", to: "b")
        #expect(report.previousConversion == nil)
        #expect(report.change == nil)
    }

    @Test func anEmptyFunnelIsFine() {
        let report = Analytics.funnelReport(info: FunnelInfo(id: 1, name: "F"), current: FunnelResult(conversion: 0, steps: []), previous: nil, from: "a", to: "b")
        #expect(report.entered == 0)
        #expect(report.leak == nil)
    }
}

@Suite struct RetentionTests {
    private func cohort(_ back: Int, size: Double, cells: [Double]) -> RetentionCohort {
        RetentionCohort(date: lastDay.addingTimeInterval(-Double(back) * dayLength), size: size, retention: cells)
    }
    private let curve = (0...30).map { $0 == 0 ? 1 : 0.5 }

    @Test func dayNIsElementN() {
        var cells = curve
        cells[1] = 0.6
        cells[7] = 0.3
        cells[30] = 0.1
        let report = Analytics.retention([cohort(40, size: 100, cells: cells)], born: "B", returning: "R", lastDay: lastDay)
        #expect(report?.d1 == 0.6)
        #expect(report?.d7 == 0.3)
        #expect(report?.d30 == 0.1)
    }

    @Test func weightedBySize() {
        let cells = [Double](repeating: 0.2, count: 31), others = [Double](repeating: 0.5, count: 31)
        let report = Analytics.retention([cohort(40, size: 300, cells: cells), cohort(41, size: 100, cells: others)], born: "B", returning: "R", lastDay: lastDay)
        #expect(abs(report!.d7! - 0.275) < 0.0001)
    }

    @Test func cohortsTooYoungDontCountAsZero() {
        // Three days old: its day 7 hasn't happened, whatever the array says.
        let young = [1, 0.5, 0.4, 0.3, 0, 0, 0, 0, 0, 0]
        let report = Analytics.retention([cohort(40, size: 100, cells: curve), cohort(3, size: 900, cells: young)], born: "B", returning: "R", lastDay: lastDay)
        #expect(report?.d7 == 0.5)
        #expect(abs(report!.d1! - 0.5) < 0.0001)
    }

    @Test func aShortArrayDoesntCrash() {
        let report = Analytics.retention([cohort(40, size: 100, cells: [1, 0.5])], born: "B", returning: "R", lastDay: lastDay)
        #expect(report?.d1 == 0.5)
        #expect(report?.d7 == nil)
    }

    @Test func noPeopleNoReport() {
        #expect(Analytics.retention([cohort(40, size: 0, cells: curve)], born: "B", returning: "R", lastDay: lastDay) == nil)
        #expect(Analytics.retention([], born: "B", returning: "R", lastDay: lastDay) == nil)
    }

    @Test func recentCohortsAreComparedWithTheOnesBefore() {
        let low = [Double](repeating: 0.1, count: 31), high = [Double](repeating: 0.4, count: 31)
        let cohorts = (8..<22).map { cohort($0, size: 10, cells: low) } + (22..<50).map { cohort($0, size: 10, cells: high) }
        let report = Analytics.retention(cohorts, born: "B", returning: "R", lastDay: lastDay)
        #expect(abs(report!.d7Recent! - 0.1) < 0.0001)
        #expect(abs(report!.d7Baseline! - 0.4) < 0.0001)
        #expect(report?.d7RecentSize == 140)
    }

    @Test func weeksBeginOnMonday() {
        // 2026-06-30 is a Tuesday, so the Monday before it is the 29th.
        let report = Analytics.retention([cohort(0, size: 5, cells: [1]), cohort(1, size: 5, cells: [1])], born: "B", returning: "R", lastDay: lastDay)
        #expect(report?.rows.count == 1)
        #expect(report?.rows[0].week == Day.date("2026-06-29"))
        #expect(report?.rows[0].size == 10)
        #expect(report?.rows[0].cells.allSatisfy { $0 == nil } == true)
    }
}

@Suite struct PortfolioTests {
    private func report(_ id: String, users: Double) -> ProjectReport {
        var report = ProjectReport(project: MPProject(id: id, name: id))
        report.dailyUsers = days([Double](repeating: users, count: 30))
        report.insights = Analytics.insights(daily: report.dailyUsers, monthly: [])
        report.updatedAt = Date(timeIntervalSince1970: users)
        return report
    }

    @Test func indexesStartAtAHundred() {
        let line = Analytics.indexed(days((0..<40).map { 100 + Double($0) }))
        #expect(line?.first?.value == 100)
        #expect((line?.last?.value ?? 0) > 100)
    }

    @Test func noIndexFromNothing() {
        #expect(Analytics.indexed(days([1, 2])) == nil)
        #expect(Analytics.indexed(days([Double](repeating: 0, count: 20))) == nil)
    }

    @Test func projectsAreRankedAndNeverAdded() {
        let portfolio = Analytics.portfolio([report("small", users: 10), report("big", users: 1000)])
        #expect(portfolio.reports.map(\.id) == ["big", "small"])
        #expect(portfolio.indexed.count == 2)
        #expect(portfolio.updatedAt == Date(timeIntervalSince1970: 1000))
    }

    @Test func aProjectWithNoDataStillListsLast() {
        let portfolio = Analytics.portfolio([ProjectReport(project: MPProject(id: "empty", name: "E")), report("big", users: 5)])
        #expect(portfolio.reports.map(\.id) == ["big", "empty"])
        #expect(portfolio.indexed.count == 1)
    }

    @Test func nothingAtAll() {
        #expect(Analytics.portfolio([]).reports.isEmpty)
        #expect(Analytics.portfolio([]).updatedAt == nil)
    }

    @Test func worstLeakAcrossProjectsFirst() {
        func funnel(_ id: Int, _ second: Double) -> FunnelReport {
            Analytics.funnelReport(info: FunnelInfo(id: id, name: "F"), current: FunnelResult(conversion: 0, steps: [step("A", 100), step("B", second)]), previous: nil, from: "a", to: "b")
        }
        var a = report("a", users: 2), b = report("b", users: 1)
        a.funnels = [funnel(1, 50)]
        b.funnels = [funnel(2, 10)]
        #expect(Analytics.portfolio([a, b]).leaks.map(\.funnel.id) == [2, 1])
    }
}

@Suite struct AlertTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func base() -> ProjectReport { ProjectReport(project: MPProject(id: "p", name: "P")) }

    private func funnel(rate: Double, was: Double, people: Double = 1000) -> FunnelReport {
        Analytics.funnelReport(
            info: FunnelInfo(id: 9, name: "Checkout"),
            current: FunnelResult(conversion: 0, steps: [step("A", people), step("B", people * rate)]),
            previous: FunnelResult(conversion: 0, steps: [step("A", people), step("B", people * was)]), from: "a", to: "b"
        )
    }

    @Test func conversionDropFires() {
        var report = base()
        report.funnels = [funnel(rate: 0.1, was: 0.2)]
        let alerts = AlertRulesEngine.alerts(report, rules: .standard, now: now)
        #expect(alerts.map(\.kind) == [.conversionDrop])
        #expect(alerts[0].subject == "Checkout")
        #expect(alerts[0].baseline == 0.2)
    }

    @Test func smallMovesAndSmallSamplesDont() {
        var report = base()
        report.funnels = [funnel(rate: 0.19, was: 0.2), funnel(rate: 0.1, was: 0.2, people: 10)]
        #expect(AlertRulesEngine.alerts(report, rules: .standard, now: now).isEmpty)
    }

    @Test func theIDHoldsTheWeekSoItFiresOnce() {
        var report = base()
        report.funnels = [funnel(rate: 0.1, was: 0.2)]
        let first = AlertRulesEngine.alerts(report, rules: .standard, now: now)[0].id
        let sameWeek = AlertRulesEngine.alerts(report, rules: .standard, now: now.addingTimeInterval(3600))[0].id
        let nextWeek = AlertRulesEngine.alerts(report, rules: .standard, now: now.addingTimeInterval(8 * 86400))[0].id
        #expect(first == sameWeek)
        #expect(first != nextWeek)
    }

    @Test func unusualDayOnlyWhenItIsTheLastDay() {
        var report = base()
        report.keyEvent = "Run"
        report.dailyUsers = days([100, 400])
        report.anomalies = [Anomaly(date: lastDay, value: 400, expected: 100)]
        #expect(AlertRulesEngine.alerts(report, rules: .standard, now: now).map(\.kind) == [.eventSpike])
        report.anomalies = [Anomaly(date: lastDay, value: 40, expected: 100)]
        #expect(AlertRulesEngine.alerts(report, rules: .standard, now: now).map(\.kind) == [.eventDip])
        report.anomalies = [Anomaly(date: lastDay.addingTimeInterval(-dayLength), value: 400, expected: 100)]
        #expect(AlertRulesEngine.alerts(report, rules: .standard, now: now).isEmpty)
    }

    @Test func retentionDropFires() {
        var report = base()
        report.retention = RetentionReport(
            born: "B", returning: "R", d1: nil, d7: nil, d30: nil, d7Recent: 0.1, d7Baseline: 0.2,
            d7RecentSize: 500, d7BaselineSize: 900, days: [], rows: [], curve: []
        )
        #expect(AlertRulesEngine.alerts(report, rules: .standard, now: now).map(\.kind) == [.retentionDrop])
    }

    @Test func aTurnedOffKindIsSilent() {
        var report = base()
        report.funnels = [funnel(rate: 0.1, was: 0.2)]
        var rules = AlertRules.standard
        rules.enabled[.conversionDrop] = false
        #expect(AlertRulesEngine.alerts(report, rules: rules, now: now).isEmpty)
    }
}

@Suite struct BudgetTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func staysOpenUntilTheLimit() {
        var budget = QueryBudget(limit: 2)
        #expect(budget.nextSlot(at: now) == now)
        budget.record(at: now)
        #expect(budget.nextSlot(at: now) == now)
        budget.record(at: now.addingTimeInterval(10))
        #expect(budget.nextSlot(at: now.addingTimeInterval(10)) == now.addingTimeInterval(3600))
    }

    @Test func oldQueriesFallOutOfTheHour() {
        var budget = QueryBudget(limit: 1)
        budget.record(at: now)
        #expect(budget.used(at: now.addingTimeInterval(3599)) == 1)
        #expect(budget.used(at: now.addingTimeInterval(3600)) == 0)
    }

    @Test func backoffGrowsAndHonoursTheServer() {
        var backoff = Backoff()
        #expect(backoff.next(retryAfter: nil) == 300)
        #expect(backoff.next(retryAfter: nil) == 600)
        #expect(backoff.next(retryAfter: 3000) == 3000)
        #expect(backoff.next(retryAfter: nil) == 2400)
        #expect(backoff.next(retryAfter: nil) == 3600)
        backoff.reset()
        #expect(backoff.next(retryAfter: nil) == 300)
    }

    @Test func oldPreferencesKeepWhatTheyHave() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"setupFinished": true, "refreshHours": 6, "somethingNew": 1}"#.utf8))
        #expect(preferences.setupFinished)
        #expect(preferences.refreshHours == 6)
        #expect(preferences.queriesPerHour == 40)
        #expect(preferences.alerts == .standard)
    }
}
