import Foundation

public struct DatedValue: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct Anomaly: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var value: Double
    public var expected: Double
    public var id: Date { date }
}

/// A top event this week against last week.
public struct Mover: Codable, Sendable, Hashable, Identifiable {
    public var event: String
    public var thisWeek: Double
    public var lastWeek: Double
    /// 0.1 = +10 %. Nil for an event that had nothing last week.
    public var change: Double?
    public var id: String { event }
}

/// The step of a funnel that keeps the smallest share of the people who reached the step before it.
public struct FunnelLeak: Codable, Sendable, Hashable {
    /// Index into the funnel's steps, never 0.
    public var step: Int
    public var fromEvent: String
    public var toEvent: String
    /// 0…1, the share who went on.
    public var kept: Double
    /// People who reached `fromEvent` and not `toEvent`.
    public var lost: Double
}

public struct FunnelReport: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var steps: [FunnelStep]
    /// First step to last, 0…1, in the period `from`…`to`.
    public var conversion: Double
    /// The same in the period before, when anyone entered it.
    public var previousConversion: Double?
    public var entered: Double
    public var previousEntered: Double
    public var leak: FunnelLeak?
    public var from: String
    public var to: String

    /// Relative: 0.1 = conversion is a tenth higher than the period before.
    public var change: Double? {
        guard let previousConversion, previousConversion > 0 else { return nil }
        return (conversion - previousConversion) / previousConversion
    }
}

public struct RetentionRow: Codable, Sendable, Hashable, Identifiable {
    /// The Monday the cohorts' week begins.
    public var week: Date
    public var size: Double
    /// One per `RetentionReport.days`. Nil where the week's cohorts are too young to know.
    public var cells: [Double?]
    public var id: Date { week }
}

public struct RetentionReport: Codable, Sendable, Hashable {
    public var born: String
    public var returning: String
    public var d1: Double?
    public var d7: Double?
    public var d30: Double?
    /// D7 of the newest two weeks of cohorts old enough to have one, and of the four weeks before.
    public var d7Recent: Double?
    public var d7Baseline: Double?
    public var d7RecentSize: Double
    public var d7BaselineSize: Double
    /// The days that `RetentionRow.cells` show.
    public var days: [Int]
    public var rows: [RetentionRow]
    /// Share still returning on day n, every day from 1 to 30, where known.
    public var curve: [DatedDay]

    public struct DatedDay: Codable, Sendable, Hashable, Identifiable {
        public var day: Int
        public var value: Double
        public var id: Int { day }
    }
}

public struct Insights: Codable, Sendable, Hashable {
    /// Average daily users of the key event over the last 7 full days.
    public var activeUsers: Double?
    /// The same for the 7 days before.
    public var previousActiveUsers: Double?
    /// 0.1 = +10 %.
    public var activeChange: Double?
    /// DAU/MAU of the last full month, 0…1.
    public var stickiness: Double?
    /// The month that number is about.
    public var stickinessMonth: Date?
    public var stickinessByMonth: [DatedValue]
    /// Monday first. 1 = an average day.
    public var weekdayIndex: [Double]
    public var bestWeekday: Int?
    /// A straight line through the last 60 days, drawn 30 days on. A trend, not a forecast.
    public var trend: [DatedValue]
    /// 0…1. How well that line fits.
    public var trendFit: Double?

    public static let empty = Insights(
        activeUsers: nil, previousActiveUsers: nil, activeChange: nil, stickiness: nil, stickinessMonth: nil,
        stickinessByMonth: [], weekdayIndex: [], bestWeekday: nil, trend: [], trendFit: nil
    )
}

public struct ProjectReport: Codable, Sendable, Hashable, Identifiable {
    public var project: MPProject
    /// When anything was last read for this project; nil until something has been.
    public var updatedAt: Date?
    /// When the day-based reports below were last read.
    public var deepUpdatedAt: Date?
    /// What those reports were read for: their last day and the events picked. A new key means read again.
    public var deepKey: String?
    /// The last full day in the project's time zone that the reports reach.
    public var lastDay: String?
    public var topEvents: [TopEvent]
    public var eventNames: [String]
    public var movers: [Mover]
    public var keyEvent: String?
    /// True while the key event is the busiest one rather than one picked in Settings.
    public var keyEventIsGuess: Bool
    public var dailyUsers: [DatedValue]
    public var monthlyUsers: [DatedValue]
    public var funnels: [FunnelReport]
    /// How many saved funnels the project has; FunnelRadar reads at most three.
    public var funnelCount: Int
    public var retention: RetentionReport?
    public var anomalies: [Anomaly]
    public var insights: Insights
    public var id: String { project.id }

    public init(project: MPProject) {
        self.project = project
        topEvents = []
        eventNames = []
        movers = []
        keyEventIsGuess = false
        dailyUsers = []
        monthlyUsers = []
        funnels = []
        funnelCount = 0
        anomalies = []
        insights = .empty
    }
}

/// A leak or a mover named with its project, for the list across projects.
public struct PortfolioLeak: Codable, Sendable, Hashable, Identifiable {
    public var projectID: String
    public var projectName: String
    public var funnel: FunnelReport
    public var id: String { "\(projectID).\(funnel.id)" }
}

public struct PortfolioMover: Codable, Sendable, Hashable, Identifiable {
    public var projectID: String
    public var projectName: String
    public var mover: Mover
    public var id: String { "\(projectID).\(mover.event)" }
}

/// One project's daily users as an index, 100 = its own start. Projects count different events and
/// can share people, so indexes can be compared and the counts can't be added.
public struct IndexedSeries: Codable, Sendable, Hashable, Identifiable {
    public var projectID: String
    public var projectName: String
    public var points: [DatedValue]
    public var id: String { projectID }
}

public struct Portfolio: Codable, Sendable, Hashable {
    public var reports: [ProjectReport]
    public var indexed: [IndexedSeries]
    public var movers: [PortfolioMover]
    public var leaks: [PortfolioLeak]
    /// The newest read of any project.
    public var updatedAt: Date?

    public static let empty = Portfolio(reports: [], indexed: [], movers: [], leaks: [], updatedAt: nil)

    public init(reports: [ProjectReport], indexed: [IndexedSeries], movers: [PortfolioMover], leaks: [PortfolioLeak], updatedAt: Date?) {
        self.reports = reports
        self.indexed = indexed
        self.movers = movers
        self.leaks = leaks
        self.updatedAt = updatedAt
    }
}
