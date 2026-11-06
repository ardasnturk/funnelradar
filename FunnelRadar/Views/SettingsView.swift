import FunnelKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            EventsTab().tabItem { Label("Events", systemImage: "scope") }
            AlertsTab().tabItem { Label("Alerts", systemImage: "bell") }
            AccountTab().tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 560, height: 480)
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
