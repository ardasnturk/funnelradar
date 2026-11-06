import Charts
import FunnelKit
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            if model.phase == .ready {
                header
                apps
                if let alert = model.alerts.first { alertRow(alert) }
            } else {
                setup
            }
            if model.updater.availableRelease != nil {
                UpdateStatusView(updater: model.updater).glassCard(padding: 10)
            }
            footer
        }
        .padding(10)
        .frame(width: 360)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconBadge(symbol: "line.3.horizontal.decrease")
                Text(verbatim: "FunnelRadar").font(.headline)
            }
            Text("Finish setup to see your numbers.").foregroundStyle(.secondary)
            Button("Finish Setup") { model.openWindow() }.buttonStyle(GradientButtonStyle())
        }
        .glassCard()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "FunnelRadar").font(.headline)
                Spacer()
                if let date = model.portfolio.updatedAt {
                    Text(date, format: .relative(presentation: .named)).font(.caption)
                }
            }
            if let leak = model.portfolio.leaks.first, let detail = leak.funnel.leak {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Biggest leak").font(.caption.weight(.medium))
                    Text(verbatim: "\(detail.fromEvent) → \(detail.toEvent)").font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(leak.projectName) keeps \(Format.percent(detail.kept, digits: 0)) here").font(.caption)
                }
            } else if model.portfolio.reports.isEmpty {
                Text("Reading your numbers…").font(.callout)
            } else {
                Text("No funnels to watch yet.").font(.callout)
            }
            HStack(spacing: 7) {
                stat(String(model.portfolio.reports.count), "apps")
                stat(String(model.alerts.count), "alerts")
                stat(model.budget.map { "\($0.used)/\($0.limit)" } ?? "—", "queries this hour")
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var apps: some View {
        VStack(spacing: 2) {
            ForEach(model.portfolio.reports.prefix(6)) { report in
                Button {
                    model.show(project: report.id)
                } label: {
                    HStack(spacing: 9) {
                        ProjectIcon(name: report.project.name, size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: report.project.name).lineLimit(1)
                            Text(verbatim: report.keyEvent ?? "—").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Sparkline(values: report.dailyUsers.suffix(30).map(\.value)).frame(width: 54, height: 18)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(verbatim: report.insights.activeUsers.map(Format.count) ?? "—").monospacedDigit()
                            Text(verbatim: report.insights.activeChange.map(Format.signedPercent) ?? " ")
                                .font(.caption2.weight(.medium)).monospacedDigit()
                                .foregroundStyle((report.insights.activeChange ?? 0) >= 0 ? Brand.mint : Brand.coral)
                        }
                        .frame(minWidth: 52, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard(padding: 10)
    }

    private func alertRow(_ alert: FunnelAlert) -> some View {
        HStack(spacing: 9) {
            Image(systemName: alert.symbol).foregroundStyle(alert.isGood ? Brand.mint : Brand.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: alert.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(verbatim: alert.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .glassCard(padding: 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.phase == .ready {
                Button("Open FunnelRadar") { model.openWindow() }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }
                    .help(Text("Refresh"))
            }
            Spacer()
            Button { SettingsWindow.show(using: openSettings) } label: { Label("Settings…", systemImage: "gearshape").labelStyle(.iconOnly) }
                .help(Text("Settings…"))
            Button { model.quit() } label: { Label("Quit FunnelRadar", systemImage: "power").labelStyle(.iconOnly) }
                .help(Text("Quit FunnelRadar"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
    }
}

/// A tiny line with no axes.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle((values.last ?? 0) >= (values.first ?? 0) ? Brand.mint : Brand.coral)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}
