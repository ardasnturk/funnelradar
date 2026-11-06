import Charts
import FunnelKit
import SwiftUI

struct ProjectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let id: String

    private var report: ProjectReport? {
        model.selectedReport?.id == id ? model.selectedReport : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ErrorBanner()
                if let report {
                    FreshnessLine(date: report.updatedAt)
                    content(report)
                } else {
                    ProgressView().padding(.top, 120)
                }
            }
            .padding(20)
        }
        .navigationTitle(Text(verbatim: report?.project.name ?? "FunnelRadar"))
        .task { await model.select(project: id) }
    }

    @ViewBuilder private func content(_ report: ProjectReport) -> some View {
        let insights = report.insights
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            KPICard(
                title: "Daily users", value: insights.activeUsers.map(Format.count) ?? "—",
                detail: insights.activeChange.map { String(localized: "\(Format.signedPercent($0)) on last week") }, positive: insights.activeChange.map { $0 >= 0 },
                help: "Unique users of the key event, averaged over the last 7 full days."
            )
            KPICard(
                title: "Stickiness", value: insights.stickiness.map { Format.percent($0) } ?? "—",
                detail: insights.stickinessMonth.map(Format.month), help: "DAU/MAU: the average day's users as a share of the month's."
            )
            KPICard(title: "D1 retention", value: report.retention?.d1.map { Format.percent($0) } ?? "—", help: "Share of a cohort that returns the day after.")
            KPICard(title: "D7 retention", value: report.retention?.d7.map { Format.percent($0) } ?? "—", help: "Share of a cohort that returns on day 7.")
            KPICard(title: "D30 retention", value: report.retention?.d30.map { Format.percent($0) } ?? "—", help: "Share of a cohort that returns on day 30.")
        }
        if report.deepKey == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading reports. Mixpanel limits queries, so this takes about a minute per app.").font(.callout).foregroundStyle(.secondary)
            }
            .glassCard(padding: 10)
        } else {
            takeaways(report)
            funnels(report)
            users(report)
            HStack(alignment: .top, spacing: 12) {
                movers(report)
                weekdays(report)
                today(report)
            }
            HStack(alignment: .top, spacing: 12) {
                retention(report)
                curve(report)
            }
            stickiness(report)
        }
    }

    /// Plain sentences, from the numbers below.
    @ViewBuilder private func takeaways(_ report: ProjectReport) -> some View {
        let lines = Self.takeaways(report)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "sparkle").font(.callout)
                }
            }
            .glassCard()
        }
    }

    static func takeaways(_ report: ProjectReport) -> [String] {
        let insights = report.insights
        var lines: [String] = []
        if let funnel = report.funnels.filter({ $0.leak != nil }).min(by: { $0.leak!.kept < $1.leak!.kept }), let leak = funnel.leak {
            lines.append(String(localized: "\(funnel.name) loses the most people at \(leak.toEvent): only \(Format.percent(leak.kept, digits: 0)) get there from \(leak.fromEvent)."))
        }
        if let sticky = insights.stickiness, let month = insights.stickinessMonth {
            let days = (sticky * 30).formatted(.number.precision(.fractionLength(0...1)))
            lines.append(String(localized: "In \(Format.month(month)) an active user came back on about \(days) days of 30."))
        }
        if let day = insights.bestWeekday, insights.weekdayIndex.count == 7 {
            let name = Calendar.current.standaloneWeekdaySymbols[(day + 1) % 7]
            lines.append(String(localized: "\(name) is your busiest day, \(Format.signedPercent(insights.weekdayIndex[day] - 1)) against an average day."))
        }
        return lines
    }

    @ViewBuilder private func funnels(_ report: ProjectReport) -> some View {
        if report.funnels.isEmpty {
            ChartCard(title: "Funnels") {
                EmptyNote(text: "This project has no saved funnels. Save one in Mixpanel and it appears here.", height: 70)
            }
        } else {
            let last = report.funnels.first
            ChartCard(
                title: "Funnels",
                subtitle: "\(last.map { Format.day($0.from) } ?? "") – \(last.map { Format.day($0.to) } ?? ""), against the 28 days before. The newest 7 days are left out: people who just entered may still convert."
            ) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(report.funnels) { funnel in FunnelCard(funnel: funnel) }
                }
                if report.funnelCount > report.funnels.count {
                    Text("Showing the \(String(report.funnels.count)) most recently changed of \(String(report.funnelCount)) saved funnels. Each one costs queries.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func users(_ report: ProjectReport) -> some View {
        let event = report.keyEvent ?? "—"
        return ChartCard(
            title: "Daily users",
            subtitle: report.keyEventIsGuess
                ? "\(event), the busiest event until you pick one in Settings. Marked days are far from the 28 before them. Dashed: a straight line through the last 60 days, for 30 more. A trend, not a forecast."
                : "\(event). Marked days are far from the 28 before them. Dashed: a straight line through the last 60 days, for 30 more. A trend, not a forecast."
        ) {
            if report.dailyUsers.isEmpty {
                EmptyNote(text: "No data yet.", height: 200)
            } else {
                Chart {
                    ForEach(report.dailyUsers.suffix(120)) { day in
                        AreaMark(x: .value("Date", day.date), y: .value("Users", day.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Brand.violet.opacity(0.4), Brand.violet.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", day.date), y: .value("Users", day.value), series: .value("Series", "Users"))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Brand.violet)
                    }
                    ForEach(report.insights.trend) { day in
                        LineMark(x: .value("Date", day.date), y: .value("Users", day.value), series: .value("Series", "Trend"))
                            .foregroundStyle(Brand.gold)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    ForEach(report.anomalies.suffix(12)) { anomaly in
                        PointMark(x: .value("Date", anomaly.date), y: .value("Users", anomaly.value))
                            .foregroundStyle(anomaly.value > anomaly.expected ? Brand.mint : Brand.coral)
                            .symbolSize(50)
                    }
                }
                .frame(height: 230)
            }
        }
    }

    private func movers(_ report: ProjectReport) -> some View {
        ChartCard(title: "Movers", subtitle: "This week against last week.") {
            if report.movers.isEmpty {
                EmptyNote(text: "Nothing has moved much yet.", height: 150)
            } else {
                VStack(spacing: 8) {
                    ForEach(report.movers) { mover in
                        VStack(spacing: 2) {
                            HStack {
                                Text(verbatim: mover.event).lineLimit(1)
                                Spacer()
                                Text(verbatim: mover.change.map(Format.signedPercent) ?? String(localized: "new")).monospacedDigit()
                                    .foregroundStyle((mover.change ?? 1) >= 0 ? Brand.mint : Brand.coral)
                            }
                            .font(.callout)
                            ChangeBar(change: mover.change ?? 0)
                        }
                    }
                }
            }
        }
    }

    private func weekdays(_ report: ProjectReport) -> some View {
        let names = Calendar.current.veryShortStandaloneWeekdaySymbols
        let rows = report.insights.weekdayIndex.enumerated().map { (offset: $0.offset, name: names[($0.offset + 1) % 7], value: $0.element) }
        return ChartCard(title: "Weekday pattern", subtitle: "Against an average day, last 12 weeks.") {
            if rows.isEmpty {
                EmptyNote(text: "This fills in after a week of data.", height: 150)
            } else {
                Chart(rows, id: \.offset) { row in
                    BarMark(x: .value("Day", "\(row.offset) \(row.name)"), y: .value("Index", row.value))
                        .foregroundStyle(row.value >= 1 ? Brand.violet : Brand.blue.opacity(0.5))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel { Text(verbatim: value.as(String.self)?.split(separator: " ").last.map(String.init) ?? "") }
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private func today(_ report: ProjectReport) -> some View {
        ChartCard(title: "Today so far", subtitle: "Busiest events, from the latest check.") {
            if report.topEvents.isEmpty {
                EmptyNote(text: "No events yet today.", height: 150)
            } else {
                VStack(spacing: 6) {
                    ForEach(report.topEvents.prefix(6)) { event in
                        HStack {
                            Text(verbatim: event.event).lineLimit(1)
                            Spacer()
                            Text(verbatim: Format.count(event.count)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    @ViewBuilder private func retention(_ report: ProjectReport) -> some View {
        ChartCard(title: "Retention by week", subtitle: "Weekly cohorts by day. Blank cells are too young to know.") {
            if let retention = report.retention {
                Text(verbatim: "\(retention.born) → \(retention.returning)").font(.caption).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        Text(verbatim: "").gridColumnAlignment(.leading)
                        Text(verbatim: "")
                        ForEach(retention.days, id: \.self) { day in
                            Text(verbatim: "D\(day)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(retention.rows) { row in
                        GridRow {
                            Text(row.week, format: Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: Format.count(row.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, value in cell(value) }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    EmptyNote(text: "Pick the two events of this project's cohort in Settings.", height: 110)
                    Button("Open Settings…") { SettingsWindow.show(using: openSettings) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func cell(_ value: Double?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(value.map { Brand.violet.opacity(0.12 + min(1, $0 * 1.6) * 0.8) } ?? Color.clear)
            .frame(height: 24)
            .overlay {
                if let value { Text(verbatim: Format.percent(value, digits: 0)).font(.caption2).monospacedDigit() }
            }
    }

    private func curve(_ report: ProjectReport) -> some View {
        ChartCard(title: "Retention curve", subtitle: "All cohorts, weighted by size. A curve that flattens means people stay.") {
            if let curve = report.retention?.curve, !curve.isEmpty {
                Chart(curve) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Share", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.blue)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { Text(verbatim: value.as(Double.self).map { Format.percent($0, digits: 0) } ?? "") }
                    }
                }
                .frame(height: 230)
            } else {
                EmptyNote(text: "No cohorts to draw yet.", height: 150)
            }
        }
        .frame(maxWidth: 400)
    }

    @ViewBuilder private func stickiness(_ report: ProjectReport) -> some View {
        ChartCard(title: "Stickiness by month", subtitle: "DAU/MAU of the key event, full months only.") {
            if report.insights.stickinessByMonth.isEmpty {
                EmptyNote(text: "This fills in after a full month of data.", height: 100)
            } else {
                Chart(report.insights.stickinessByMonth) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("DAU/MAU", month.value))
                        .foregroundStyle(Brand.buttonGradient)
                        .annotation(position: .top) {
                            Text(verbatim: Format.percent(month.value, digits: 0)).font(.caption2).monospacedDigit()
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 130)
            }
        }
    }
}

/// One funnel as bars that narrow, with the worst step in red.
private struct FunnelCard: View {
    let funnel: FunnelReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: funnel.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(verbatim: Format.percent(funnel.conversion)).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
            }
            if let change = funnel.change, let before = funnel.previousConversion {
                Text("\(Format.signedPercent(change)) · was \(Format.percent(before))")
                    .font(.caption.weight(.medium)).foregroundStyle(change >= 0 ? Brand.mint : Brand.coral)
            } else {
                Text("Nothing to compare with yet.").font(.caption).foregroundStyle(.secondary)
            }
            if funnel.entered == 0 {
                Text("Nobody entered this funnel in the period.").font(.caption).foregroundStyle(.secondary)
            }
            let first = max(1, funnel.steps.first?.count ?? 1)
            ForEach(Array(funnel.steps.enumerated()), id: \.offset) { index, step in
                let isLeak = funnel.leak?.step == index
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: step.event).lineLimit(1).fontWeight(isLeak ? .semibold : .regular)
                        Spacer()
                        Text(verbatim: Format.count(step.count)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLeak ? AnyShapeStyle(Brand.coral) : AnyShapeStyle(Brand.buttonGradient))
                            .frame(width: max(3, proxy.size.width * step.count / first))
                    }
                    .frame(height: 8)
                }
            }
            if let leak = funnel.leak {
                Label("\(Format.count(leak.lost)) people stop before \(leak.toEvent)", systemImage: "drop.fill")
                    .font(.caption).foregroundStyle(Brand.coral).lineLimit(2)
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
