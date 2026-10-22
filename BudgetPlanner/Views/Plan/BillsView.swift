import SwiftUI

struct BillsView: View {
    @Environment(DataStore.self) private var store
    @State private var editing: Bill?
    @State private var addingNew = false
    @State private var paidCount = 0
    @State private var showInactive = false

    var body: some View {
        let engine = store.engine
        let cal = AppLocale.calendar
        let active = engine.activeBills.sorted { $0.nextDueDate < $1.nextDueDate }
        let today = engine.startOfToday
        let weekAhead = cal.date(byAdding: .day, value: 7, to: today)!
        let overdue = active.filter { $0.nextDueDate < today }
        let soon = active.filter { $0.nextDueDate >= today && $0.nextDueDate < weekAhead }
        let later = active.filter { $0.nextDueDate >= weekAhead }
        let finished = store.data.bills.filter { !$0.isActive }

        List {
            if active.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Never miss a payment")
                            .font(.headline)
                        Text("Add rent, phone, internet, insurance and subscriptions. You'll get a reminder before each one is due, and paying it takes one swipe.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Add a bill") { addingNew = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    HStack {
                        StatColumn(title: "Bills per month", value: engine.monthlyBillsCost)
                        StatColumn(title: "Due next 30 days", value: engine.upcomingBills(days: 30).reduce(0) { $0 + $1.bill.amount })
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Swipe right on a bill to mark it paid. This records the payment and moves the bill to its next due date.")
                }
            }

            billSection("Overdue", overdue)
            billSection("Next 7 days", soon)
            billSection("Later", later)

            if !finished.isEmpty {
                Section {
                    DisclosureGroup("Finished one-off bills (\(finished.count))", isExpanded: $showInactive) {
                        ForEach(finished) { bill in
                            HStack {
                                Text(bill.name)
                                Spacer()
                                Text(bill.amount.currency).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.deleteBill(bill.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add bill")
            }
        }
        .sheet(isPresented: $addingNew) { BillFormView(bill: nil) }
        .sheet(item: $editing) { BillFormView(bill: $0) }
        .sensoryFeedback(.success, trigger: paidCount)
    }

    @ViewBuilder
    private func billSection(_ title: String, _ bills: [Bill]) -> some View {
        if !bills.isEmpty {
            Section(title) {
                ForEach(bills) { bill in
                    Button { editing = bill } label: { BillRow(bill: bill) }
                        .tint(.primary)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.markPaid(bill.id)
                                paidCount += 1
                            } label: {
                                Label("Paid", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.deleteBill(bill.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if bill.frequency != .once {
                                Button { store.skip(bill.id) } label: {
                                    Label("Skip", systemImage: "forward.end")
                                }
                                .tint(.orange)
                            }
                        }
                }
            }
        }
    }
}

struct BillRow: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: bill.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bill.name).lineLimit(1)
                    if bill.isSample { SampleBadge() }
                }
                Text(dueLabel(for: bill.nextDueDate))
                    .font(.caption)
                    .foregroundStyle(bill.nextDueDate < AppLocale.calendar.startOfDay(for: Date()) ? Theme.danger : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(bill.amount.currency).font(.body.monospacedDigit())
                HStack(spacing: 3) {
                    if bill.remindDaysBefore != nil {
                        Image(systemName: "bell.fill").font(.system(size: 9))
                    }
                    Text(bill.frequency.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BillFormView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Bill?
    @State private var name: String
    @State private var amountText: String
    @State private var category: Category
    @State private var frequency: Frequency
    @State private var dueDate: Date
    @State private var reminder: Int?
    @State private var problem: String?
    @State private var confirmDelete = false

    private struct ReminderOption: Identifiable {
        let title: String
        let days: Int?
        var id: String { title }
    }

    private static let reminderOptions = [
        ReminderOption(title: "No reminder", days: nil), ReminderOption(title: "On the day", days: 0),
        ReminderOption(title: "1 day before", days: 1), ReminderOption(title: "2 days before", days: 2),
        ReminderOption(title: "3 days before", days: 3), ReminderOption(title: "1 week before", days: 7),
    ]

    private struct Preset: Identifiable {
        let name: String
        let category: Category
        let frequency: Frequency
        var id: String { name }
    }

    /// Common Australian bills to fill the form in one tap.
    private static let presets = [
        Preset(name: "Rent", category: .rent, frequency: .weekly),
        Preset(name: "Electricity", category: .utilities, frequency: .quarterly),
        Preset(name: "Phone", category: .phoneInternet, frequency: .monthly),
        Preset(name: "Internet", category: .phoneInternet, frequency: .monthly),
        Preset(name: "Car rego", category: .transport, frequency: .yearly),
        Preset(name: "Car insurance", category: .insurance, frequency: .monthly),
        Preset(name: "Health insurance", category: .insurance, frequency: .monthly),
        Preset(name: "Netflix", category: .subscriptions, frequency: .monthly),
        Preset(name: "Spotify", category: .subscriptions, frequency: .monthly),
        Preset(name: "Gym", category: .subscriptions, frequency: .fortnightly),
        Preset(name: "Water", category: .utilities, frequency: .quarterly),
        Preset(name: "Gas", category: .utilities, frequency: .quarterly),
    ]

    init(bill: Bill?) {
        original = bill
        _name = State(initialValue: bill?.name ?? "")
        _amountText = State(initialValue: bill.map { AmountInput.text(for: $0.amount) } ?? "")
        _category = State(initialValue: bill?.category ?? .utilities)
        _frequency = State(initialValue: bill?.frequency ?? .monthly)
        _dueDate = State(initialValue: bill?.nextDueDate ?? AppLocale.calendar.startOfDay(for: Date()))
        _reminder = State(initialValue: bill == nil ? 1 : bill?.remindDaysBefore)
    }

    var body: some View {
        NavigationStack {
            Form {
                if original == nil {
                    Section("Quick pick") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.presets) { preset in
                                    Button(preset.name) {
                                        name = preset.name
                                        category = preset.category
                                        frequency = preset.frequency
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }

                Section {
                    TextField("Name, e.g. Rent", text: $name)
                    AmountField(title: "Amount", text: $amountText)
                } footer: {
                    if let problem { Text(problem).foregroundStyle(Theme.danger) }
                }

                Section {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker(original == nil ? "First due" : "Next due", selection: $dueDate, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(Category.expenseCategories) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section {
                    Picker("Remind me", selection: $reminder) {
                        ForEach(Self.reminderOptions) { option in
                            Text(option.title).tag(option.days)
                        }
                    }
                } footer: {
                    if !store.settings.billRemindersEnabled {
                        Text("Bill reminders are switched off in Settings.")
                    } else {
                        Text("Reminders arrive at 9 am.")
                    }
                }

                if let original {
                    Section {
                        Button("Mark as paid today") {
                            if save(dismissAfter: false) { store.markPaid(original.id) }
                            dismiss()
                        }
                        if original.frequency != .once {
                            Button("Skip this payment") {
                                if save(dismissAfter: false) { store.skip(original.id) }
                                dismiss()
                            }
                        }
                    } footer: {
                        if let paid = original.lastPaidDate {
                            Text("Last paid \(paid.dayMonthYear).")
                        }
                    }
                    Section {
                        Button("Delete bill", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { _ = save(dismissAfter: true) }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete this bill?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original { store.deleteBill(original.id) }
                    dismiss()
                }
            } message: {
                Text("Past payments stay in your activity.")
            }
        }
    }

    @discardableResult
    private func save(dismissAfter: Bool) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            problem = "Give the bill a name."
            return false
        }
        if let message = AmountInput.problem(with: amountText) {
            problem = message
            return false
        }
        let due = AppLocale.calendar.startOfDay(for: dueDate)
        var bill = original ?? Bill(name: trimmed, amount: 0, category: category, frequency: frequency, anchorDate: due, nextDueDate: due)
        bill.name = trimmed
        bill.amount = AmountInput.parse(amountText) ?? 0
        bill.category = category
        // Changing the date or how often it repeats restarts the schedule from the new date.
        if bill.nextDueDate != due || bill.frequency != frequency {
            bill.anchorDate = due
            bill.nextDueDate = due
        }
        bill.frequency = frequency
        bill.remindDaysBefore = reminder
        bill.isActive = true
        bill.isSample = false
        store.save(bill)

        if reminder != nil && store.settings.billRemindersEnabled {
            Task { _ = await store.requestReminderPermission() }
        }
        if dismissAfter { dismiss() }
        return true
    }
}

#Preview {
    NavigationStack { BillsView() }.environment(DataStore.preview())
}
