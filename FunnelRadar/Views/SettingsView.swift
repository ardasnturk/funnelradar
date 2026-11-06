import FunnelKit
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, events, alerts, account, updates
        var id: String { rawValue }
    }

    @State private var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    Text(title(pane))
                } icon: {
                    IconBadge(symbol: symbol(pane), colors: colors(pane), size: 22)
                }
                .padding(.vertical, 3)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            .background(.thinMaterial)
            Divider()
            VStack(spacing: 0) {
                PaneHeader(symbol: symbol(pane), colors: colors(pane), title: title(pane), subtitle: subtitle(pane))
                detail.scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandBackground())
        }
        .frame(width: 780, height: 560)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralTab()
        case .events: EventsTab()
        case .alerts: AlertsTab()
        case .account: AccountTab()
        case .updates: UpdatesTab()
        }
    }

    private func title(_ pane: Pane) -> LocalizedStringKey {
        switch pane {
        case .general: "General"
        case .events: "Events"
        case .alerts: "Alerts"
        case .account: "Account"
        case .updates: "Updates"
        }
    }

    private func subtitle(_ pane: Pane) -> LocalizedStringKey {
        switch pane {
        case .general: "When FunnelRadar opens and how often it reads."
        case .events: "Key events, funnels and retention for each project."
        case .alerts: "Which notifications you get, and when."
        case .account: "Your sign-in and the command line tool."
        case .updates: "The version you have, and newer ones."
        }
    }

    private func symbol(_ pane: Pane) -> String {
        switch pane {
        case .general: "gearshape.fill"
        case .events: "scope"
        case .alerts: "bell.fill"
        case .account: "person.crop.circle.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    private func colors(_ pane: Pane) -> [Color] {
        switch pane {
        case .general: [Color.gray, Color.gray.opacity(0.7)]
        case .events: [Color.indigo, Color.indigo.opacity(0.7)]
        case .alerts: [Color.red, Color.orange]
        case .account: [Color.blue, Color.teal]
        case .updates: [Color.green, Color.teal]
        }
    }
}

private struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}

