import AppKit
import FunnelKit
import Observation
import UserNotifications

enum SetupStep: Int, CaseIterable, Comparable {
    case welcome, tool, account, projects, notifications, done
    static func < (a: SetupStep, b: SetupStep) -> Bool { a.rawValue < b.rawValue }
}

enum Phase: Equatable {
    case checking
    case setup
    case ready
}

/// The app's state. Until every required step is done `phase` stays `.setup`, the window shows
/// onboarding and the menu offers only to finish it. A step that later breaks, such as an
/// expired sign-in, brings the app back to that step.
@MainActor
@Observable
final class AppModel {
    static let demo = CommandLine.arguments.contains("--demo")

    private(set) var phase = Phase.checking
    var step = SetupStep.welcome
    var preferences = AppModel.demo ? DemoSource.preferences : Preferences.load()
    private(set) var portfolio = Portfolio.empty
    private(set) var alerts: [FunnelAlert] = []
    private(set) var selectedReport: ProjectReport?
    private(set) var budget: BudgetStatus?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    var selection: SidebarItem? = .portfolio
    var onOpenWindow: (() -> Void)?

    let cli = MPCLI()
    private var engine: Engine?
    private var hub: Hub?
    private var delegate: NotificationDelegate?
    private var listener: Task<Void, Never>?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func launch() async {
        let delegate = NotificationDelegate { [weak self] project in self?.show(project: project) }
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        await check()
        #if DEBUG
        if let folder = Snapshots.folder { await Snapshots.run(self, to: folder) }
        #endif
    }

    /// Finds the first required step that isn't done. Without a network the sign-in can't be
    /// judged, so a finished setup stays open and shows its cached reports.
    func check() async {
        if Self.demo {
            await becomeReady()
            return
        }
        if phase != .ready { phase = .checking }
        let missing: SetupStep? = if !ToolInstaller.isInstalled {
            .tool
        } else if await cli.signInState() == .signedOut {
            .account
        } else if !preferences.setupFinished {
            nil
        } else {
            .done
        }
        switch missing {
        case .done:
            await becomeReady()
        case nil:
            phase = .setup
            openWindow()
        case let step?:
            stopEngine()
            phase = .setup
            self.step = preferences.setupFinished ? step : .welcome
            openWindow()
        }
    }

    func finishSetup() async {
        preferences.setupFinished = true
        savePreferences()
        await becomeReady()
    }

    func savePreferences() {
        guard !Self.demo else { return }
        try? preferences.save()
    }

    /// New events to read, or apps to follow. The engine decides whether that costs a query.
    func settingsChanged() {
        savePreferences()
        Task { [engine] in await engine?.settingsChanged() }
    }

    private func becomeReady() async {
        phase = .ready
        guard engine == nil else { return }
        await Hub.askLiveHubToYield()
        let engine = Self.demo
            ? Engine(source: DemoSource(), spacing: .milliseconds(1), persists: false, preferences: { DemoSource.preferences })
            : Engine(source: cli)
        self.engine = engine
        let hub = Hub(engine: engine, demo: Self.demo, version: version) {}
        try? hub.start()
        self.hub = hub
        await update(from: engine)
        let events = await engine.events()
        listener = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
        await engine.start()
    }

    private func stopEngine() {
        listener?.cancel()
        listener = nil
        hub?.stop()
        hub = nil
        Task { [engine] in await engine?.stop() }
        engine = nil
    }

    private func update(from engine: Engine) async {
        portfolio = await engine.portfolio()
        alerts = await engine.recentAlerts()
        budget = await engine.budget()
        if let id = selectedReport?.id { selectedReport = await engine.report(id) }
    }

    private func handle(_ event: EngineEvent) async {
        guard let engine else { return }
        switch event {
        case .portfolio:
            await update(from: engine)
            let failure = await engine.lastError
            lastError = failure.map(describe)
            if failure == .signedOut || failure == .cliMissing { await check() }
        case .alert(let alert):
            alerts = await engine.recentAlerts()
            if preferences.notifyOnMac { Notifier.post(alert) }
        }
    }

    private func describe(_ error: FunnelError) -> String {
        switch error {
        case .cliMissing: String(localized: "The mp tool is missing.")
        case .signedOut: String(localized: "Sign in to Mixpanel again.")
        case .rateLimited: String(localized: "Mixpanel asked FunnelRadar to slow down. It will try again later.")
        case .failed(let message): message
        }
    }

    /// Shows what's in the cache. Opening a view never sends a query.
    func select(project id: String) async {
        selectedReport = await engine?.report(id)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await engine?.refresh(project: selectedProjectID)
            isRefreshing = false
        }
    }

    private var selectedProjectID: String? {
        if case .project(let id) = selection { return id }
        return nil
    }

    func show(project id: String) {
        selection = .project(id)
        openWindow()
    }

    func openWindow() {
        onOpenWindow?()
    }

    func signOut() async {
        cli.signOut()
        await engine?.reset()
        preferences.setupFinished = false
        savePreferences()
        stopEngine()
        portfolio = .empty
        alerts = []
        step = .welcome
        await check()
    }

    func quit() {
        hub?.stop()
        NSApp.terminate(nil)
    }
}

enum SidebarItem: Hashable {
    case portfolio
    case alerts
    case project(String)
}
