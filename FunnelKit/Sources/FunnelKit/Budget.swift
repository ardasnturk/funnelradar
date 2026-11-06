import Foundation

/// Mixpanel's Query API allows 60 queries an hour and 5 at once, shared with everything else on
/// the project. This counts FunnelRadar's over a rolling hour and stays well under it.
public struct QueryBudget: Codable, Sendable, Hashable {
    /// Never more than this in an hour, whatever is asked for: other tools need the rest.
    public static let ceiling = 40
    static let window: TimeInterval = 3600

    public var limit: Int
    public private(set) var stamps: [Date]

    public init(limit: Int, stamps: [Date] = []) {
        self.limit = limit
        self.stamps = stamps
    }

    public func used(at now: Date) -> Int {
        stamps.filter { now.timeIntervalSince($0) < Self.window }.count
    }

    /// The earliest moment a query may go.
    public func nextSlot(at now: Date) -> Date {
        let recent = stamps.filter { now.timeIntervalSince($0) < Self.window }.sorted()
        guard recent.count >= limit else { return now }
        return recent[recent.count - limit].addingTimeInterval(Self.window)
    }

    public mutating func record(at now: Date) {
        stamps = stamps.filter { now.timeIntervalSince($0) < Self.window } + [now]
    }
}

/// Waiting time after a 429. Mixpanel's window is an hour, so hammering it again soon helps nobody.
struct Backoff: Sendable {
    static let base: TimeInterval = 300
    static let longest: TimeInterval = 3600
    private(set) var failures = 0

    mutating func next(retryAfter: Int?) -> TimeInterval {
        failures += 1
        let doubled = min(Self.longest, Self.base * pow(2, Double(failures - 1)))
        return max(doubled, TimeInterval(retryAfter ?? 0))
    }

    mutating func reset() { failures = 0 }
}

/// One query at a time, spaced apart, within the budget. Spacing keeps the hour's budget from
/// going in one burst; running one at a time keeps well under Mixpanel's limit of 5 at once.
actor RateLimiter {
    private let spacing: Duration
    private var budget: QueryBudget
    private var next: Date
    private var pausedUntil: Date?

    init(spacing: Duration, budget: QueryBudget) {
        self.spacing = spacing
        self.budget = budget
        next = .distantPast
    }

    func take() async throws {
        while true {
            let now = Date.now
            let slot = max(next, budget.nextSlot(at: now), pausedUntil ?? .distantPast)
            if slot <= now {
                budget.record(at: now)
                next = now.addingTimeInterval(TimeInterval(spacing.components.seconds) + Double(spacing.components.attoseconds) / 1e18)
                return
            }
            try await Task.sleep(for: .seconds(slot.timeIntervalSince(now)))
        }
    }

    func pause(_ seconds: TimeInterval) -> Date {
        let until = Date.now.addingTimeInterval(seconds)
        pausedUntil = max(pausedUntil ?? until, until)
        return pausedUntil!
    }

    func setLimit(_ limit: Int) { budget.limit = limit }
    func used() -> Int { budget.used(at: .now) }
    func snapshot() -> QueryBudget { budget }
    func waitingUntil() -> Date? { pausedUntil.flatMap { $0 > .now ? $0 : nil } }
}
