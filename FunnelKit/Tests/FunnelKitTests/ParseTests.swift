import Foundation
import Testing
@testable import FunnelKit

/// The JSON shapes documented in mixpanel-headless 0.4.0's source. None of this came from an account.
private func data(_ text: String) -> Data { Data(text.utf8) }

@Suite struct ParseTests {
    @Test func projectsReadTheirZone() throws {
        let projects = try MPParse.projects(data(#"""
        [{"id": "3713224", "name": "Tempo", "organization_id": 12, "timezone": "Europe/Istanbul", "is_active": true},
         {"id": 42, "name": null, "organization_id": 12, "timezone": null, "is_active": false}]
        """#))
        #expect(projects.count == 2)
        #expect(projects[0].zone.identifier == "Europe/Istanbul")
        #expect(projects[1].id == "42")
        #expect(projects[1].name == "42")
        #expect(projects[1].zone == Day.utcZone)
    }

    @Test func noisyOutputStillParses() throws {
        let projects = try MPParse.projects(data("Refreshing…\n[{\"id\": \"1\", \"name\": \"A\"}]"))
        #expect(projects.count == 1)
    }

    @Test func topEvents() throws {
        let events = try MPParse.topEvents(data(#"[{"event": "Page View", "count": 15234, "percent_change": 12.5}, {"event": "Login", "count": 8921, "percent_change": -3.2}]"#))
        #expect(events.map(\.event) == ["Page View", "Login"])
        #expect(events[0].count == 15234)
    }

    @Test func eventNames() throws {
        #expect(try MPParse.eventNames(data(#"["Sign Up", "Login"]"#)) == ["Sign Up", "Login"])
    }

    @Test func funnelsNewestFirstWhenDatesAreKnown() throws {
        let list = try MPParse.funnels(data(#"[{"funnel_id": 1, "name": "A"}, {"funnel_id": 2, "name": "B"}, {"funnel_id": 3, "name": "C"}]"#))
        let dates = try MPParse.modifiedDates(data(#"[{"id": 3, "name": "C", "type": "funnels", "modified": "2024-01-15T10:30:00"}, {"id": 2, "name": "B", "type": "funnels", "modified": "2024-03-01T00:00:00"}]"#))
        #expect(MPParse.byRecency(list, modified: dates).map(\.id) == [2, 3, 1])
        #expect(MPParse.byRecency(list, modified: [:]).map(\.id) == [1, 2, 3])
    }

    @Test func funnelResult() throws {
        let result = try MPParse.funnel(data(#"""
        {"funnel_id": 12345, "funnel_name": "", "from_date": "2025-01-01", "to_date": "2025-01-31", "conversion_rate": 0.23,
         "steps": [{"event": "Sign Up", "count": 10000, "conversion_rate": 1.0}, {"event": "Verify Email", "count": 7500, "conversion_rate": 0.75}]}
        """#))
        #expect(result.conversion == 0.23)
        #expect(result.steps.count == 2)
        #expect(result.steps[1].conversion == 0.75)
    }

    @Test func emptyFunnel() throws {
        let result = try MPParse.funnel(data(#"{"funnel_id": 1, "conversion_rate": 0.0, "steps": []}"#))
        #expect(result.steps.isEmpty)
    }

    @Test func retentionCohortsInOrder() throws {
        let cohorts = try MPParse.retention(data(#"""
        {"born_event": "Sign Up", "return_event": "Login", "unit": "day",
         "cohorts": [{"date": "2025-01-02", "size": 480, "retention": [1.0, 0.62]}, {"date": "2025-01-01", "size": 500, "retention": [1.0, 0.65, 0.45]}]}
        """#))
        #expect(cohorts.map(\.size) == [500, 480])
        #expect(cohorts[0].retention[2] == 0.45)
    }

    @Test func eventCountsSorted() throws {
        let series = try MPParse.eventCounts(data(#"""
        {"events": ["Login"], "from_date": "2025-01-01", "to_date": "2025-01-02", "unit": "day", "type": "unique",
         "series": {"Login": {"2025-01-02": 610, "2025-01-01": 520, "not a date": 1}}}
        """#))
        #expect(series["Login"]?.map(\.value) == [520, 610])
    }

    @Test func monthKeys() throws {
        let series = try MPParse.eventCounts(data(#"{"series": {"A": {"2025-02": 9, "2025-01-01T00:00:00": 7}}}"#))
        #expect(series["A"]?.map(\.value) == [7, 9])
    }

    @Test func answersOfAnotherShapeGiveNothing() throws {
        #expect(try MPParse.eventCounts(data(#"{"unexpected": true}"#)).isEmpty)
        #expect(try MPParse.topEvents(data(#"{"unexpected": true}"#)).isEmpty)
        #expect(throws: FunnelError.self) { try MPParse.funnel(data("not json")) }
    }
}

@Suite struct CLITests {
    private func failure(_ code: Int32, _ stderr: String) -> ProcessResult {
        ProcessResult(code: code, stdout: Data(), stderr: stderr)
    }

    @Test func exitCodesBecomeErrors() {
        #expect(MPCLI.error(from: failure(5, "Rate limited: slow\nWait 120 seconds before retrying.")) == .rateLimited(120))
        #expect(MPCLI.error(from: failure(5, "Rate limited")) == .rateLimited(nil))
        #expect(MPCLI.error(from: failure(2, "Authentication error: bad token")) == .signedOut)
        #expect(MPCLI.error(from: failure(1, "Configuration error: No account configured.\n\nFix one")) == .signedOut)
        #expect(MPCLI.error(from: failure(3, "Query error: nope")) == .failed("Query error: nope"))
        #expect(MPCLI.error(from: failure(2, "Network error reaching Mixpanel")) == .failed("Network error reaching Mixpanel"))
    }

    @Test func theShellCantSteerMP() {
        let storage = URL(fileURLWithPath: "/tmp/mp")
        let env = MPCLI.environment(base: ["PATH": "/bin", "MP_PROJECT_ID": "9", "MP_ACCOUNT": "other", "MP_SECRET": "old"], service: nil, project: "7", storage: storage)
        #expect(env["MP_PROJECT_ID"] == nil)
        #expect(env["MP_ACCOUNT"] == nil)
        #expect(env["MP_SECRET"] == nil)
        #expect(env["PATH"] == "/bin")
        #expect(env["MP_STORAGE_DIR"] == "/tmp/mp")
        #expect(env["COLUMNS"] == "100000")
    }

    @Test func aServiceAccountIsAllFourVariables() {
        let account = ServiceAccount(username: "u", secret: "s", region: "eu")
        let storage = URL(fileURLWithPath: "/tmp/mp")
        let env = MPCLI.environment(base: [:], service: account, project: "7", storage: storage)
        #expect(env["MP_USERNAME"] == "u")
        #expect(env["MP_SECRET"] == "s")
        #expect(env["MP_REGION"] == "eu")
        #expect(env["MP_PROJECT_ID"] == "7")
        #expect(MPCLI.environment(base: [:], service: account, project: nil, storage: storage)["MP_PROJECT_ID"] == "0")
    }
}

@Suite struct InstallerTests {
    @Test func order() {
        #expect(ToolInstaller.plan(uv: "/u", python: "/p", brew: "/b") == .uv("/u"))
        #expect(ToolInstaller.plan(uv: nil, python: "/p", brew: "/b") == .python("/p"))
        #expect(ToolInstaller.plan(uv: nil, python: nil, brew: "/b") == .homebrew("/b"))
        #expect(ToolInstaller.plan(uv: nil, python: nil, brew: nil) == .manual)
    }

    @Test func pythonVersions() {
        #expect(ToolInstaller.isUsable(pythonVersion: "Python 3.10.0"))
        #expect(ToolInstaller.isUsable(pythonVersion: "Python 3.13.5\n"))
        #expect(!ToolInstaller.isUsable(pythonVersion: "Python 3.9.6"))
        #expect(!ToolInstaller.isUsable(pythonVersion: "garbage"))
    }

    @Test func theVersionIsPinned() {
        #expect(ToolInstaller.pin == "mixpanel-headless==0.4.0")
    }

    /// Downloads about 300 MB, so only on request: `FUNNELRADAR_LIVE_INSTALL=<folder with a space>`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUNNELRADAR_LIVE_INSTALL"] != nil)) func realInstall() async throws {
        setenv("FUNNELRADAR_HOME", ProcessInfo.processInfo.environment["FUNNELRADAR_LIVE_INSTALL"]!, 1)
        try await ToolInstaller.install { _ in }
        #expect(await MPCLI().version() == ToolInstaller.version)
        #expect(await MPCLI().signInState() == .signedOut)
    }
}

@Suite struct DayTests {
    @Test func theProjectsZoneDecidesTheDay() {
        // 2026-03-10 23:30 UTC is already the 11th in Istanbul.
        let now = Date(timeIntervalSince1970: 1_773_185_400)
        #expect(Day.lastComplete(now: now, in: Day.utcZone) == "2026-03-09")
        #expect(Day.lastComplete(now: now, in: TimeZone(identifier: "Europe/Istanbul")!) == "2026-03-10")
    }

    @Test func monthsAndEdges() {
        #expect(Day.monthStart(of: "2026-03-10", monthsBack: 3) == "2025-12-01")
        #expect(Day.adding(1, to: "2024-02-28") == "2024-02-29")
        #expect(Day.date("nonsense") == nil)
    }
}
