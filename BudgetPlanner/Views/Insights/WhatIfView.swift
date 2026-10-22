import SwiftUI
import Charts

/// Estimates future savings when income or spending changes.
struct WhatIfView: View {
    @Environment(DataStore.self) private var store

    @State private var incomeText = ""
    @State private var expensesText = ""
    @State private var incomeChangeText = ""
    @State private var incomeIsIncrease = true
    @State private var expenseChangeText = ""
    @State private var expenseIsIncrease = false
    @State private var oneOffText = ""
    @State private var months = 12
    @State private var loaded = false

    private var scenario: WhatIfScenario {
        func value(_ text: String) -> Decimal { AmountInput.parse(text) ?? 0 }
        return WhatIfScenario(
            monthlyIncome: value(incomeText),
            monthlyExpenses: value(expensesText),
            incomeChange: incomeIsIncrease ? value(incomeChangeText) : -value(incomeChangeText),
            expenseChange: expenseIsIncrease ? value(expenseChangeText) : -value(expenseChangeText),
            oneOffCost: value(oneOffText),
            startingSavings: store.engine.totalInGoals,
            months: months
        )
    }

    private struct Preset: Identifiable {
        let title: String
        let apply: () -> Void
        var id: String { title }
    }

    var body: some View {
        let result = scenario
        Form {
            Section {
                AmountRow(title: "Money in", text: $incomeText)
                AmountRow(title: "Spending", text: $expensesText)
            } header: {
                Text("A usual month")
            } footer: {
                let averages = store.engine.monthlyAverages()
                if averages.hasEnoughHistory {
                    Text("Filled in from your last \(min(90, averages.daysOfHistory)) days. You can change these.")
                } else {
                    Text("Enter your usual monthly income and spending.")
                }
            }

            Section("Try a change") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button(preset.title, action: preset.apply)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                ChangeRow(title: "Income each month", text: $incomeChangeText, isIncrease: $incomeIsIncrease)
                ChangeRow(title: "Spending each month", text: $expenseChangeText, isIncrease: $expenseIsIncrease)
                AmountRow(title: "One-off cost", text: $oneOffText)
                Picker("Over", selection: $months) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("1 year").tag(12)
                    Text("2 years").tag(24)
                }
            }

            Section("Result") {
                HStack {
                    StatColumn(title: "Saved per month now", value: result.currentMonthly, color: result.currentMonthly.balanceColor)
                    StatColumn(title: "With changes", value: result.newMonthly, color: result.newMonthly < 0 ? Theme.danger : Theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("After \(monthsLabel), your savings would be")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(result.scenarioTotal.currencyWhole)
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(result.scenarioTotal.balanceColor)
                    let difference = result.scenarioTotal - result.currentTotal
                    if difference != 0 {
                        Text("\(difference > 0 ? "+" : "−")\((difference > 0 ? difference : -difference).currencyWhole) compared with no changes (\(result.currentTotal.currencyWhole))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(difference > 0 ? Color.green : Theme.warning)
                    }
                }
                .padding(.vertical, 4)

                Chart {
                    ForEach(result.points) { point in
                        LineMark(x: .value("Month", point.month), y: .value("Savings", point.current.doubleValue))
                            .foregroundStyle(by: .value("Scenario", "No changes"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        LineMark(x: .value("Month", point.month), y: .value("Savings", point.scenario.doubleValue))
                            .foregroundStyle(by: .value("Scenario", "With changes"))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.4))
                }
                .chartForegroundStyleScale(["No changes": Color.gray, "With changes": Theme.accent])
                .chartXAxisLabel("Months from now")
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
                .padding(.vertical, 6)

                if result.startingSavings > 0 {
                    Text("Starts from the \(result.startingSavings.currencyWhole) already in your savings goals. Estimates only – real months vary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Estimates only – real months vary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset to my usual month") { loadDefaults(force: true) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadDefaults(force: false) }
    }

    private var monthsLabel: String {
        switch months {
        case 12: return "1 year"
        case 24: return "2 years"
        default: return "\(months) months"
        }
    }

    private var presets: [Preset] {
        let byCategory = store.engine.monthlySpendingByCategory()
        let eatingOut = byCategory.first { $0.category == .eatingOut }?.amount ?? 0
        return [
            Preset(title: "Extra shift a week (+$150)") {
                incomeChangeText = AmountInput.text(for: (Decimal(150) * 52 / 12).rounded(0))
                incomeIsIncrease = true
            },
            Preset(title: "Rent up $30 a week") {
                expenseChangeText = AmountInput.text(for: (Decimal(30) * 52 / 12).rounded(0))
                expenseIsIncrease = true
            },
            Preset(title: "Halve eating out") {
                expenseChangeText = AmountInput.text(for: max(1, (eatingOut / 2).rounded(0)))
                expenseIsIncrease = false
            },
            Preset(title: "Cancel a subscription") {
                expenseChangeText = "15"
                expenseIsIncrease = false
            },
            Preset(title: "Fewer hours (−$300/mo)") {
                incomeChangeText = "300"
                incomeIsIncrease = false
            },
        ]
    }

    private func loadDefaults(force: Bool) {
        guard force || !loaded else { return }
        loaded = true
        let averages = store.engine.monthlyAverages()
        incomeText = AmountInput.text(for: averages.income.rounded(0))
        expensesText = AmountInput.text(for: averages.expenses.rounded(0))
        incomeChangeText = ""
        expenseChangeText = ""
        oneOffText = ""
    }
}

private struct AmountRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            AmountField(title: "0", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }
}

private struct ChangeRow: View {
    let title: String
    @Binding var text: String
    @Binding var isIncrease: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Picker(title, selection: $isIncrease) {
                    Text("Up").tag(true)
                    Text("Down").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }
            HStack {
                Text(isIncrease ? "Goes up by" : "Goes down by")
                    .foregroundStyle(.secondary)
                Spacer()
                AmountField(title: "0", text: $text)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
            .font(.subheadline)
        }
    }
}
