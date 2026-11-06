import Foundation

/// Made-up apps for screenshots and for trying FunnelRadar without an account (`--demo`).
/// Answers the same questions as `mp`, so all of FunnelRadar's calculations run on it.
public struct DemoSource: AnalyticsSource {
    public init() {}

    private struct App: Sendable {
        var project: MPProject
        var users: Double
        var growth: Double
        var age: Int
        var keyEvent: String
        var born: String?
        var returning: String?
        var events: [(name: String, share: Double, drift: Double)]
        var funnels: [(info: FunnelInfo, steps: [(String, Double)], slip: Double)]
    }

    private static let apps: [App] = [
        App(
            project: MPProject(id: "1000001", name: "Tempo Run", timezone: "Europe/Istanbul"), users: 3_840, growth: 0.0022, age: 400,
            keyEvent: "Run Started", born: "Sign Up", returning: "Run Started",
            events: [("Run Started", 1, 0.03), ("Screen View", 6.2, 0.01), ("Run Finished", 0.74, 0.02), ("Plan Opened", 0.41, 0.17), ("Share Tapped", 0.09, -0.21), ("Paywall Viewed", 0.18, 0.06)],
            funnels: [
                (FunnelInfo(id: 501, name: "Onboarding to First Run", modified: "2026-10-20T09:00:00"), [("Sign Up", 1), ("Goal Set", 0.71), ("Plan Picked", 0.62), ("First Run", 0.31)], 0),
                (FunnelInfo(id: 502, name: "Trial to Paid", modified: "2026-09-02T09:00:00"), [("Paywall Viewed", 1), ("Trial Started", 0.22), ("Subscribed", 0.46)], 0.26),
                (FunnelInfo(id: 503, name: "Invite a Friend", modified: "2026-03-11T09:00:00"), [("Share Tapped", 1), ("Invite Sent", 0.54), ("Invite Accepted", 0.38)], 0),
            ]
        ),
        App(
            project: MPProject(id: "1000002", name: "Kite Reader", timezone: "America/New_York"), users: 1_260, growth: 0.0008, age: 400,
            keyEvent: "Article Opened", born: "Install", returning: "Article Opened",
            events: [("Article Opened", 1, -0.04), ("Feed Refreshed", 3.1, 0.01), ("Highlight Saved", 0.28, 0.12), ("Search Used", 0.2, -0.09)],
            funnels: [(FunnelInfo(id: 601, name: "Reader to Subscriber", modified: "2026-08-14T09:00:00"), [("Article Opened", 1), ("Paywall Viewed", 0.17), ("Subscribed", 0.09)], 0)]
        ),
        App(
            project: MPProject(id: "1000003", name: "Pine Journal", timezone: "Europe/Berlin"), users: 690, growth: -0.0019, age: 400,
            keyEvent: "Entry Written", born: nil, returning: nil,
            events: [("Entry Written", 1, -0.12), ("Prompt Opened", 1.8, -0.03), ("Mood Logged", 0.66, 0.04)],
            funnels: [(FunnelInfo(id: 701, name: "First Week", modified: nil), [("Sign Up", 1), ("First Entry", 0.58), ("Third Entry", 0.33)], 0.05)]
        ),
        App(
            project: MPProject(id: "1000004", name: "Moss Budget", timezone: "UTC"), users: 48, growth: 0.012, age: 12,
            keyEvent: "Expense Added", born: nil, returning: nil,
            events: [("Expense Added", 1, 0.3), ("Budget Viewed", 1.4, 0.2)],
            funnels: []
        ),
    ]

    /// The events picked for the demo apps, as a person would in Settings.
    public static var preferences: Preferences {
        var preferences = Preferences()
        preferences.setupFinished = true
        for app in apps {
            preferences.setups[app.project.id] = ProjectSetup(keyEvent: app.keyEvent, bornEvent: app.born, returnEvent: app.returning)
        }
        return preferences
    }

    private func app(_ project: MPProject) throws -> App {
        guard let app = Self.apps.first(where: { $0.project.id == project.id }) else { throw FunnelError.failed("Unknown demo project") }
        return app
    }

    /// A repeatable wobble, so the charts don't change on every refresh.
    private static func wobble(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// Whole days since 1970, a day's fixed number.
    private static func index(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 86400) }

