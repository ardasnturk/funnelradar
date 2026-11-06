import FunnelKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Portfolio", systemImage: "square.grid.2x2").tag(SidebarItem.portfolio)
                Label("Alerts", systemImage: "bell").tag(SidebarItem.alerts)
                Section("Apps") {
                    ForEach(model.portfolio.reports) { report in
                        HStack(spacing: 8) {
                            ProjectIcon(name: report.project.name, size: 20)
                            Text(verbatim: report.project.name).lineLimit(1)
                        }
                        .tag(SidebarItem.project(report.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            ZStack {
                BrandBackground()
                switch model.selection ?? .portfolio {
                case .portfolio: PortfolioView()
                case .alerts: AlertsView()
                case .project(let id): ProjectView(id: id).id(id)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { model.refresh() } label: {
                        if model.isRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .help(Text("Refresh"))
                }
            }
        }
    }
}

/// Reports whatever went wrong on the last read, above the content it may have left stale.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Brand.coral)
                .glassCard(padding: 10)
        }
    }
}

/// When the data was read, and how much of the hour's budget has gone.
struct FreshnessLine: View {
    @Environment(AppModel.self) private var model
    let date: Date?

    var body: some View {
        HStack(spacing: 14) {
            if let date {
                Label {
                    HStack(spacing: 4) {
                        Text("Last read")
                        Text(date, format: .relative(presentation: .named))
                    }
                } icon: {
                    Image(systemName: "clock")
                }
            }
            if let budget = model.budget {
                Label {
                    Text("\(String(budget.used)) of \(String(budget.limit)) queries this hour")
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                }
                if let paused = budget.pausedUntil {
                    Label {
                        HStack(spacing: 4) {
                            Text("Paused until")
                            Text(paused, format: .dateTime.hour().minute())
                        }
                    } icon: {
                        Image(systemName: "pause.circle")
                    }
                    .foregroundStyle(Brand.gold)
                }
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct AlertsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if model.alerts.isEmpty {
                    ContentUnavailableView("No alerts yet", systemImage: "bell.slash", description: Text("FunnelRadar tells you here when a number moves."))
                        .padding(.top, 80)
                }
                ForEach(model.alerts) { alert in
                    Button { model.show(project: alert.projectID) } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: alert.symbol, colors: alert.isGood ? [Brand.mint, Brand.blue] : [Brand.coral, Brand.gold], size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: alert.title).fontWeight(.medium)
                                Text(verbatim: alert.body).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(alert.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .glassCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("Alerts"))
    }
}

/// One headline number.
struct KPICard: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?
    var positive: Bool?
    var help: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(verbatim: value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: detail ?? " ")
                .font(.caption.weight(.medium))
                .foregroundStyle(positive.map { $0 ? Brand.mint : Brand.coral } ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .glassCard(padding: 12)
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
    }
}

struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .glassCard()
    }
}

/// What a card shows until it has something to draw.
struct EmptyNote: View {
    let text: LocalizedStringKey
    var height: CGFloat = 120

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// A row with a bar that grows both ways from the middle, for a change in percent.
struct ChangeBar: View {
    let change: Double

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let width = max(2, min(1, abs(change)) * half)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 2).frame(maxHeight: .infinity)
                Capsule().fill(change >= 0 ? Brand.mint : Brand.coral)
                    .frame(width: width, height: 6)
                    .offset(x: change >= 0 ? half : half - width)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
