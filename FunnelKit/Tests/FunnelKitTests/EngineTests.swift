import Foundation
import Testing
@testable import FunnelKit

/// Counts what the engine asks for.
private actor Counter {
    var queries: [String] = []
    func add(_ name: String) { queries.append(name) }
    func count(_ name: String) -> Int { queries.filter { $0 == name }.count }
    func reset() { queries = [] }
}

private struct FakeSource: AnalyticsSource {
    let counter: Counter
    var failure: FunnelError?
    let project = MPProject(id: "1", name: "App")

    func hit(_ name: String) async throws {
        await counter.add(name)
        if let failure { throw failure }
    }

    func projects() async throws -> [MPProject] { [project] }
    func topEvents(project: MPProject, limit: Int) async throws -> [TopEvent] {
        try await hit("top")
        return [TopEvent(event: "Comma, Event", count: 9), TopEvent(event: "Run", count: 5)]
    }
    func eventNames(project: MPProject) async throws -> [String] {
        try await hit("names")
        return ["Run", "Sign Up"]
    }
    func funnels(project: MPProject) async throws -> [FunnelInfo] {
        try await hit("funnels")
        return (1...5).map { FunnelInfo(id: $0, name: "F\($0)") }
    }
    func funnel(project: MPProject, id: Int, from: String, to: String) async throws -> FunnelResult {
        try await hit("funnel")
        return FunnelResult(conversion: 0.5, steps: [FunnelStep(event: "A", count: 100, conversion: 1), FunnelStep(event: "B", count: 50, conversion: 0.5)])
    }
    func retention(project: MPProject, born: String, returning: String, from: String, to: String, days: Int) async throws -> [RetentionCohort] {
        try await hit("retention")
        return []
    }
    func eventCounts(project: MPProject, events: [String], from: String, to: String, unit: TimeUnit, unique: Bool) async throws -> [String: [DatedValue]] {
        try await hit("counts")
        return [:]
    }
}

private func engine(_ source: FakeSource, preferences: Preferences = Preferences()) -> Engine {
    Engine(source: source, spacing: .milliseconds(0), persists: false, limit: 10_000, preferences: { preferences })
}

@Suite struct EngineTests {
    @Test func aFirstReadStaysSmall() async {
        let counter = Counter()
        var preferences = Preferences()
        preferences.setups["1"] = ProjectSetup(keyEvent: "Run", bornEvent: "Sign Up", returnEvent: "Run")
        let engine = engine(FakeSource(counter: counter), preferences: preferences)
        await engine.refreshDue()
        #expect(await counter.queries.count == 13)
        #expect(await counter.count("funnel") == 6) // three funnels, two periods
        #expect(await engine.report("1")?.funnels.count == 3)
        #expect(await engine.report("1")?.funnelCount == 5)
        #expect(await engine.lastError == nil)
    }

    @Test func nothingIsDueRightAfterARead() async {
        let counter = Counter()
        let engine = engine(FakeSource(counter: counter))
        await engine.refreshDue()
        await counter.reset()
        await engine.refreshDue()
        #expect(await counter.queries.isEmpty)
    }

    @Test func readingTheCacheSpendsNoQueries() async {
        let counter = Counter()
        let engine = engine(FakeSource(counter: counter))
        await engine.refreshDue()
        await counter.reset()
        _ = await engine.portfolio()
        _ = await engine.report("1")
        #expect(await counter.queries.isEmpty)
    }

    @Test func refreshButtonRightAfterAReadSpendsNothing() async {
        let counter = Counter()
        let engine = engine(FakeSource(counter: counter))
        await engine.refreshDue()
        await counter.reset()
        await engine.refresh()
        await engine.refresh(project: "1")
        #expect(await counter.queries.isEmpty)
    }

    @Test func anEventWithACommaIsNeverTheKeyEvent() async {
        let engine = engine(FakeSource(counter: Counter()))
        await engine.refreshDue()
        let report = await engine.report("1")
        #expect(report?.keyEvent == "Run")
        #expect(report?.keyEventIsGuess == true)
    }

    @Test func noRetentionQueryUntilBothEventsArePicked() async {
        let counter = Counter()
        let engine = engine(FakeSource(counter: counter))
        await engine.refreshDue()
        #expect(await counter.count("retention") == 0)
        #expect(await engine.report("1")?.retention == nil)
    }

