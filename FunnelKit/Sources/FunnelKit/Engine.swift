import Foundation

public enum EngineEvent: Sendable {
    case portfolio
    case alert(FunnelAlert)
}

/// What the app and the hub show about the query budget.
public struct BudgetStatus: Codable, Sendable, Hashable {
    public var used: Int
    public var limit: Int
    /// Set while FunnelRadar waits out a 429.
    public var pausedUntil: Date?

    public init(used: Int, limit: Int, pausedUntil: Date?) {
        self.used = used
        self.limit = limit
        self.pausedUntil = pausedUntil
    }
}

/// Reads Mixpanel, keeps the reports on disk and raises alerts. The app runs one in process;
/// without the app, `funnelradar-hub hub` runs it for Remote Code. Only one runs at a time (`Hub`).
///
/// Nearly everything FunnelRadar shows is about days that have ended, so those reports are read
/// once a day (the "deep" read). A refresh between them only asks for today's top events: one
/// query instead of a dozen. Opening a view reads the cache and never Mixpanel.
public actor Engine {
    /// A saved funnel can take days to finish, so the newest days would always look worse than
    /// older ones. Both funnel periods stop this many days before the last full day.
    public static let funnelSettleDays = 7
    public static let funnelPeriodDays = 28
    public static let funnelCap = 3
    /// Days 0 to 30.
    static let retentionIntervals = 31
    static let retentionDays = 90
    static let dailyDays = 182
    static let stickinessMonths = 6
    static let topEventLimit = 8
    /// A manual refresh doesn't spend queries on what was just read.
    static let cooldown: TimeInterval = 300
    static let deepCooldown: TimeInterval = 6 * 3600
    static let retryDelay: TimeInterval = 1800

    private let source: any AnalyticsSource
    private let limiter: RateLimiter
    private let persists: Bool
    private let preferences: @Sendable () -> Preferences
    private let tick: Duration
    private let fixedLimit: Int?
    private var backoff = Backoff()
    private var reports: [String: ProjectReport] = [:]
    private var alerts: [FunnelAlert] = []
    private var fired: Set<String> = []
    private var listeners: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]
    private var loop: Task<Void, Never>?
    private var reading = false
    private var retryAt: [String: Date] = [:]
    public private(set) var lastError: FunnelError?

    public init(
        source: any AnalyticsSource, spacing: Duration = .seconds(5), persists: Bool = true,
        limit: Int? = nil, tick: Duration = .seconds(300),
        preferences: @escaping @Sendable () -> Preferences = { Preferences.load() }
    ) {
        self.source = source
        self.persists = persists
        self.preferences = preferences
        self.tick = tick
        fixedLimit = limit
        var budget = QueryBudget(limit: limit ?? min(QueryBudget.ceiling, preferences().queriesPerHour))
        if persists {
            Self.loadCache(into: &reports, alerts: &alerts, fired: &fired)
            if let data = try? Data(contentsOf: Paths.budget), let saved = try? JSONDecoder().decode(QueryBudget.self, from: data) {
                // Queries sent before a restart still count against the hour.
                budget = QueryBudget(limit: budget.limit, stamps: saved.stamps)
            }
        }
        limiter = RateLimiter(spacing: spacing, budget: budget)
    }

    // MARK: Reading

    public func portfolio() -> Portfolio { Analytics.portfolio(tracked()) }
    public func report(_ id: String) -> ProjectReport? { reports[id] }
    public func recentAlerts() -> [FunnelAlert] { alerts }

    public func budget() async -> BudgetStatus {
        let snapshot = await limiter.snapshot()
        return BudgetStatus(used: await limiter.used(), limit: snapshot.limit, pausedUntil: await limiter.waitingUntil())
    }

    private func tracked() -> [ProjectReport] {
        let wanted = preferences().trackedProjects
        return reports.values.filter { wanted?.contains($0.id) ?? true }
    }

    public func events() -> AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }
    private func post(_ event: EngineEvent) { for listener in listeners.values { listener.yield(event) } }

    // MARK: Running

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self, tick] in
            while !Task.isCancelled {
                await self?.refreshDue()
                try? await Task.sleep(for: tick)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Reads the projects whose time has come. Called by the loop; anything else uses `refresh`.
    func refreshDue() async {
        let hours = Double(max(1, preferences().refreshHours))
        let now = Date.now
        // A new day, or a deep read that failed, doesn't wait for the next refresh.
        let behind = Set(reports.values.filter { report in
            report.deepKey != deepKey(report, lastDay: Day.lastComplete(now: now, in: report.project.zone))
                && (retryAt[report.id] ?? .distantPast) <= now
        }.map(\.id))
        await read { report, now in
            guard let report, let last = report.updatedAt else { return true }
            return behind.contains(report.id) || now.timeIntervalSince(last) >= hours * 3600
        }
    }

    /// The Refresh button, and the hub's. With a project, only that one. It still spends no query
    /// on what was read in the last few minutes.
    public func refresh(project: String? = nil) async {
        await read(manual: true) { report, now in
            if let project, report?.id != project { return false }
            guard let last = report?.updatedAt else { return true }
            return now.timeIntervalSince(last) >= Self.cooldown
        }
    }

    /// Reads at once the projects whose events changed in Settings, if the budget allows.
    public func settingsChanged() async {
        let changed = Set(reports.values.filter { report in
            report.deepKey != deepKey(report, lastDay: report.lastDay ?? "")
        }.map(\.id))
        await read { report, _ in report.map { changed.contains($0.id) } ?? false }
    }

    private func read(manual: Bool = false, where isDue: @Sendable (ProjectReport?, Date) -> Bool) async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        let settings = preferences()
        await limiter.setLimit(fixedLimit ?? min(QueryBudget.ceiling, settings.queriesPerHour))
        var failure: FunnelError?
        do {
            // `mp` answers this from its own cache of the account, so it costs no query.
            let projects = try await source.projects()
            let known = Set(projects.map(\.id))
            reports = reports.filter { known.contains($0.key) }
            for project in projects where settings.trackedProjects?.contains(project.id) ?? true {
                try Task.checkCancellation()
                guard isDue(reports[project.id], .now) else { continue }
                do {
                    try await read(project, manual: manual, settings: settings)
                    retryAt[project.id] = nil
                } catch FunnelError.failed(let message) {
                    // One project's trouble, such as a deleted funnel, doesn't stop the others.
                    failure = .failed(message)
                    retryAt[project.id] = Date.now.addingTimeInterval(Self.retryDelay)
                }
            }
            lastError = failure
        } catch is CancellationError {
        } catch {
            lastError = (error as? FunnelError) ?? .failed(error.localizedDescription)
        }
        save()
        post(.portfolio)
    }

    private func call<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        try await limiter.take()
        do {
            let value = try await work()
            backoff.reset()
            return value
        } catch FunnelError.rateLimited(let seconds) {
            _ = await limiter.pause(backoff.next(retryAfter: seconds))
            throw FunnelError.rateLimited(seconds)
        }
    }

    /// `--events` splits on commas, so an event with one in its name can't be asked for. A guessed
    /// key event stays once made: two events swapping places today mustn't cost a dozen queries.
    private func setup(for report: ProjectReport, settings: Preferences) -> (key: String?, guessed: Bool, born: String?, returning: String?) {
        let setup = settings.setups[report.id] ?? ProjectSetup()
        let isQueryable = { (event: String) in !event.contains(",") }
        let guess = (report.keyEventIsGuess ? report.keyEvent : nil)
            ?? report.topEvents.map(\.event).first(where: isQueryable) ?? report.eventNames.first(where: isQueryable)
        let picked = setup.keyEvent.flatMap { isQueryable($0) ? $0 : nil }
        return (picked ?? guess, picked == nil, setup.bornEvent, setup.returnEvent)
    }

    /// Changes when the reports would come out differently: a new day, or other events.
    private func deepKey(_ report: ProjectReport, lastDay: String) -> String {
        let picks = setup(for: report, settings: preferences())
        return "\(lastDay)|\(picks.key ?? "")|\(picks.born ?? "")|\(picks.returning ?? "")"
    }

    private func read(_ project: MPProject, manual: Bool, settings: Preferences) async throws {
        var report = reports[project.id] ?? ProjectReport(project: project)
        report.project = project
        let now = Date.now
        let lastDay = Day.lastComplete(now: now, in: project.zone)

        report.topEvents = try await call { try await source.topEvents(project: project, limit: Self.topEventLimit) }
        report.updatedAt = now
        reports[project.id] = report

        let key = deepKey(report, lastDay: lastDay)
        let tooSoon = manual && report.deepKey == key && (report.deepUpdatedAt.map { now.timeIntervalSince($0) < Self.deepCooldown } ?? false)
        if report.deepKey != key || (manual && !tooSoon) {
            try await readDeep(&report, lastDay: lastDay, settings: settings, now: now)
            report.deepKey = deepKey(report, lastDay: lastDay)
            report.deepUpdatedAt = now
        }
        reports[project.id] = report
        raiseAlerts(report, settings: settings)
        save()
        post(.portfolio)
    }

    private func readDeep(_ report: inout ProjectReport, lastDay: String, settings: Preferences, now: Date) async throws {
        let project = report.project
        report.lastDay = lastDay
        report.eventNames = try await call { try await source.eventNames(project: project) }
        let picks = setup(for: report, settings: settings)
        report.keyEvent = picks.key
        report.keyEventIsGuess = picks.guessed

        // Movers: two full weeks of the busiest events.
        let moving = report.topEvents.map(\.event).filter { !$0.contains(",") }
        if !moving.isEmpty {
            let from = Day.adding(-13, to: lastDay)
            let series = try await call { try await source.eventCounts(project: project, events: moving, from: from, to: lastDay, unit: .day, unique: false) }
            report.movers = Analytics.movers(series)
        } else {
            report.movers = []
        }

        if let key = picks.key {
            let from = Day.adding(1 - Self.dailyDays, to: lastDay)
            let daily = try await call { try await source.eventCounts(project: project, events: [key], from: from, to: lastDay, unit: .day, unique: true) }
            report.dailyUsers = Analytics.trimmed(daily[key] ?? [])
            let monthFrom = Day.monthStart(of: lastDay, monthsBack: Self.stickinessMonths)
            let monthly = try await call { try await source.eventCounts(project: project, events: [key], from: monthFrom, to: lastDay, unit: .month, unique: true) }
            report.monthlyUsers = monthly[key] ?? []
        } else {
            report.dailyUsers = []
            report.monthlyUsers = []
        }
        report.anomalies = Analytics.anomalies(report.dailyUsers, threshold: settings.alerts.unusualDay)
        report.insights = Analytics.insights(daily: report.dailyUsers, monthly: report.monthlyUsers)

        let funnels = try await call { try await source.funnels(project: project) }
        report.funnelCount = funnels.count
        var funnelReports: [FunnelReport] = []
        let to = Day.adding(-Self.funnelSettleDays, to: lastDay)
        let from = Day.adding(1 - Self.funnelPeriodDays, to: to)
        let previousTo = Day.adding(-1, to: from)
        let previousFrom = Day.adding(1 - Self.funnelPeriodDays, to: previousTo)
        for info in funnels.prefix(Self.funnelCap) {
            let current = try await call { try await source.funnel(project: project, id: info.id, from: from, to: to) }
            let previous = try await call { try await source.funnel(project: project, id: info.id, from: previousFrom, to: previousTo) }
            funnelReports.append(Analytics.funnelReport(info: info, current: current, previous: previous, from: from, to: to))
        }
        report.funnels = funnelReports

        if let born = picks.born, let returning = picks.returning, let last = Day.date(lastDay) {
            let cohorts = try await call {
                try await source.retention(
                    project: project, born: born, returning: returning, from: Day.adding(1 - Self.retentionDays, to: lastDay),
                    to: lastDay, days: Self.retentionIntervals
                )
            }
            report.retention = Analytics.retention(cohorts, born: born, returning: returning, lastDay: last)
        } else {
            report.retention = nil
        }
    }

    private func raiseAlerts(_ report: ProjectReport, settings: Preferences) {
        for alert in AlertRulesEngine.alerts(report, rules: settings.alerts, now: .now) where !fired.contains(alert.id) {
            fired.insert(alert.id)
            alerts.insert(alert, at: 0)
            post(.alert(alert))
        }
        alerts = Array(alerts.prefix(100))
    }

    // MARK: Disk

    private struct AlertFile: Codable {
        var alerts: [FunnelAlert]
        var fired: [String]
    }

    private static func loadCache(into reports: inout [String: ProjectReport], alerts: inout [FunnelAlert], fired: inout Set<String>) {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Paths.cache.appendingPathComponent("reports.json")),
           let list = try? decoder.decode([ProjectReport].self, from: data) {
            reports = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        }
        if let data = try? Data(contentsOf: Paths.alerts), let file = try? decoder.decode(AlertFile.self, from: data) {
            alerts = file.alerts
            fired = Set(file.fired)
        }
    }

    private func save() {
        guard persists else { return }
        Paths.prepare()
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Array(reports.values)) {
            try? Paths.writePrivately(data, to: Paths.cache.appendingPathComponent("reports.json"))
        }
        if let data = try? encoder.encode(AlertFile(alerts: alerts, fired: Array(fired.suffix(2000)))) {
            try? Paths.writePrivately(data, to: Paths.alerts)
        }
        Task { [limiter] in
            if let data = try? JSONEncoder().encode(await limiter.snapshot()) {
                try? Paths.writePrivately(data, to: Paths.budget)
            }
        }
    }

    /// Forgets everything, on sign-out.
    public func reset() {
        reports = [:]
        alerts = []
        fired = []
        try? FileManager.default.removeItem(at: Paths.cache)
        try? FileManager.default.removeItem(at: Paths.alerts)
        try? FileManager.default.removeItem(at: Paths.budget)
        post(.portfolio)
    }
}
