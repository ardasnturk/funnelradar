import FunnelKit
import SwiftUI

/// Everything FunnelRadar needs before it opens. Required steps can't be passed until they are done.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .tool: ToolStep()
                case .account: AccountStep()
                case .projects: ProjectsStep()
                case .notifications: NotificationsStep()
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: 560)
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandBackground())
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(symbol: "line.3.horizontal.decrease", size: 30)
                Text(verbatim: "FunnelRadar").font(.title2.bold())
            }
            .padding(.bottom, 18)
            ForEach(SetupStep.allCases, id: \.self) { step in
                HStack(spacing: 10) {
                    Image(systemName: step < model.step ? "checkmark.circle.fill" : (step == model.step ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(step <= model.step ? Brand.violet : .secondary)
                    Text(title(step))
                        .fontWeight(step == model.step ? .semibold : .regular)
                        .foregroundStyle(step == model.step ? .primary : .secondary)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 230, alignment: .leading)
    }

    private func title(_ step: SetupStep) -> LocalizedStringKey {
        switch step {
        case .welcome: "Welcome"
        case .tool: "Mixpanel tool"
        case .account: "Sign in"
        case .projects: "Your apps"
        case .notifications: "Notifications"
        case .done: "Ready"
        }
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(symbol: symbol, size: 44)
            Text(title).font(.largeTitle.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "chart.bar.xaxis", title: "See your product numbers your way",
                text: "FunnelRadar lays out all your Mixpanel projects together, with what panels don't show at a glance: funnel leaks, D1/D7/D30 retention, stickiness, unusual days and alerts."
            )
            VStack(alignment: .leading, spacing: 10) {
                Label("Runs on your Mac, with no server and no account of its own.", systemImage: "lock.shield")
                Label("Uses Mixpanel's official mp tool, which keeps your sign-in.", systemImage: "terminal")
                Label("Only reads. It sends nothing anywhere except your queries to Mixpanel.", systemImage: "eye.slash")
            }
            Button("Get Started") { model.step = .tool }.buttonStyle(GradientButtonStyle())
        }
    }
}

private struct ToolStep: View {
    @Environment(AppModel.self) private var model
    @State private var found = false
    @State private var version: String?
    @State private var checking = true
    @State private var installing = false
    @State private var stage: ToolInstaller.Stage?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "terminal", title: "Install the Mixpanel tool",
                text: "FunnelRadar reads your data through mp, Mixpanel's official command line tool. It's free and open source."
            )
            if checking {
                ProgressView()
            } else if found {
                Label {
                    VStack(alignment: .leading) {
                        Text("mp \(version ?? "") is installed")
                        Text(verbatim: Paths.mp.path).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                }
                Button("Continue") { model.step = .account }.buttonStyle(GradientButtonStyle())
            } else {
                Text("FunnelRadar keeps a private copy of mp \(ToolInstaller.version) in its own folder, so nothing else on your Mac changes. It needs Python 3.10 or newer, which macOS doesn't include: uv can fetch one, otherwise FunnelRadar uses a Python you have or gets uv with Homebrew.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("The install is about 300 MB and takes a minute or two.", systemImage: "externaldrive")
                    .font(.callout)
                if installing {
                    HStack { ProgressView().controlSize(.small); Text(stageText).foregroundStyle(.secondary) }
                } else {
                    Button("Install") { install() }.buttonStyle(GradientButtonStyle())
                }
                ErrorLine(text: error)
            }
        }
        .task { await look() }
    }

    private var stageText: LocalizedStringKey {
        switch stage {
        case .gettingUV: "Getting uv with Homebrew…"
        case .fetchingPython: "Preparing Python…"
        case .makingEnvironment: "Preparing Python…"
        case .installing: "Installing mp…"
        case .checking, nil: "Checking the install…"
        }
    }

    private func look() async {
        checking = true
        found = ToolInstaller.isInstalled
        if found { version = await model.cli.version() }
        checking = false
    }

    private func install() {
        installing = true
        error = nil
        Task {
            do {
                try await ToolInstaller.install { value in
                    Task { @MainActor in stage = value }
                }
                await look()
            } catch {
                self.error = error.localizedDescription
            }
            installing = false
        }
    }
}