private struct UpdatesTab: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppUpdater.automaticKey) private var automatic = true

    var body: some View {
        let updater = model.updater
        Form {
            Section {
                LabeledContent("Installed version", value: updater.currentVersion)
                UpdateStatusView(updater: updater)
                Toggle("Check for updates automatically", isOn: $automatic)
            } footer: {
                Text("FunnelRadar looks for a new release on GitHub once a day. Updates are only installed when you click Install; they are checked for Apple's notarization and the same developer signature first.")
            }
            if case .available = updater.state, !updater.releaseNotes.isEmpty {
                Section {
                    ScrollView {
                        Text(LocalizedStringKey(updater.releaseNotes))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                } header: {
                    Text("What's new")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The update state with its action: check, install, progress or error.
struct UpdateStatusView: View {
    let updater: AppUpdater

    var body: some View {
        HStack(spacing: 10) {
            switch updater.state {
            case .idle:
                Text("Not checked yet").foregroundStyle(.secondary)
                Spacer()
                checkButton
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
                Spacer()
            case .upToDate:
                Label("FunnelRadar is up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                checkButton
            case .available(let release):
                Label {
                    Text("Version \(release.version.description) is available")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Color.purple)
                }
                Spacer()
                Button("Install and Relaunch") { Task { await updater.installUpdate() } }
                    .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text("Downloading…")
                }
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button("Check Now") { Task { await updater.checkForUpdates(userInitiated: true) } }
    }
}

private struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var startAtLogin = LaunchAtLogin.isEnabled
    @State private var projects: [MPProject] = []

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Open FunnelRadar at login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, value in try? LaunchAtLogin.setEnabled(value) }
            Section {
                Picker("Check for new data", selection: $model.preferences.refreshHours) {
                    Text("Every hour").tag(1)
                    Text("Every 2 hours").tag(2)
                    Text("Every 6 hours").tag(6)
                    Text("Once a day").tag(24)
                }
                Picker("Queries an hour, at most", selection: $model.preferences.queriesPerHour) {
                    Text(verbatim: "10").tag(10)
                    Text(verbatim: "20").tag(20)
                    Text(verbatim: "40").tag(40)
                }
            } footer: {
                Text("Mixpanel allows a project 60 queries an hour, shared with its other tools. A check costs one query per app; the full reports are read once a day, about a dozen queries per app.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Apps") {
                ForEach(projects) { project in
                    Toggle(project.name, isOn: Binding(
                        get: { model.preferences.trackedProjects?.contains(project.id) ?? true },
                        set: { on in
                            var list = model.preferences.trackedProjects ?? projects.map(\.id)
                            if on { list.append(project.id) } else { list.removeAll { $0 == project.id } }
                            model.preferences.trackedProjects = Set(list).count == projects.count ? nil : list
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.preferences) { _, _ in model.savePreferences() }
        .task { projects = (try? await AppModel.demo ? DemoSource().projects() : model.cli.projects()) ?? [] }
    }
}

/// The events each project's numbers are about. The lists come from the last read, so this tab
/// spends no queries.
private struct EventsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if model.portfolio.reports.isEmpty {
                Text("The event lists appear after FunnelRadar's first read.").foregroundStyle(.secondary)
            }
            ForEach(model.portfolio.reports) { report in
                Section(report.project.name) {
                    picker("Key event", help: "Busiest event", report, \.keyEvent)
                    picker("Cohort starts with", help: "None", report, \.bornEvent)
                    picker("Comes back with", help: "None", report, \.returnEvent)
                }
            }
            Section {
            } footer: {
                Text("The key event drives daily users, stickiness and unusual days. Retention needs both of the other two. A comma in an event's name can't be queried through mp, so those events aren't listed.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func picker(_ title: LocalizedStringKey, help: LocalizedStringKey, _ report: ProjectReport, _ path: WritableKeyPath<ProjectSetup, String?>) -> some View {
        let names = report.eventNames.filter { !$0.contains(",") }
        return Picker(title, selection: Binding(
            get: { model.preferences.setups[report.id]?[keyPath: path] },
            set: { value in
                var setup = model.preferences.setups[report.id] ?? ProjectSetup()
                setup[keyPath: path] = value
                model.preferences.setups[report.id] = setup
                model.settingsChanged()
            }
        )) {
            Text(help).tag(String?.none)
            ForEach(names, id: \.self) { name in
                Text(verbatim: name).tag(String?.some(name))
            }
        }
    }
}

private struct AlertsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Notify me on this Mac", isOn: $model.preferences.notifyOnMac)
            Section("Tell me about") {
                ForEach(FunnelAlert.Kind.allCases, id: \.self) { kind in
                    Toggle(name(kind), isOn: Binding(
                        get: { model.preferences.alerts.isOn(kind) },
                        set: { model.preferences.alerts.enabled[kind] = $0 }
                    ))
                }
            }
            Section("Thresholds") {
                Picker("Conversion falls by", selection: $model.preferences.alerts.conversionDrop) {
                    Text(verbatim: Format.percent(0.1)).tag(0.1)
                    Text(verbatim: Format.percent(0.2)).tag(0.2)
                    Text(verbatim: Format.percent(0.3)).tag(0.3)
                }
                Picker("Day 7 retention falls by", selection: $model.preferences.alerts.retentionDrop) {
                    Text(verbatim: Format.percent(0.1)).tag(0.1)
                    Text(verbatim: Format.percent(0.2)).tag(0.2)
                    Text(verbatim: Format.percent(0.3)).tag(0.3)
                }
                Picker("Unusual days", selection: $model.preferences.alerts.unusualDay) {
                    Text("More of them").tag(3.0)
                    Text("Normal").tag(3.5)
                    Text("Only the striking ones").tag(5.0)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.preferences) { _, _ in model.savePreferences() }
    }

    private func name(_ kind: FunnelAlert.Kind) -> LocalizedStringKey {
        switch kind {
        case .conversionDrop: "Falling conversion"
        case .eventSpike: "Unusually busy days"
        case .eventDip: "Unusually quiet days"
        case .retentionDrop: "Falling retention"
        }
    }
}

private struct AccountTab: View {
    @Environment(AppModel.self) private var model
    @State private var version: String?

    var body: some View {
        Form {
            LabeledContent("mp") { Text(verbatim: version ?? "—") }
            LabeledContent("Location") { Text(verbatim: Paths.mp.path).textSelection(.enabled).lineLimit(2) }
            Button("Sign Out…", role: .destructive) {
                Task { await model.signOut() }
            }
            Section {
                LabeledContent("FunnelRadar") { Text(verbatim: model.version) }
            } footer: {
                Text("FunnelRadar is not affiliated with Mixpanel.")
            }
        }
        .formStyle(.grouped)
        .task { version = await model.cli.version() }
    }
}