    private static func users(_ app: App, on date: Date) -> Double {
        let today = index(.now), day = index(date), back = today - day
        guard back <= app.age else { return 0 }
        let weekday = Day.utc.component(.weekday, from: date)
        let week: Double = weekday == 1 || weekday == 7 ? 0.82 : (weekday == 3 ? 1.1 : 1)
        var value = app.users * pow(1 + app.growth, -Double(back)) * week * (0.93 + wobble(day, app.users) * 0.14)
        // One striking day, so the marks and the alert have something to show.
        if app.project.id == "1000001", back == 9 { value *= 1.75 }
        if app.project.id == "1000002", back == 1 { value *= 0.5 }
        return value.rounded()
    }

    public func projects() async throws -> [MPProject] { Self.apps.map(\.project) }

    public func topEvents(project: MPProject, limit: Int) async throws -> [TopEvent] {
        let app = try app(project)
        let hour = Double(Calendar.current.component(.hour, from: .now) + 1) / 24
        return Array(app.events.sorted { $0.share > $1.share }.prefix(limit)).map {
            TopEvent(event: $0.name, count: (app.users * $0.share * 1.6 * hour).rounded())
        }
    }

    public func eventNames(project: MPProject) async throws -> [String] {
        let app = try app(project)
        return (app.events.map(\.name) + app.funnels.flatMap { $0.steps.map(\.0) } + [app.born].compactMap { $0 }).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        .sorted()
    }

    public func funnels(project: MPProject) async throws -> [FunnelInfo] {
        try app(project).funnels.map(\.info)
    }

    public func funnel(project: MPProject, id: Int, from: String, to: String) async throws -> FunnelResult {
        let app = try app(project)
        guard let funnel = app.funnels.first(where: { $0.info.id == id }) else { throw FunnelError.failed("Unknown demo funnel") }
        let isNewest = (Day.date(to).map { Self.index(.now) - Self.index($0) } ?? 99) < 20
        var count = (app.users * 8 * (isNewest ? 1.06 : 1)).rounded()
        var steps: [FunnelStep] = []
        for (index, step) in funnel.steps.enumerated() {
            let rate = index == 0 ? 1 : step.1 * (index == funnel.steps.count - 1 && isNewest ? 1 - funnel.slip : 1)
            count = (count * rate).rounded()
            steps.append(FunnelStep(event: step.0, count: count, conversion: rate))
        }
        let first = steps.first?.count ?? 0
        return FunnelResult(conversion: first > 0 ? count / first : 0, steps: steps)
    }

    public func retention(project: MPProject, born: String, returning: String, from: String, to: String, days: Int) async throws -> [RetentionCohort] {
        let app = try app(project)
        guard let start = Day.date(from), let end = Day.date(to) else { return [] }
        let base = app.project.id == "1000001" ? 0.46 : 0.34
        return stride(from: start, through: end, by: 86400).map { date in
            let back = Self.index(end) - Self.index(date), day = Self.index(date)
            let cells = (0..<min(days, back + 1)).map { n -> Double in
                n == 0 ? 1 : base * pow(Double(n), -0.42) * (0.92 + Self.wobble(day &+ n, 3) * 0.16)
            }
            return RetentionCohort(date: date, size: (app.users * 0.06 * (0.8 + Self.wobble(day, 5) * 0.4)).rounded(), retention: cells)
        }
    }

    public func eventCounts(project: MPProject, events: [String], from: String, to: String, unit: TimeUnit, unique: Bool) async throws -> [String: [DatedValue]] {
        let app = try app(project)
        guard let start = Day.date(from), let end = Day.date(to) else { return [:] }
        var result: [String: [DatedValue]] = [:]
        for event in events {
            let info = app.events.first { $0.name == event }
            let share = info?.share ?? 0.3, drift = info?.drift ?? 0
            let days = stride(from: start, through: end, by: 86400).map { date -> DatedValue in
                let back = Self.index(end) - Self.index(date)
                let shift = back < 7 ? 1 + drift : 1
                return DatedValue(date: date, value: (Self.users(app, on: date) * (unique ? 1 : share) * shift).rounded())
            }
            if unit == .month {
                let calendar = Day.utc
                let months = Dictionary(grouping: days) { calendar.dateInterval(of: .month, for: $0.date)!.start }
                result[event] = months.keys.sorted().map { month in
                    let average = months[month]!.reduce(0) { $0 + $1.value } / Double(months[month]!.count)
                    let sticky = 0.2 + Self.wobble(Self.index(month), app.users) * 0.05 + (app.project.id == "1000001" ? 0.06 : 0)
                    return DatedValue(date: month, value: (average / sticky).rounded())
                }
            } else {
                result[event] = days
            }
        }
        return result
    }
}