private struct AccountStep: View {
    @Environment(AppModel.self) private var model
    @State private var signedIn = false
    @State private var checking = true
    @State private var waiting = false
    @State private var useService = false
    @State private var region = "us"
    @State private var username = ""
    @State private var secret = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                symbol: "person.badge.key", title: "Sign in to Mixpanel",
                text: "Your browser opens Mixpanel. FunnelRadar never sees your password, and mp keeps the sign-in on this Mac, apart from any mp you use in a terminal."
            )
            if checking {
                ProgressView()
            } else if signedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                Button("Continue") { model.step = .projects }.buttonStyle(GradientButtonStyle())
            } else if waiting {
                HStack { ProgressView().controlSize(.small); Text("Waiting for you to approve in the browser…").foregroundStyle(.secondary) }
            } else {
                Picker("Data region", selection: $region) {
                    Text("US").tag("us")
                    Text("EU").tag("eu")
                    Text("India").tag("in")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                Button("Sign In with Browser") { browser() }.buttonStyle(GradientButtonStyle())
                DisclosureGroup("Use a service account instead", isExpanded: $useService) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create one in your Mixpanel organization settings, with access to the projects you want. Its secret stays in your Keychain.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                        SecureField("Secret", text: $secret).textFieldStyle(.roundedBorder)
                        Button("Use This Account") { saveService() }
                            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 6)
                }
                ErrorLine(text: error)
            }
        }
        .task {
            signedIn = await model.cli.signInState() == .signedIn
            checking = false
        }
    }

    private func browser() {
        waiting = true
        error = nil
        Task {
            do {
                try await model.cli.signIn(region: region)
                signedIn = true
            } catch {
                self.error = String(localized: "The sign-in didn't finish. Check the region and try again.")
            }
            waiting = false
        }
    }

    private func saveService() {
        error = nil
        Task {
            do {
                let account = ServiceAccount(username: username.trimmingCharacters(in: .whitespaces), secret: secret.trimmingCharacters(in: .whitespaces), region: region)
                try await model.cli.signIn(service: account)
                secret = ""
                signedIn = true
            } catch FunnelError.signedOut {
                self.error = String(localized: "Mixpanel didn't accept this service account.")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ProjectsStep: View {
    @Environment(AppModel.self) private var model
    @State private var projects: [MPProject] = []
    @State private var chosen: Set<String> = []
    @State private var loading = true
    @State private var verifying = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "square.grid.2x2", title: "Choose your apps", text: "FunnelRadar follows the projects you pick here. In Settings you can change them, and pick each one's key event and retention events.")
            if loading {
                ProgressView()
            } else if projects.isEmpty {
                ErrorLine(text: error ?? String(localized: "This account can't see any projects."))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(projects) { project in
                            Toggle(isOn: Binding(
                                get: { chosen.contains(project.id) },
                                set: { if $0 { chosen.insert(project.id) } else { chosen.remove(project.id) } }
                            )) {
                                HStack(spacing: 10) {
                                    ProjectIcon(name: project.name, size: 26)
                                    Text(verbatim: project.name)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
                Text("Each app costs about a dozen of Mixpanel's 60 queries an hour on its first read.")
                    .font(.caption).foregroundStyle(.secondary)
                ErrorLine(text: error)
                Button(verifying ? "Checking access…" : "Continue") { verify() }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(chosen.isEmpty || verifying)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            projects = AppModel.demo ? try await DemoSource().projects() : try await model.cli.projects()
            chosen = Set(model.preferences.trackedProjects ?? projects.map(\.id))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// A sign-in without access would give an empty app, so that's caught here.
    private func verify() {
        verifying = true
        error = nil
        Task {
            let first = projects.first { chosen.contains($0.id) }
            if let first, await !model.cli.canRead(first) {
                error = String(localized: "This sign-in can't read \(first.name). Check its access in Mixpanel.")
            } else {
                model.preferences.trackedProjects = chosen.count == projects.count ? nil : Array(chosen)
                model.savePreferences()
                model.step = .notifications
            }
            verifying = false
        }
    }
}

private struct NotificationsStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "bell.badge", title: "Stay on top of your numbers",
                text: "FunnelRadar tells you when a funnel's conversion falls, a day is unusually busy or quiet, or retention drops. Each one reaches you once."
            )
            HStack {
                Button("Turn On Notifications") {
                    Task {
                        model.preferences.notifyOnMac = await Notifier.requestPermission()
                        model.savePreferences()
                        model.step = .done
                    }
                }
                .buttonStyle(GradientButtonStyle())
                Button("Not Now") {
                    model.preferences.notifyOnMac = false
                    model.savePreferences()
                    model.step = .done
                }
            }
        }
    }
}

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var startAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "checkmark.seal", title: "You're all set",
                text: "FunnelRadar lives in your menu bar. The first full read takes about a minute per app, and with many apps it spreads over a few hours, because Mixpanel limits queries. Pick each app's events in Settings for retention and stickiness that mean what you want."
            )
            Toggle("Open FunnelRadar at login", isOn: $startAtLogin)
            Button("Open FunnelRadar") {
                try? LaunchAtLogin.setEnabled(startAtLogin)
                Task { await model.finishSetup() }
            }
            .buttonStyle(GradientButtonStyle())
        }
    }
}
