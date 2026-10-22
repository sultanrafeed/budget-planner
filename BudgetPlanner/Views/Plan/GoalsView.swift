import SwiftUI
import UIKit

struct GoalsView: View {
    @Environment(DataStore.self) private var store
    @State private var addingNew = false

    var body: some View {
        let engine = store.engine
        let goals = store.data.goals.sorted { lhs, rhs in
            // Unfinished goals first, then oldest first.
            if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
            return lhs.createdAt < rhs.createdAt
        }
        let capacity = engine.savingsCapacity

        List {
            Section {
                HStack {
                    StatColumn(title: "Total saved", value: engine.totalInGoals, color: Theme.accent)
                    StatColumn(title: "Still to save", value: goals.reduce(0) { $0 + $1.remaining })
                }
                .padding(.vertical, 4)
            } footer: {
                if capacity.averages.hasEnoughHistory {
                    if capacity.realisticMonthly > 0 {
                        Text("Based on your recent income and spending, you could realistically put aside about \(capacity.realisticMonthly.currencyWhole) a month (\(capacity.realisticWeekly.currencyWhole) a week).")
                    } else {
                        Text("You're currently spending more than you earn, so start small – even $10 a week adds up to $520 a year.")
                    }
                }
            }

            if goals.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save for what matters")
                            .font(.headline)
                        Text("An emergency fund, a holiday, a car or a new laptop. Set a target and a date and we'll work out how much to put aside each week.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Create a goal") { addingNew = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section("Goals") {
                    ForEach(goals) { goal in
                        NavigationLink(value: goal.id) {
                            GoalRow(goal: goal)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            GoalDetailView(goalID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add goal")
            }
        }
        .sheet(isPresented: $addingNew) { GoalFormView(goal: nil) }
    }
}

struct GoalRow: View {
    let goal: SavingsGoal

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(goal.isComplete ? Color.green : Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: goal.isComplete ? "checkmark" : goal.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(goal.isComplete ? Color.green : Theme.accent)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(goal.name).font(.body.weight(.medium))
                    if goal.isSample { SampleBadge() }
                }
                Text("\(goal.saved.currency) of \(goal.target.currency)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if goal.isComplete {
                    Text("Goal reached 🎉").font(.caption.weight(.semibold)).foregroundStyle(.green)
                } else if let date = goal.targetDate, let req = GoalPlanner.required(remaining: goal.remaining, from: Date(), to: date) {
                    Text("\(req.perWeek.currencyWhole) a week to reach it by \(date.dayMonthYear)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let date = goal.targetDate, date <= Date() {
                    Text("Target date has passed").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            Spacer(minLength: 0)
            Text("\(Int((goal.progress * 100).rounded()))%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct GoalDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID

    @State private var contribution: GoalContributionSheet.Mode?
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var weeklyText = ""

    private var goal: SavingsGoal? { store.data.goals.first { $0.id == goalID } }

    var body: some View {
        if let goal {
            List {
                Section {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 14)
                            Circle()
                                .trim(from: 0, to: goal.progress)
                                .stroke(goal.isComplete ? Color.green.gradient : Theme.accent.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Image(systemName: goal.symbol).font(.title2).foregroundStyle(Theme.accent)
                                Text(goal.saved.currencyWhole).font(.title.bold().monospacedDigit())
                                Text("of \(goal.target.currencyWhole)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 180, height: 180)
                        .padding(.top, 8)

                        HStack(spacing: 12) {
                            Button { contribution = .add } label: {
                                Label("Add money", systemImage: "plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Button { contribution = .withdraw } label: {
                                Label("Take out", systemImage: "minus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(goal.saved <= 0)
                        }
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                planSection(goal)

                Section("History") {
                    if goal.contributions.isEmpty {
                        Text("No money added yet.").foregroundStyle(.secondary)
                    }
                    ForEach(goal.contributions.sorted { $0.date > $1.date }) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.note.isEmpty ? (item.amount >= 0 ? "Added" : "Taken out") : item.note)
                                Text(item.date.dayMonthYear).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.amount.signedCurrency)
                                .monospacedDigit()
                                .foregroundStyle(item.amount >= 0 ? Theme.income : .primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.deleteContribution(item.id, from: goal.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                } footer: {
                    Text("Money added to a goal is set aside from your available balance. Taking it out puts it back.")
                }
            }
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = true } label: { Label("Edit goal", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete goal", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $contribution) { mode in
                GoalContributionSheet(goal: goal, mode: mode)
            }
            .sheet(isPresented: $editing) { GoalFormView(goal: goal) }
            .confirmationDialog("Delete \(goal.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete goal", role: .destructive) {
                    store.deleteGoal(goal.id)
                    dismiss()
                }
            } message: {
                Text("The \(goal.saved.currency) saved will go back into your available balance.")
            }
        } else {
            ContentUnavailableView("Goal not found", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func planSection(_ goal: SavingsGoal) -> some View {
        Section {
            if goal.isComplete {
                Label("You've reached this goal. Nice work!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if let date = goal.targetDate, let req = GoalPlanner.required(remaining: goal.remaining, from: Date(), to: date) {
                Text("To reach \(goal.remaining.currency) more by \(date.longDate) (\(req.daysLeft) days), put aside:")
                    .font(.subheadline)
                HStack {
                    StatColumn(title: "Each week", value: req.perWeek, color: Theme.accent)
                    StatColumn(title: "Each fortnight", value: req.perFortnight)
                    StatColumn(title: "Each month", value: req.perMonth)
                }
                let capacity = store.engine.savingsCapacity
                if capacity.averages.hasEnoughHistory && req.perMonth > capacity.realisticMonthly {
                    Label("That's more than the \(capacity.realisticMonthly.currencyWhole) a month you can realistically save right now. Consider a later date or trimming spending.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            } else {
                if let date = goal.targetDate {
                    Label("The target date (\(date.dayMonthYear)) has passed. Edit the goal to set a new one.", systemImage: "calendar.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                }
                HStack {
                    Text("If I save")
                    AmountField(title: "50", text: $weeklyText)
                        .frame(maxWidth: 110)
                    Text("a week")
                }
                if let perWeek = AmountInput.parse(weeklyText), perWeek > 0,
                   let finish = GoalPlanner.finishDate(remaining: goal.remaining, perWeek: perWeek, from: Date()) {
                    Text("you'll reach \(goal.target.currencyWhole) around **\(finish.longDate)**.")
                } else {
                    Text("Enter a weekly amount to see when you'll get there.")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Plan")
        }
    }
}

struct GoalContributionSheet: View {
    enum Mode: String, Identifiable {
        case add, withdraw
        var id: String { rawValue }
    }

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal
    let mode: Mode

    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "0.00", text: $amountText, large: true)
                        .focused($focused)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let problem { Text(problem).foregroundStyle(Theme.danger) }
                        if mode == .add {
                            Text("Available to move: \(store.engine.availableBalance.currency)")
                        } else {
                            Text("In this goal: \(goal.saved.currency)")
                        }
                    }
                }
                if mode == .add, let pay = store.settings.pay, store.settings.savingsPerPay > 0 {
                    Section {
                        Button("Use my usual \(store.settings.savingsPerPay.currency) per pay") {
                            amountText = AmountInput.text(for: store.settings.savingsPerPay)
                        }
                    } footer: {
                        Text("You plan to save this from each \(pay.frequency.title.lowercased()) pay.")
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle(mode == .add ? "Add to \(goal.name)" : "Take out of \(goal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        if let message = AmountInput.problem(with: amountText) {
            problem = message
            return
        }
        let amount = AmountInput.parse(amountText) ?? 0
        if mode == .withdraw && amount > goal.saved {
            problem = "You can take out up to \(goal.saved.currency)."
            return
        }
        store.addContribution(
            GoalContribution(date: date, amount: mode == .add ? amount : -amount, note: note.trimmingCharacters(in: .whitespaces)),
            to: goal.id
        )
        dismiss()
    }
}

struct GoalFormView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: SavingsGoal?
    @State private var name: String
    @State private var symbol: String
    @State private var targetText: String
    @State private var hasDate: Bool
    @State private var targetDate: Date
    @State private var startingText = ""
    @State private var problem: String?

    init(goal: SavingsGoal?) {
        original = goal
        _name = State(initialValue: goal?.name ?? "")
        _symbol = State(initialValue: goal?.symbol ?? "star.fill")
        _targetText = State(initialValue: goal.map { AmountInput.text(for: $0.target) } ?? "")
        _hasDate = State(initialValue: goal?.targetDate != nil)
        _targetDate = State(initialValue: goal?.targetDate
            ?? AppLocale.calendar.date(byAdding: .month, value: 6, to: Date())!)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Emergency fund", text: $name)
                    AmountField(title: "Target amount", text: $targetText)
                } footer: {
                    if let problem { Text(problem).foregroundStyle(Theme.danger) }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(SavingsGoal.symbolChoices, id: \.self) { choice in
                            Button { symbol = choice } label: {
                                Image(systemName: choice)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(symbol == choice ? .white : Theme.accent)
                                    .background(symbol == choice ? Theme.accent : Theme.accent.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Reach it by a date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Target date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    if hasDate, let target = AmountInput.parse(targetText), target > 0,
                       let req = GoalPlanner.required(remaining: max(0, target - (original?.saved ?? AmountInput.parse(startingText) ?? 0)), from: Date(), to: targetDate) {
                        Text("You'll need to save about \(req.perWeek.currencyWhole) a week or \(req.perMonth.currencyWhole) a month.")
                    }
                }

                if original == nil {
                    Section {
                        AmountField(title: "Already saved (optional)", text: $startingText)
                    } footer: {
                        Text("This amount is moved from your available balance into the goal.")
                    }
                }
            }
            .navigationTitle(original == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            problem = "Give the goal a name."
            return
        }
        if let message = AmountInput.problem(with: targetText) {
            problem = message
            return
        }
        if !startingText.isEmpty, AmountInput.parse(startingText) == nil {
            problem = "Check the amount already saved."
            return
        }
        var goal = original ?? SavingsGoal(name: trimmed, target: 0)
        goal.name = trimmed
        goal.symbol = symbol
        goal.target = AmountInput.parse(targetText) ?? 0
        goal.targetDate = hasDate ? AppLocale.calendar.startOfDay(for: targetDate) : nil
        goal.isSample = false
        if original == nil, let starting = AmountInput.parse(startingText), starting > 0 {
            goal.contributions.append(GoalContribution(date: Date(), amount: starting, note: "Starting amount"))
        }
        store.save(goal)
        dismiss()
    }
}

#Preview {
    NavigationStack { GoalsView() }.environment(DataStore.preview())
}
