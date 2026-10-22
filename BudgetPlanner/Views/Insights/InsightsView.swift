import SwiftUI
import Charts

struct InsightsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case spending = "Spending"
        case reports = "Reports"
        case whatIf = "What if"
        var id: String { rawValue }
    }

    @State private var page: Page = .spending

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .spending: SpendingInsightsView()
                case .reports: ReportsView()
                case .whatIf: WhatIfView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Page", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Insights")
        }
    }
}

// MARK: - Spending

struct SpendingInsightsView: View {
    @Environment(DataStore.self) private var store
    @State private var period: BudgetPeriod = .monthly
    /// 0 = this period, -1 = last period, …
    @State private var offset = 0
    @State private var selectedAngle: Double?

    var body: some View {
        let engine = store.engine
        let range = engine.shifted(engine.interval(for: period, containing: Date()), by: offset, period: period)
        let byCategory = engine.spendingByCategory(in: range)
        let total = byCategory.reduce(Decimal(0)) { $0 + $1.amount }
        let totals = engine.totals(in: range)
        let daily = engine.dailySpending(in: range)
        let selected = selectedCategory(in: byCategory)

        ScrollView {
            VStack(spacing: 16) {
                periodPicker(range)

                Card {
                    HStack {
                        StatColumn(title: "Money in", value: totals.income, color: Theme.income)
                        StatColumn(title: "Spent", value: totals.expenses)
                        StatColumn(title: "Left over", value: totals.net, color: totals.net.balanceColor)
                    }
                }

                Card(title: "Where your money went", systemImage: "chart.pie.fill") {
                    if byCategory.isEmpty {
                        Text("No spending in this \(period.noun).")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Chart(byCategory) { item in
                            SectorMark(
                                angle: .value("Amount", item.amount.doubleValue),
                                innerRadius: .ratio(0.62),
                                outerRadius: selected?.category == item.category ? .ratio(1) : .ratio(0.92),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.category.color)
                            .cornerRadius(4)
                            .opacity(selected == nil || selected?.category == item.category ? 1 : 0.4)
                        }
                        .chartAngleSelection(value: $selectedAngle)
                        .chartBackground { _ in
                            VStack(spacing: 2) {
                                Text(selected?.category.name ?? "Total spent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text((selected?.amount ?? total).currencyWhole)
                                    .font(.title2.bold().monospacedDigit())
                                if let selected {
                                    Text("\(Int((selected.share * 100).rounded()))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 230)
                        .accessibilityLabel("Spending by category chart")

                        VStack(spacing: 10) {
                            ForEach(byCategory) { item in
                                NavigationLink {
                                    CategoryTransactionsView(category: item.category, range: range)
                                } label: {
                                    CategoryShareRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !byCategory.isEmpty {
                    Card(title: "Spending by day", systemImage: "chart.bar.fill") {
                        let average = daily.isEmpty ? 0 : (total / Decimal(daily.count)).doubleValue
                        Chart {
                            ForEach(daily) { day in
                                BarMark(
                                    x: .value("Day", day.date, unit: .day),
                                    y: .value("Spent", day.amount.doubleValue)
                                )
                                .foregroundStyle(Theme.accent.gradient)
                                .cornerRadius(2)
                            }
                            RuleMark(y: .value("Average", average))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("avg \(Decimal(average).currencyWhole)/day")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) { Text(Decimal(amount).currencyWhole) }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: period == .weekly ? 1 : 7)) { value in
                                AxisValueLabel {
                                    if let date = value.as(Date.self) {
                                        Text(period == .weekly
                                             ? date.formatted(.dateTime.weekday(.abbreviated).locale(AppLocale.locale))
                                             : date.formatted(.dateTime.day().locale(AppLocale.locale)))
                                    }
                                }
                            }
                        }
                        .frame(height: 180)
                    }
                }

                SuggestionsCard(suggestions: engine.suggestions())
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.screenBackground)
        .onChange(of: period) { _, _ in offset = 0 }
    }

    private func selectedCategory(in items: [CategoryAmount]) -> CategoryAmount? {
        guard let selectedAngle else { return nil }
        var running = 0.0
        for item in items {
            running += item.amount.doubleValue
            if selectedAngle <= running { return item }
        }
        return nil
    }

    private func periodPicker(_ range: DateInterval) -> some View {
        VStack(spacing: 10) {
            Picker("Period", selection: $period) {
                Text("Week").tag(BudgetPeriod.weekly)
                Text("Month").tag(BudgetPeriod.monthly)
            }
            .pickerStyle(.segmented)

            HStack {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous \(period.noun)")
                Spacer()
                Text(label(for: range)).font(.headline)
                Spacer()
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(offset >= 0)
                    .accessibilityLabel("Next \(period.noun)")
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }

    private func label(for range: DateInterval) -> String {
        if period == .monthly { return range.start.monthYear }
        let end = AppLocale.calendar.date(byAdding: .day, value: -1, to: range.end)!
        return "\(range.start.dayMonth) – \(end.dayMonth)"
    }
}

struct CategoryShareRow: View {
    let item: CategoryAmount

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: item.category, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.category.name).font(.subheadline)
                    Spacer()
                    Text(item.amount.currency).font(.subheadline.monospacedDigit())
                    Text("\(Int((item.share * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                ProgressBar(value: item.share, tint: item.category.color, height: 5)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct CategoryTransactionsView: View {
    @Environment(DataStore.self) private var store
    let category: Category
    let range: DateInterval
    @State private var sheet: TransactionSheet?

    var body: some View {
        let items = store.engine.transactions(in: range)
            .filter { $0.category == category }
            .sorted { $0.date > $1.date }
        let total = items.reduce(Decimal(0)) { $0 + $1.amount }
        List {
            Section {
                ForEach(items) { tx in
                    Button { sheet = .edit(tx) } label: { TransactionRow(transaction: tx, showDate: true) }
                        .tint(.primary)
                }
            } footer: {
                Text("\(items.count) transactions · \(total.currency)")
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .transactionSheet($sheet)
    }
}

struct SuggestionsCard: View {
    let suggestions: [Suggestion]

    var body: some View {
        Card(title: "Ways to save", systemImage: "lightbulb.fill") {
            if suggestions.isEmpty {
                Text("Once you've recorded a couple of weeks of spending, you'll see practical ideas here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(suggestions) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(color(for: tip.tone))
                                .frame(width: 30, height: 30)
                                .background(color(for: tip.tone).opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(tip.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if let saving = tip.monthlySaving, saving > 0 {
                                        Text("\(saving.currencyWhole)/mo")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(tip.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for tone: Suggestion.Tone) -> Color {
        switch tone {
        case .tip: return Theme.accent
        case .warning: return Theme.warning
        case .praise: return .green
        }
    }
}

#Preview {
    InsightsView().environment(DataStore.preview())
}