    @Test func aSettingsChangeReadsOnlyThatProject() async {
        let counter = Counter()
        final class Box: @unchecked Sendable { var value = Preferences() }
        let box = Box()
        let engine = Engine(source: FakeSource(counter: counter), spacing: .milliseconds(0), persists: false, limit: 10_000, preferences: { box.value })
        await engine.refreshDue()
        await counter.reset()
        await engine.settingsChanged()
        #expect(await counter.queries.isEmpty)
        box.value.setups["1"] = ProjectSetup(keyEvent: "Sign Up")
        await engine.settingsChanged()
        #expect(await counter.count("counts") > 0)
        #expect(await engine.report("1")?.keyEvent == "Sign Up")
    }

    @Test func aRateLimitStopsTheReadAndWaits() async {
        let counter = Counter()
        let engine = engine(FakeSource(counter: counter, failure: .rateLimited(900)))
        await engine.refreshDue()
        #expect(await counter.queries.count == 1)
        #expect(await engine.lastError == .rateLimited(900))
        let paused = await engine.budget().pausedUntil
        #expect(paused != nil)
        #expect((paused ?? .now).timeIntervalSinceNow > 800)
    }

    @Test func signedOutReachesTheApp() async {
        let engine = engine(FakeSource(counter: Counter(), failure: .signedOut))
        await engine.refreshDue()
        #expect(await engine.lastError == .signedOut)
    }

    @Test func untrackedProjectsAreNotRead() async {
        let counter = Counter()
        var preferences = Preferences()
        preferences.trackedProjects = []
        let engine = engine(FakeSource(counter: counter), preferences: preferences)
        await engine.refreshDue()
        #expect(await counter.queries.isEmpty)
    }

    @Test func theDemoGivesAFullPortfolio() async {
        let engine = Engine(source: DemoSource(), spacing: .milliseconds(0), persists: false, limit: 100_000, preferences: { DemoSource.preferences })
        await engine.refreshDue()
        let portfolio = await engine.portfolio()
        #expect(portfolio.reports.count == 4)
        #expect(portfolio.reports[0].project.name == "Tempo Run")
        #expect(portfolio.reports[0].retention?.d7 != nil)
        #expect(portfolio.reports[0].insights.stickiness != nil)
        #expect(portfolio.reports[0].funnels.count == 3)
        #expect(portfolio.reports.last?.project.name == "Moss Budget")
        #expect(portfolio.reports.last?.funnels.isEmpty == true)
        #expect(!(await engine.recentAlerts()).isEmpty)
    }
}

@Suite(.serialized) struct DiskTests {
    @Test func cacheIsPrivateAndSurvivesARestart() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("FunnelRadarTests-\(UUID().uuidString)")
        setenv("FUNNELRADAR_HOME", home.path, 1)
        defer {
            unsetenv("FUNNELRADAR_HOME")
            try? FileManager.default.removeItem(at: home)
        }
        let counter = Counter()
        let engine = Engine(source: FakeSource(counter: counter), spacing: .milliseconds(0), limit: 10_000, preferences: { Preferences() })
        await engine.refreshDue()
        let attributes = try FileManager.default.attributesOfItem(atPath: Paths.cache.path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
        let file = try FileManager.default.attributesOfItem(atPath: Paths.cache.appendingPathComponent("reports.json").path)
        #expect(file[.posixPermissions] as? Int == 0o600)

        await counter.reset()
        let second = Engine(source: FakeSource(counter: counter), spacing: .milliseconds(0), limit: 10_000, preferences: { Preferences() })
        #expect(await second.report("1")?.funnels.count == 3)
        await second.refreshDue()
        #expect(await counter.queries.isEmpty)
    }
}

@Suite struct HubTests {
    @Test func parsesARequest() {
        let text = "POST /v1/refresh HTTP/1.1\r\nAuthorization: Bearer abc\r\nContent-Length: 2\r\n\r\n{}"
        let request = Hub.parse(Data(text.utf8))
        #expect(request?.method == "POST")
        #expect(request?.path == "/v1/refresh")
        #expect(request?.authorization == "Bearer abc")
        #expect(request?.body.count == 2)
    }

    @Test func waitsForTheWholeBody() {
        #expect(Hub.parse(Data("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n{}".utf8)) == nil)
    }

    @Test func theSummaryDropsTheHeavySeries() {
        var report = ProjectReport(project: MPProject(id: "1", name: "A"))
        report.dailyUsers = (0..<90).map { DatedValue(date: Date(timeIntervalSince1970: Double($0) * 86400), value: 1) }
        report.eventNames = ["A"]
        let light = Hub.summary(Analytics.portfolio([report]))
        #expect(light.reports[0].dailyUsers.count == 30)
        #expect(light.reports[0].eventNames.isEmpty)
    }
}
