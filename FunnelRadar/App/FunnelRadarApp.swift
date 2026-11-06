import AppKit
import SwiftUI

@main
struct FunnelRadarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("FunnelRadar", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Runs the launch logic: this view exists from the first moment, unlike any window.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "line.3.horizontal.decrease")
            .task {
                model.onOpenWindow = {
                    openWindow(id: "main")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                await model.launch()
            }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .checking:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(BrandBackground())
            case .setup:
                OnboardingView()
            case .ready:
                DashboardView()
            }
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
