import Charts
import FunnelKit
import SwiftUI

/// Every app side by side. Mixpanel shows one project at a time, and one report at a time in it.
struct PortfolioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ErrorBanner()
                FreshnessLine(date: model.portfolio.updatedAt)
                if model.portfolio.reports.isEmpty {
                    ProgressView("Reading your numbers…").padding(.top, 120)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        trend
                        movers.frame(maxWidth: 360)
                    }
                    leaks
                    table
                }
            }
            .padding(20)
        }
        .navigationTitle(Text("Portfolio"))
    }

    private var trend: some View {
        ChartCard(title: "Active users, side by side", subtitle: "A 7-day average, 100 = each app 90 days ago. Apps count different events and can share people, so they are compared and never added.") {
            if model.portfolio.indexed.isEmpty {
                EmptyNote(text: "This fills in after two weeks of data.", height: 230)
            } else {
                Chart {
                    ForEach(model.portfolio.indexed) { series in
                        ForEach(series.points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Index", point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(by: .value("App", series.projectName))
                        }
                    }
                    RuleMark(y: .value("Start", 100)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
                .chartForegroundStyleScale(domain: model.portfolio.indexed.map(\.projectName), range: Array(Brand.series.prefix(max(1, model.portfolio.indexed.count))))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 250)
            }
        }
    }

    private var movers: some View {
        ChartCard(title: "Biggest movers", subtitle: "Top events, this week against last week.") {
            if model.portfolio.movers.isEmpty {
                EmptyNote(text: "Nothing has moved much yet.", height: 230)
            } else {
                VStack(spacing: 9) {
                    ForEach(model.portfolio.movers) { row in
                        Button { model.selection = .project(row.projectID) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(verbatim: row.mover.event).lineLimit(1)
                                    Spacer()
                                    Text(verbatim: row.mover.change.map(Format.signedPercent) ?? "—").monospacedDigit()
                                        .foregroundStyle((row.mover.change ?? 0) >= 0 ? Brand.mint : Brand.coral)
                                }
                                .font(.callout)
                                Text(verbatim: row.projectName).font(.caption2).foregroundStyle(.secondary)
                                ChangeBar(change: row.mover.change ?? 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var leaks: some View {
        if !model.portfolio.leaks.isEmpty {
            ChartCard(title: "Where people drop out", subtitle: "The worst step of each saved funnel, worst first.") {
                VStack(spacing: 8) {
                    ForEach(model.portfolio.leaks) { row in
                        if let leak = row.funnel.leak {
                            Button { model.selection = .project(row.projectID) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: "\(leak.fromEvent) → \(leak.toEvent)").lineLimit(1)
                                        Text(verbatim: "\(row.projectName) · \(row.funnel.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(width: 330, alignment: .leading)
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Brand.coral.opacity(0.28))
                                            Capsule().fill(Brand.buttonGradient).frame(width: max(4, proxy.size.width * leak.kept))
                                        }
                                    }
                                    .frame(height: 8)
                                    Text("keeps \(Format.percent(leak.kept, digits: 0))").monospacedDigit().frame(width: 100, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var table: some View {
        ChartCard(title: "Apps compared", subtitle: "Daily users are of each app's key event, a 7-day average. Stickiness is DAU/MAU of the last full month. D7 is the share of a cohort back on day 7.") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    Text("App")
                    Text("Key event")
                    Text("Daily users").gridColumnAlignment(.trailing)
                    Text("Change").gridColumnAlignment(.trailing)
                    Text("Stickiness").gridColumnAlignment(.trailing)
                    Text("D7").gridColumnAlignment(.trailing)
                    Text("Best funnel").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(model.portfolio.reports) { report in
                    let insights = report.insights
                    GridRow {
                        Button { model.selection = .project(report.id) } label: {
                            HStack(spacing: 8) {
                                ProjectIcon(name: report.project.name, size: 22)
                                Text(verbatim: report.project.name).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: report.keyEvent ?? "—").foregroundStyle(.secondary).lineLimit(1)
                        Text(verbatim: insights.activeUsers.map(Format.count) ?? "—")
                        Text(verbatim: insights.activeChange.map(Format.signedPercent) ?? "—")
                            .foregroundStyle(insights.activeChange.map { $0 >= 0 ? Brand.mint : Brand.coral } ?? .secondary)
                        Text(verbatim: insights.stickiness.map { Format.percent($0) } ?? "—")
                        Text(verbatim: report.retention?.d7.map { Format.percent($0) } ?? "—")
                        Text(verbatim: report.funnels.map(\.conversion).max().map { Format.percent($0) } ?? "—")
                    }
                    .monospacedDigit()
                }
            }
        }
    }
}
