import SwiftUI
import Charts

/// The home screen answers five questions at a glance:
/// how much is available, where it's going, what's due next,
/// how much can be saved, and whether spending is within budget.
struct DashboardView: View {
    @Environment(DataStore.self) private var store
    @Binding var selectedTab: AppTab
    @State private var sheet: TransactionSheet?
    @State private var planSection: PlanView.Page?
    @State private var paidBill: Bill?

    var body: some View {
        let engine = store.engine
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.data.hasSampleData {
                        SampleDataBanner()
                    }
                    balanceCard(engine)
                    quickActions
                    budgetCard(engine)
                    billsCard(engine)
                    spendingCard(engine)
                    savingsCard(engine)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.screenBackground)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .add(.expense) } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add expense")
                }
            }
            .navigationDestination(item: $planSection) { section in
                PlanView(initialSection: section, embedded: true)
            }
            .transactionSheet($sheet)
            .sensoryFeedback(.success, trigger: paidBill)
        }
    }

    private var greeting: String {
        let hour = AppLocale.calendar.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: 1. How much money do I have?

    private func balanceCard(_ engine: FinanceEngine) -> some View {
        let available = engine.availableBalance
        let plan = engine.paydayPlan()
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Available now")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(available.currency)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if engine.totalInGoals > 0 {
                    Text("Plus \(engine.totalInGoals.currency) set aside in savings")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Divider().overlay(.white.opacity(0.3))

            if let plan {
                Button { planSection = .payday } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safe to spend until payday")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(plan.safeToSpend.currency)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(plan.daysUntilPayday == 1 ? "Payday tomorrow" : "Payday in \(plan.daysUntilPayday) days")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(plan.safeToSpend > 0 ? "\(plan.safePerDay.currency) a day" : "Bills need more than you have")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens payday planning")
            } else {
                Button { planSection = .payday } label: {
                    Label("Set your payday to see what's safe to spend", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: available < 0 ? [.red, .orange] : [Theme.accent, Theme.accent.opacity(0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickButton("Expense", systemImage: "minus", tint: .red) { sheet = .add(.expense) }
            quickButton("Income", systemImage: "plus", tint: .green) { sheet = .add(.income) }
            quickButton("Bills", systemImage: "calendar", tint: .blue) { planSection = .bills }
        }
    }

    private func quickButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.15), in: Circle())
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Bills" ? "View bills" : "Add \(title.lowercased())")
    }

    // MARK: 5. Am I staying within my budget?

    private func budgetCard(_ engine: FinanceEngine) -> some View {
        let statuses = engine.budgetStatuses
        let main = engine.primaryBudgetStatus
        let others = statuses.filter { $0.budget.id != main?.budget.id }.prefix(3)
        return Card(title: "Budget", systemImage: "chart.bar.fill") {
            if let main {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(main.remaining >= 0 ? main.remaining.currency : (-main.remaining).currency)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(main.remaining.balanceColor)
                        Text(main.remaining >= 0 ? "left this \(main.budget.period.noun)" : "over budget")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(main.state.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Theme.color(for: main.state))
                            .background(Theme.color(for: main.state).opacity(0.15), in: Capsule())
                    }
                    ProgressBar(value: main.fractionSpent, tint: Theme.color(for: main.state), marker: main.fractionElapsed)
                    Text(budgetDetail(main))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !others.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(others)) { status in
                        HStack(spacing: 10) {
                            if let category = status.budget.category {
                                CategoryIcon(category: category, size: 26)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(status.budget.name).font(.subheadline)
                                    Spacer()
                                    Text(status.remaining >= 0 ? "\(status.remaining.currencyWhole) left" : "\((-status.remaining).currencyWhole) over")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(status.remaining < 0 ? Theme.danger : .secondary)
                                }
                                ProgressBar(value: status.fractionSpent, tint: Theme.color(for: status.state), height: 6)
                            }
                        }
                    }
                }
                .padding(.top, main == nil ? 0 : 4)
            }
            if statuses.isEmpty {
                Text("Set a weekly or monthly limit to see how much you have left to spend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(statuses.isEmpty ? "Create a budget" : "See all budgets") { planSection = .budgets }
                .font(.subheadline.weight(.semibold))
        }
    }

    private func budgetDetail(_ status: BudgetStatus) -> String {
        var text = "\(status.spent.currencyWhole) of \(status.budget.amount.currencyWhole) spent · \(status.daysLeft) days left"
        if status.perDayLeft > 0 { text += " · \(status.perDayLeft.currencyWhole)/day" }
        return text
    }

    // MARK: 3. What's coming up?

    private func billsCard(_ engine: FinanceEngine) -> some View {
        let upcoming = engine.upcomingBills(days: 14)
        let total = upcoming.reduce(Decimal(0)) { $0 + $1.bill.amount }
        return Card(title: "Coming up · next 14 days", systemImage: "calendar") {
            if upcoming.isEmpty {
                Text(engine.activeBills.isEmpty ? "Add rent, phone and subscriptions to get reminders before they're due." : "Nothing due in the next two weeks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(upcoming.prefix(4)) { item in
                        HStack(spacing: 12) {
                            CategoryIcon(category: item.bill.category, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.bill.name).font(.subheadline.weight(.medium))
                                    if item.bill.isSample { SampleBadge() }
                                }
                                Text(dueLabel(for: item.date))
                                    .font(.caption)
                                    .foregroundStyle(item.isOverdue ? Theme.danger : .secondary)
                            }
                            Spacer()
                            Text(item.bill.amount.currency)
                                .font(.subheadline.monospacedDigit())
                            if item.date == item.bill.nextDueDate {
                                Button {
                                    store.markPaid(item.bill.id)
                                    paidBill = item.bill
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Mark \(item.bill.name) as paid")
                            }
                        }
                    }
                }
                if upcoming.count > 4 {
                    Text("+ \(upcoming.count - 4) more · \(total.currency) in total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(total.currency) in total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(engine.activeBills.isEmpty ? "Add a bill" : "See all bills") { planSection = .bills }
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: 2. Where is my money going?

    private func spendingCard(_ engine: FinanceEngine) -> some View {
        let month = engine.thisMonth
        let totals = engine.totals(in: month)
        let byCategory = engine.spendingByCategory(in: month)
        let top = Array(byCategory.prefix(4))
        return Card(title: "This month · \(Date().monthYear)", systemImage: "chart.pie.fill") {
            HStack {
                StatColumn(title: "Money in", value: totals.income, color: Theme.income)
                StatColumn(title: "Spent", value: totals.expenses)
                StatColumn(title: "Left over", value: totals.net, color: totals.net.balanceColor)
            }
            if byCategory.isEmpty {
                Text("No spending recorded this month yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    Chart(byCategory) { item in
                        SectorMark(angle: .value("Amount", item.amount.doubleValue), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(item.category.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(top) { item in
                            HStack(spacing: 6) {
                                Circle().fill(item.category.color).frame(width: 8, height: 8)
                                Text(item.category.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(item.amount.currencyWhole).font(.caption.monospacedDigit())
                                Text("\(Int((item.share * 100).rounded()))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            Button("See spending insights") { selectedTab = .insights }
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: 4. How much can I save?

    private func savingsCard(_ engine: FinanceEngine) -> some View {
        let capacity = engine.savingsCapacity
        let goals = store.data.goals.sorted { $0.progress > $1.progress }
        return Card(title: "Savings", systemImage: "banknote.fill") {
            if capacity.averages.hasEnoughHistory {
                if capacity.realisticMonthly > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You could realistically save")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(capacity.realisticMonthly.currencyWhole) a month")
                            .font(.title3.bold())
                        Text("About \(capacity.realisticWeekly.currencyWhole) a week, based on your last \(min(90, capacity.averages.daysOfHistory)) days. It leaves a 20% buffer for surprises.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Right now you're spending about \((-capacity.averages.surplus).currencyWhole) a month more than you earn. Check Insights for ideas to close the gap.")
                        .font(.subheadline)
                }
            } else {
                Text("Add a couple of weeks of income and spending to see how much you can save.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !goals.isEmpty {
                VStack(spacing: 10) {
                    ForEach(goals.prefix(3)) { goal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: goal.symbol).foregroundStyle(Theme.accent)
                                Text(goal.name).font(.subheadline)
                                Spacer()
                                Text("\(goal.saved.currencyWhole) of \(goal.target.currencyWhole)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressBar(value: goal.progress, tint: goal.isComplete ? .green : Theme.accent, height: 6)
                        }
                    }
                }
            }
            Button(goals.isEmpty ? "Create a savings goal" : "See savings goals") { planSection = .goals }
                .font(.subheadline.weight(.semibold))
        }
    }
}

#Preview {
    DashboardView(selectedTab: .constant(.home)).environment(DataStore.preview())
}
