import Foundation

public enum FunnelError: LocalizedError, Sendable, Equatable {
    case cliMissing
    case signedOut
    /// The Query API said to slow down, with its wait in seconds if it gave one.
    case rateLimited(Int?)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cliMissing: "The mp tool is not installed."
        case .signedOut: "Sign in to Mixpanel again."
        case .rateLimited: "Mixpanel asked to slow down."
        case .failed(let message): message
        }
    }
}

public struct MPProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// An IANA name such as `Europe/Istanbul`. The project's reports use this zone's days.
    public var timezone: String?

    public init(id: String, name: String, timezone: String? = nil) {
        self.id = id
        self.name = name
        self.timezone = timezone
    }

    public var zone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:)) ?? Day.utcZone
    }
}

public struct TopEvent: Codable, Sendable, Hashable, Identifiable {
    public var event: String
    /// Occurrences so far today.
    public var count: Double
    public var id: String { event }

    public init(event: String, count: Double) {
        self.event = event
        self.count = count
    }
}

public struct FunnelInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    /// When the saved report last changed, if Mixpanel says. Newest come first.
    public var modified: String?

    public init(id: Int, name: String, modified: String? = nil) {
        self.id = id
        self.name = name
        self.modified = modified
    }
}

public struct FunnelStep: Codable, Sendable, Hashable, Identifiable {
    public var event: String
    public var count: Double
    /// 0…1, of the step before. 1 on the first step.
    public var conversion: Double
    public var id: String { event }

    public init(event: String, count: Double, conversion: Double) {
        self.event = event
        self.count = count
        self.conversion = conversion
    }
}

public struct FunnelResult: Sendable, Hashable {
    public var conversion: Double
    public var steps: [FunnelStep]

    public init(conversion: Double, steps: [FunnelStep]) {
        self.conversion = conversion
        self.steps = steps
    }
}

public struct RetentionCohort: Sendable, Hashable {
    public var date: Date
    public var size: Double
    /// 0…1. Element n is day n after the cohort's day; element 0 is the day itself.
    public var retention: [Double]

    public init(date: Date, size: Double, retention: [Double]) {
        self.date = date
        self.size = size
        self.retention = retention
    }
}

public enum TimeUnit: String, Sendable { case day, week, month }

/// What the engine may ask for. Every requirement is a read, so nothing can change an account.
public protocol AnalyticsSource: Sendable {
    func projects() async throws -> [MPProject]
    func topEvents(project: MPProject, limit: Int) async throws -> [TopEvent]
    func eventNames(project: MPProject) async throws -> [String]
    /// Saved funnels, the most recently changed first when that is known.
    func funnels(project: MPProject) async throws -> [FunnelInfo]
    func funnel(project: MPProject, id: Int, from: String, to: String) async throws -> FunnelResult
    func retention(project: MPProject, born: String, returning: String, from: String, to: String, days: Int) async throws -> [RetentionCohort]
    /// Dated values per event, oldest first.
    func eventCounts(project: MPProject, events: [String], from: String, to: String, unit: TimeUnit, unique: Bool) async throws -> [String: [DatedValue]]
}
