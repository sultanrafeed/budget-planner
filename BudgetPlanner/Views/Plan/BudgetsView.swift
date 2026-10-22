import SwiftUI

struct BudgetsView: View {
    @Environment(DataStore.self) private var store
    @State private var editing: Budget?
    @State private var addingNew = false

    var body: some View {
        let engine = store.engine
        let statuses = engine.budgetStatuses
        List {
            if statuses.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Budgets help you stay on track")
                            .font(.headline)
                        Text("Set a limit for all your spending, or for categories like groceries or eating out. You'll see how much is left and what you can spend each day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        let averages = engine.monthlyAverages()
                        if averages.hasEnoughHistory && averages.expenses > 0 {
                            Text("Tip: you usually spend about \(averages.expenses.currencyWhole) a month.")
                                .font(.subheadline)
                        }
                        Button("Create a budget") { addingNew = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(BudgetPeriod.allCases.reversed()) { period in
                let rows = statuses.filter { $0.budget.period == period }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { status in
                            Button { editing = status.budget } label: {
                                BudgetRow(status: status)
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteBudget(status.budget.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(period == .monthly ? "This month · \(Date().monthYear)" : "This week · from \(engine.thisWeek.start.weekdayDayMonth)")
                    }
                }
            }

            if !statuses.isEmpty {
                Section {
                } footer: {
                    Text("The line on each bar shows how far through the \(statuses.count == 1 ? statuses[0].budget.period.noun : "period") you are. Staying left of it means you're on track.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add budget")
            }
        }
        .sheet(isPresented: $addingNew) { BudgetFormView(budget: nil) }
        .sheet(item: $editing) { BudgetFormView(budget: $0) }
    }
}

struct BudgetRow: View {
    let status: BudgetStatus

    private var detail: String {
        var text = "\(status.spent.currency) of \(status.budget.amount.currency) · \(status.daysLeft) \(status.daysLeft == 1 ? "day" : "days") left"
        if status.perDayLeft > 0 { text += " · \(status.perDayLeft.currency) a day" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let category = status.budget.category {
                    CategoryIcon(category: category, size: 30)
                } else {
                    Image(systemName: "sum")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(status.budget.name).font(.body.weight(.medium))
                        if status.budget.isSample { SampleBadge() }
                    }
                    Text(status.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.color(for: status.state))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(status.remaining >= 0 ? status.remaining.currency : (-status.remaining).currency)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(status.remaining < 0 ? Theme.danger : .primary)
                    Text(status.remaining >= 0 ? "left" : "over")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressBar(value: status.fractionSpent, tint: Theme.color(for: status.state), marker: status.fractionElapsed)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetFormView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Budget?
    @State private var category: Category?
    @State private var period: BudgetPeriod
    @State private var amountText: String
    @State private var problem: String?
    @State private var confirmDelete = false

    init(budget: Budget?) {
        original = budget
        _category = State(initialValue: budget?.category)
        _period = State(initialValue: budget?.period ?? .monthly)
        _amountText = State(initialValue: budget.map { AmountInput.text(for: $0.amount) } ?? "")
    }

    /// What the user usually spends in this category per period, as a guide.
    private var typicalSpend: Decimal? {
        let engine = store.engine
        let averages = engine.monthlyAverages()
        guard averages.hasEnoughHistory else { return nil }
        let monthly: Decimal
        if let category {
            monthly = engine.monthlySpendingByCategory().first { $0.category == category }?.amount ?? 0
        } else {
            monthly = averages.expenses
        }
        guard monthly > 0 else { return nil }
        return period == .monthly ? monthly : (monthly * 12 / 52).rounded(0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Budget for", selection: $category) {
                        Text("All spending").tag(Category?.none)
                        ForEach(Category.expenseCategories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Category?.some(category))
                        }
                    }
                    Picker("Period", selection: $period) {
                        ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    AmountField(title: "Amount", text: $amountText, large: true)
                } header: {
                    Text("Limit per \(period.noun)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let problem {
                            Text(problem).foregroundStyle(Theme.danger)
                        }
                        if let typicalSpend {
                            Text("You usually spend about \(typicalSpend.currencyWhole) a \(period.noun) on \(category?.name.lowercased() ?? "everything").")
                        }
                    }
                }

                if original != nil {
                    Section {
                        Button("Delete budget", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
            .confirmationDialog("Delete this budget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original { store.deleteBudget(original.id) }
                    dismiss()
                }
            } message: {
                Text("Your transactions are not affected.")
            }
        }
    }

    private func save() {
        if let message = AmountInput.problem(with: amountText) {
            problem = message
            return
        }
        let duplicate = store.data.budgets.contains {
            $0.id != original?.id && $0.category == category && $0.period == period
        }
        if duplicate {
            problem = "You already have a \(period.title.lowercased()) budget for \(category?.name.lowercased() ?? "all spending"). Edit that one instead."
            return
        }
        var budget = original ?? Budget(category: category, amount: 0, period: period)
        budget.category = category
        budget.period = period
        budget.amount = AmountInput.parse(amountText) ?? 0
        budget.isSample = false
        store.save(budget)
        dismiss()
    }
}

#Preview {
    NavigationStack { BudgetsView() }.environment(DataStore.preview())
}
