import SwiftUI

/// Organises money around paydays: what's safe to spend now, and a plan for the next pay.
struct PaydayView: View {
    @Environment(DataStore.self) private var store
    @State private var editingPay = false
    @State private var recordedPay = 0

    var body: some View {
        let engine = store.engine
        List {
            if let plan = engine.paydayPlan() {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.daysUntilPayday == 1 ? "Payday is tomorrow" : "Payday in \(plan.daysUntilPayday) days")
                            .font(.title2.bold())
                        Text("\(plan.nextPayday.weekdayDayMonth) · \(plan.frequency.title) pay of \(plan.payAmount.currency)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    row("Available now", engine.availableBalance)
                    ForEach(plan.billsBeforePayday) { item in
                        HStack {
                            CategoryIcon(category: item.bill.category, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.bill.name)
                                Text(dueLabel(for: item.date))
                                    .font(.caption)
                                    .foregroundStyle(item.isOverdue ? Theme.danger : .secondary)
                            }
                            Spacer()
                            Text("-" + item.bill.amount.currency).monospacedDigit()
                        }
                    }
                    if plan.billsBeforePayday.isEmpty {
                        Text("No bills due before payday").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Safe to spend").font(.headline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(plan.safeToSpend.currency)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(plan.safeToSpend.balanceColor)
                            if plan.safeToSpend > 0 {
                                Text("about \(plan.safePerDay.currency) a day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Until payday")
                } footer: {
                    if plan.safeToSpend < 0 {
                        Text("Your bills before payday add up to more than you have. Consider moving money back from savings, or contact the biller early about a payment plan.")
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("This is what's left after the bills due before your next pay.")
                    }
                }

                Section {
                    row("Pay", plan.payAmount, color: Theme.income)
                    row("Bills before the following payday (\(plan.nextCycleBills.count))", -plan.nextCycleBillsTotal)
                    row("Move to savings", -plan.savingsPerPay)
                    HStack {
                        Text("Free to spend").font(.headline)
                        Spacer()
                        Text(plan.nextCycleSpare.currency)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(plan.nextCycleSpare.balanceColor)
                    }
                    if plan.nextCycleSpare > 0 {
                        let days = max(1, AppLocale.calendar.dateComponents([.day], from: plan.nextPayday, to: plan.paydayAfterNext).day ?? 1)
                        Text("That's about \((plan.nextCycleSpare / Decimal(days)).rounded().currency) a day for groceries, transport and everything else.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Next pay · \(plan.nextPayday.dayMonth) to \(AppLocale.calendar.date(byAdding: .day, value: -1, to: plan.paydayAfterNext)!.dayMonth)")
                } footer: {
                    if plan.nextCycleSpare < 0 {
                        Text("Your next pay doesn't cover the bills and savings in that cycle. Try lowering the savings amount for this pay.")
                            .foregroundStyle(Theme.danger)
                    }
                }

                if !plan.nextCycleBills.isEmpty {
                    Section("Bills in the next pay cycle") {
                        ForEach(plan.nextCycleBills) { item in
                            HStack {
                                Text(item.bill.name)
                                Spacer()
                                Text(item.date.weekdayDayMonth).foregroundStyle(.secondary)
                                Text(item.bill.amount.currency).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section {
                    Button {
                        store.recordPay()
                        recordedPay += 1
                    } label: {
                        Label("I got paid – add \(plan.payAmount.currency) income", systemImage: "banknote")
                    }
                    Button { editingPay = true } label: {
                        Label("Change pay details", systemImage: "pencil")
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Plan around your payday")
                            .font(.headline)
                        Text("Tell us how much you're paid and when. We'll show what's safe to spend until your next pay, after the bills due before then.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Set up payday") { editingPay = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(isPresented: $editingPay) { PayScheduleForm() }
        .sensoryFeedback(.success, trigger: recordedPay)
    }

    private func row(_ title: String, _ value: Decimal, color: Color = .primary) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.currency)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

struct PayScheduleForm: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var frequency: Frequency
    @State private var payday: Date
    @State private var category: Category
    @State private var savingsText: String
    @State private var problem: String?

    init() {
        // Initial values are set in onAppear because the store comes from the environment.
        _amountText = State(initialValue: "")
        _frequency = State(initialValue: .fortnightly)
        _payday = State(initialValue: AppLocale.calendar.startOfDay(for: Date()))
        _category = State(initialValue: .salary)
        _savingsText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Take-home pay", text: $amountText)
                    Picker("How often", selection: $frequency) {
                        ForEach(Frequency.payFrequencies) { Text($0.title).tag($0) }
                    }
                    DatePicker("A recent or next payday", selection: $payday, displayedComponents: .date)
                    Picker("Pay type", selection: $category) {
                        ForEach(Category.incomeCategories) { Text($0.name).tag($0) }
                    }
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    } else {
                        Text("Use the amount that lands in your account after tax. Any past or future payday works – we count forward from it.")
                    }
                }

                Section {
                    AmountField(title: "Savings per pay (optional)", text: $savingsText)
                } footer: {
                    Text("How much you'd like to move to savings each payday. Used to plan your next pay.")
                }

                if store.settings.pay != nil {
                    Section {
                        Button("Remove payday", role: .destructive) {
                            store.updateSettings {
                                $0.pay = nil
                                $0.savingsPerPay = 0
                                $0.payIsSample = false
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Payday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
            .onAppear {
                guard let pay = store.settings.pay else { return }
                amountText = AmountInput.text(for: pay.amount)
                frequency = pay.frequency
                payday = pay.anchorDate
                category = pay.category
                savingsText = AmountInput.text(for: store.settings.savingsPerPay)
            }
        }
    }

    private func save() {
        if let message = AmountInput.problem(with: amountText) {
            problem = message
            return
        }
        let savings = savingsText.isEmpty ? 0 : (AmountInput.parse(savingsText) ?? -1)
        guard savings >= 0 else {
            problem = "Check the savings amount."
            return
        }
        let amount = AmountInput.parse(amountText) ?? 0
        guard savings <= amount else {
            problem = "Savings per pay can't be more than your pay."
            return
        }
        store.updateSettings {
            $0.pay = PaySchedule(amount: amount, frequency: frequency, anchorDate: AppLocale.calendar.startOfDay(for: payday), category: category)
            $0.savingsPerPay = savings
            $0.payIsSample = false
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { PaydayView() }.environment(DataStore.preview())
}
