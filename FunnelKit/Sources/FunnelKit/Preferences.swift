import Foundation

/// What a person picked for one project. Empty is fine: the busiest event stands in as the key
/// event, and retention waits for its two events.
public struct ProjectSetup: Codable, Sendable, Hashable {
    public var keyEvent: String?
    public var bornEvent: String?
    public var returnEvent: String?

    public init(keyEvent: String? = nil, bornEvent: String? = nil, returnEvent: String? = nil) {
        self.keyEvent = keyEvent
        self.bornEvent = bornEvent
        self.returnEvent = returnEvent
    }
}

/// Settings the app and the hub share, in `preferences.json`. A field a newer or older version
/// doesn't know keeps its default, so an update never loses the rest.
public struct Preferences: Codable, Sendable, Hashable {
    public var setupFinished = false
    /// Projects to follow; nil means all of them.
    public var trackedProjects: [String]?
    public var refreshHours = 2
    public var queriesPerHour = QueryBudget.ceiling
    public var setups: [String: ProjectSetup] = [:]
    public var alerts = AlertRules.standard
    public var notifyOnMac = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case setupFinished, trackedProjects, refreshHours, queriesPerHour, setups, alerts, notifyOnMac
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setupFinished = (try? c.decodeIfPresent(Bool.self, forKey: .setupFinished)) ?? false
        trackedProjects = try? c.decodeIfPresent([String].self, forKey: .trackedProjects)
        refreshHours = (try? c.decodeIfPresent(Int.self, forKey: .refreshHours)) ?? 2
        queriesPerHour = (try? c.decodeIfPresent(Int.self, forKey: .queriesPerHour)) ?? QueryBudget.ceiling
        setups = (try? c.decodeIfPresent([String: ProjectSetup].self, forKey: .setups)) ?? [:]
        alerts = (try? c.decodeIfPresent(AlertRules.self, forKey: .alerts)) ?? .standard
        notifyOnMac = (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnMac)) ?? true
    }

    public static func load() -> Preferences {
        guard let data = try? Data(contentsOf: Paths.preferences),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return preferences
    }

    public func save() throws {
        Paths.prepare()
        try Paths.writePrivately(try JSONEncoder().encode(self), to: Paths.preferences)
    }
}
