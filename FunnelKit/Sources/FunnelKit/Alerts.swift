import Foundation

public struct FunnelAlert: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case conversionDrop, eventSpike, eventDip, retentionDrop
    }

    public var id: String
    public var kind: Kind
    public var projectID: String
    public var projectName: String
    public var date: Date
    /// The funnel or event it is about.
    public var subject: String
    /// The new number: a rate for conversion and retention, a count of users otherwise.
    public var value: Double
    /// What it was, or what a normal day looks like.
    public var baseline: Double
}

/// Which alerts are on, and how far a number must move to raise one.
public struct AlertRules: Codable, Sendable, Hashable {
    public var enabled: [FunnelAlert.Kind: Bool]
    /// Fall of a funnel's conversion against the period before, 0.2 = down a fifth.
    public var conversionDrop: Double
    /// The same for D7 retention.
    public var retentionDrop: Double
    /// How unusual a day must be. Higher means fewer alerts.
    public var unusualDay: Double

    public static let standard = AlertRules(
        enabled: Dictionary(uniqueKeysWithValues: FunnelAlert.Kind.allCases.map { ($0, true) }),
        conversionDrop: 0.2, retentionDrop: 0.2, unusualDay: 3.5
    )

    public func isOn(_ kind: FunnelAlert.Kind) -> Bool { enabled[kind] ?? true }
}

/// Turns a report into alerts. An alert's id holds its day or week, so it fires once.
public enum AlertRulesEngine {
    static func weekStamp(_ date: Date) -> String {
        let parts = Day.utc.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(parts.yearForWeekOfYear ?? 0)w\(parts.weekOfYear ?? 0)"
    }

    public static func alerts(_ report: ProjectReport, rules: AlertRules, now: Date) -> [FunnelAlert] {
        var found: [FunnelAlert] = []
        let project = report.project, week = weekStamp(now)
        func add(_ kind: FunnelAlert.Kind, _ key: String, subject: String, value: Double, baseline: Double, date: Date = now) {
            guard rules.isOn(kind) else { return }
            found.append(FunnelAlert(
                id: "\(project.id).\(kind.rawValue).\(key)", kind: kind, projectID: project.id, projectName: project.name,
                date: date, subject: subject, value: value, baseline: baseline
            ))
        }

        for funnel in report.funnels {
            guard let before = funnel.previousConversion, let change = funnel.change, change <= -rules.conversionDrop,
                  funnel.entered >= Analytics.smallSample, funnel.previousEntered >= Analytics.smallSample else { continue }
            add(.conversionDrop, "\(funnel.id).\(week)", subject: funnel.name, value: funnel.conversion, baseline: before)
        }

        if let last = report.dailyUsers.last, let anomaly = report.anomalies.last, anomaly.date == last.date,
           max(anomaly.value, anomaly.expected) >= Analytics.smallSample {
            let up = anomaly.value > anomaly.expected
            add(up ? .eventSpike : .eventDip, Day.string(anomaly.date), subject: report.keyEvent ?? "", value: anomaly.value, baseline: anomaly.expected, date: anomaly.date)
        }

        if let retention = report.retention, let recent = retention.d7Recent, let baseline = retention.d7Baseline, baseline > 0,
           (baseline - recent) / baseline >= rules.retentionDrop,
           retention.d7RecentSize >= Analytics.smallSample, retention.d7BaselineSize >= Analytics.smallSample {
            add(.retentionDrop, week, subject: retention.returning, value: recent, baseline: baseline)
        }
        return found
    }
}
