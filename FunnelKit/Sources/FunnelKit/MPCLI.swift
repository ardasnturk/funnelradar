import Foundation

/// A service account for people who don't want the browser sign-in. It lives in the Keychain and
/// reaches `mp` through its environment, so it is never in an argument list or on disk.
public struct ServiceAccount: Codable, Sendable, Hashable {
    public var username: String
    public var secret: String
    public var region: String

    public init(username: String, secret: String, region: String) {
        self.username = username
        self.secret = secret
        self.region = region
    }
}

public enum SignInState: Sendable, Equatable {
    case signedIn
    case signedOut
    /// Mixpanel couldn't be reached, which says nothing about the sign-in.
    case unknown
}

/// Talks to Mixpanel only through the official `mp` CLI, which does the OAuth sign-in and refresh.
/// FunnelRadar never sees a token. `mp` gets a folder of its own, so a sign-in here and one in a
/// terminal don't touch each other.
public struct MPCLI: AnalyticsSource {
    public static let accountName = "funnelradar"

    public init() {}

    func executable() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: Paths.mp.path) else { throw FunnelError.cliMissing }
        return Paths.mp.path
    }

    /// `mp` reads `MP_*` before its own arguments, so whatever the shell set is cleared first.
    /// Rich wraps `mp project list` at 80 columns when it isn't on a terminal, which would break the
    /// JSON inside a long name, hence `COLUMNS`.
    static func environment(base: [String: String], service: ServiceAccount?, project: String?, storage: URL) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("MP_") }
        env["MP_STORAGE_DIR"] = storage.path
        env["MP_CONFIG_PATH"] = storage.appendingPathComponent("config.toml").path
        env["COLUMNS"] = "100000"
        env["NO_COLOR"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        if let service {
            env["MP_USERNAME"] = service.username
            env["MP_SECRET"] = service.secret
            env["MP_REGION"] = service.region
            // All four are needed before `mp` uses them. Listing projects works for any id.
            env["MP_PROJECT_ID"] = project ?? "0"
        }
        return env
    }

    private func environment(project: String?) async -> [String: String] {
        Self.environment(
            base: await ShellEnvironment.shared.environment(), service: KeychainAccount.read(), project: project, storage: Paths.mpStorage
        )
    }

    func run(_ arguments: [String], project: String? = nil, timeout: TimeInterval = 120) async throws -> Data {
        var all = ["--quiet"]
        if let project { all += ["--project", project] }
        all += arguments
        Paths.prepare()
        let result = try await ProcessRunner.run(try executable(), all, environment: await environment(project: project), timeout: timeout)
        guard result.code == 0 else { throw Self.error(from: result) }
        return result.stdout
    }

    static func error(from result: ProcessResult) -> FunnelError {
        let text = result.stderr
        let lower = text.lowercased()
        if result.code == 5 || lower.contains("rate limit") { return .rateLimited(retryAfter(text)) }
        if lower.contains("no account configured") || lower.contains("account not found") { return .signedOut }
        if result.code == 2 {
            if lower.contains("network") || lower.contains("could not reach") { return .failed(firstLine(text, code: result.code)) }
            return .signedOut
        }
        return .failed(firstLine(text, code: result.code))
    }

    static func retryAfter(_ text: String) -> Int? {
        guard let range = text.range(of: #"Wait (\d+) seconds"#, options: .regularExpression) else { return nil }
        return Int(text[range].split(separator: " ")[1])
    }

    private static func firstLine(_ text: String, code: Int32) -> String {
        text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "mp exited with \(code)"
    }

    private static func listing(_ refresh: Bool) -> [String] {
        ["project", "list", "--format", "json"] + (refresh ? ["--refresh"] : [])
    }

    public func projects() async throws -> [MPProject] {
        try MPParse.projects(try await run(Self.listing(false)))
    }

    public func topEvents(project: MPProject, limit: Int) async throws -> [TopEvent] {
        try MPParse.topEvents(try await run(["inspect", "top-events", "--limit", String(limit), "--format", "json"], project: project.id))
    }

    public func eventNames(project: MPProject) async throws -> [String] {
        try MPParse.eventNames(try await run(["inspect", "events", "--format", "json"], project: project.id))
    }

    public func funnels(project: MPProject) async throws -> [FunnelInfo] {
        let list = try MPParse.funnels(try await run(["inspect", "funnels", "--format", "json"], project: project.id))
        // Dates are a bonus: a sign-in that can't list saved reports still gets its funnels.
        let dates = (try? await run(["inspect", "bookmarks", "--type", "funnels", "--format", "json"], project: project.id))
            .flatMap { try? MPParse.modifiedDates($0) } ?? [:]
        return MPParse.byRecency(list, modified: dates)
    }

    public func funnel(project: MPProject, id: Int, from: String, to: String) async throws -> FunnelResult {
        try MPParse.funnel(try await run(["query", "funnel", String(id), "--from", from, "--to", to, "--format", "json"], project: project.id))
    }

    public func retention(project: MPProject, born: String, returning: String, from: String, to: String, days: Int) async throws -> [RetentionCohort] {
        try MPParse.retention(try await run([
            "query", "retention", "--born", born, "--return", returning, "--from", from, "--to", to,
            "--unit", "day", "--interval", "1", "--intervals", String(days), "--format", "json",
        ], project: project.id))
    }

    public func eventCounts(project: MPProject, events: [String], from: String, to: String, unit: TimeUnit, unique: Bool) async throws -> [String: [DatedValue]] {
        try MPParse.eventCounts(try await run([
            "query", "event-counts", "--events", events.joined(separator: ","), "--from", from, "--to", to,
            "--unit", unit.rawValue, "--type", unique ? "unique" : "general", "--format", "json",
        ], project: project.id))
    }

    public func version() async -> String? {
        guard let data = try? await run(["--version"], timeout: 20) else { return nil }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).last.map(String.init)
    }

    /// Asks Mixpanel, past `mp`'s day-long cache of the account, so an expired sign-in shows.
    /// A network failure isn't a sign-out; the person isn't sent back to set up over a dropped Wi-Fi.
    public func signInState() async -> SignInState {
        do {
            _ = try await run(Self.listing(true), timeout: 45)
            return .signedIn
        } catch FunnelError.signedOut {
            return .signedOut
        } catch FunnelError.cliMissing {
            return .signedOut
        } catch {
            return .unknown
        }
    }

    /// Opens the browser and waits until the user has approved, or five minutes pass.
    ///
    /// `mp account add` + `mp account login`, because plain `mp login` asks which project on a
    /// terminal and fails without one when the account sees several.
    public func signIn(region: String) async throws {
        KeychainAccount.delete()
        try? FileManager.default.removeItem(at: Paths.mpStorage)
        _ = try await run(["account", "add", Self.accountName, "--type", "oauth_browser", "--region", region], timeout: 30)
        _ = try await run(["account", "login", Self.accountName], timeout: 300)
        guard await signInState() == .signedIn else { throw FunnelError.signedOut }
    }

    /// Keeps the account in the Keychain only if Mixpanel accepts it.
    public func signIn(service: ServiceAccount) async throws {
        try KeychainAccount.save(service)
        guard await signInState() == .signedIn else {
            KeychainAccount.delete()
            throw FunnelError.signedOut
        }
    }

    public func signOut() {
        KeychainAccount.delete()
        try? FileManager.default.removeItem(at: Paths.mpStorage)
    }

    /// Whether this sign-in may run queries on the project. One query.
    public func canRead(_ project: MPProject) async -> Bool {
        (try? await topEvents(project: project, limit: 1)) != nil
    }
}
