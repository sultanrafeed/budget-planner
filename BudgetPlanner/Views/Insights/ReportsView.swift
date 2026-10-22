import SwiftUI
import Charts

/// Compares income, spending and saving across weeks or months.
struct ReportsView: View {
    @Environment(DataStore.self) private var store
    @State private var period: BudgetPeriod = .monthly
    @State private var exported: ExportedFile?

    private struct Bar: Identifiable {
        let label: String
        let start: Date
        let series: String
        let amount: Double
        var id: String { "\(start.timeIntervalSince1970)-\(series)" }
    }

    var body: some View {
        let engine = store.engine
        let count = period == .monthly ? 6 : 8
        let summaries = engine.periodSummaries(period, count: count)
        let bars = summaries.flatMap { summary in
            [
                Bar(label: summary.label, start: summary.interval.start, series: "Money in", amount: summary.totals.income.doubleValue),
                Bar(label: summary.label, start: summary.interval.start, series: "Spent", amount: summary.totals.expenses.doubleValue),
            ]
        }
        let current = engine.interval(for: period, containing: Date())
        let previous = engine.shifted(current, by: -1, period: period)
        let changes = engine.categoryComparison(current: current, previous: previous)
        let completed = summaries.dropLast().filter { $0.totals.income > 0 || $0.totals.expenses > 0 }
        let avgSpent = completed.isEmpty ? Decimal(0) : completed.reduce(Decimal(0)) { $0 + $1.totals.expenses } / Decimal(completed.count)
        let avgIn = completed.isEmpty ? Decimal(0) : completed.reduce(Decimal(0)) { $0 + $1.totals.income } / Decimal(completed.count)

        ScrollView {
            VStack(spacing: 16) {
                Picker("Compare", selection: $period) {
                    Text("Weeks").tag(BudgetPeriod.weekly)
                    Text("Months").tag(BudgetPeriod.monthly)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                Card(title: "Money in vs spent", systemImage: "chart.bar.xaxis") {
                    Chart(bars) { bar in
                        BarMark(
                            x: .value("Period", bar.label),
                            y: .value("Amount", bar.amount)
                        )
                        .foregroundStyle(by: .value("Type", bar.series))
                        .position(by: .value("Type", bar.series))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(["Money in": Color.green, "Spent": Theme.accent])
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) { Text(Decimal(amount).currencyWhole) }
                            }
                        }
                    }
                    .chartLegend(position: .top, alignment: .leading)
                    .frame(height: 220)

                    if !completed.isEmpty {
                        Text("Over the last \(completed.count) full \(period.noun)s you averaged \(avgIn.currencyWhole) in and \(avgSpent.currencyWhole) spent per \(period.noun).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Card(title: "\(period.title) summary", systemImage: "tablecells") {
                    VStack(spacing: 0) {
                        HStack {
                            Text(period == .monthly ? "Month" : "Week of").frame(maxWidth: .infinity, alignment: .leading)
                            Text("In").frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Spent").frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Left over").frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                        ForEach(summaries.reversed()) { summary in
                            Divider()
                            HStack {
                                Text(summary.label + (summary.id == summaries.last?.id ? " (now)" : ""))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(summary.totals.income.currencyWhole)
                                    .foregroundStyle(Theme.income)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(summary.totals.expenses.currencyWhole)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(summary.totals.net.currencyWhole)
                                    .foregroundStyle(summary.totals.net.balanceColor)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.subheadline.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 8)
                        }
                    }
                    Text("Left over is money in minus money spent. Money moved into savings goals isn't counted as spending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card(title: "This \(period.noun) vs last \(period.noun)", systemImage: "arrow.left.arrow.right") {
                    if changes.isEmpty {
                        Text("No spending to compare yet.").foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(changes.prefix(8)) { change in
                                HStack(spacing: 10) {
                                    CategoryIcon(category: change.category, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(change.category.name).font(.subheadline)
                                        Text("\(change.current.currencyWhole) vs \(change.previous.currencyWhole)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    changeLabel(change.change)
                                }
                            }
                        }
                        Text("This \(period.noun) isn't finished yet, so it may look lower than last \(period.noun).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    do {
                        exported = ExportedFile(url: try store.csvFile())
                    } catch {
                        store.errorMessage = "Couldn't create the export. \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export all transactions (CSV)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.data.transactions.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.screenBackground)
        .sheet(item: $exported) { file in
            ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func changeLabel(_ change: Decimal) -> some View {
        if change == 0 {
            Text("Same").font(.subheadline).foregroundStyle(.secondary)
        } else {
            Label((change > 0 ? change : -change).currencyWhole, systemImage: change > 0 ? "arrow.up" : "arrow.down")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(change > 0 ? Theme.warning : Color.green)
        }
    }
}
