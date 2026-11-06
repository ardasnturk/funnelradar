#if DEBUG
import AppKit
import SwiftUI

/// `--demo --snapshot <folder>`: writes the app's screens as PNGs from demo data, for the README.
@MainActor
enum Snapshots {
    static var folder: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(_ model: AppModel, to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        BrandBackground.isFlat = true
        try? await Task.sleep(for: .seconds(4))
        func render<V: View>(_ view: V, _ name: String, size: CGSize) async {
            let host = NSHostingView(rootView: view.environment(model).frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(for: .seconds(1.5))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
            window.orderOut(nil)
        }
        model.selection = .portfolio
        await render(PortfolioView().background(BrandBackground()).preferredColorScheme(.dark), "portfolio", size: CGSize(width: 1240, height: 1000))
        await render(AlertsView().background(BrandBackground()).preferredColorScheme(.dark), "alerts", size: CGSize(width: 1000, height: 500))
        if let first = model.portfolio.reports.first {
            model.selection = .project(first.id)
            await model.select(project: first.id)
            await render(ProjectView(id: first.id).background(BrandBackground()).preferredColorScheme(.dark), "project", size: CGSize(width: 1240, height: 2100))
        }
        if let sparse = model.portfolio.reports.last {
            model.selection = .project(sparse.id)
            await model.select(project: sparse.id)
            await render(ProjectView(id: sparse.id).background(BrandBackground()).preferredColorScheme(.dark), "project-sparse", size: CGSize(width: 1240, height: 1100))
        }
        await render(MenuPanel().preferredColorScheme(.dark), "menu", size: CGSize(width: 360, height: 430))
        await render(SettingsView().preferredColorScheme(.dark), "settings", size: CGSize(width: 560, height: 480))
        for step in SetupStep.allCases {
            model.step = step
            await render(OnboardingView().preferredColorScheme(.dark), "onboarding-\(step.rawValue)", size: CGSize(width: 860, height: 600))
        }
        NSApp.terminate(nil)
    }
}
#endif
