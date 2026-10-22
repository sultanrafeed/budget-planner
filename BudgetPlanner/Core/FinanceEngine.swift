import Foundation

// MARK: - Result types

struct PeriodTotals: Equatable {
    var income: Decimal = 0
    var expenses: Decimal = 0
    var net: Decimal { income - expenses }
}

struct CategoryAmount: Identifiable, Equatable {
    var category: Category
    var amount: Decimal
    /// Share of the total, 0...1.
    var share: Double
    var id: Category { category }
}

struct DayAmount: Identifiable, Equatable {
    var date: Date
    var amount: Decimal
    var id: Date { date }
}

struct BudgetStatus: Identifiable {
    enum State {
        case onTrack
        case spendingFast
        case over

        var label: String {
            switch self {
            case .onTrack: return "On track"
            case .spendingFast: return "Spending fast"
            case .over: return "Over budget"
            }
        }
    }

    var budget: Budget
    var interval: DateInterval
    var spent: Decimal
    var remaining: Decimal { budget.amount - spent }
    /// Share of the budget spent (can be above 1).
    var fractionSpent: Double
    /// Share of the period that has passed, 0...1.
    var fractionElapsed: Double
    /// Days left including today.
    var daysLeft: Int
    var perDayLeft: Decimal {
        guard daysLeft > 0, remaining > 0 else { return 0 }
        return (remaining / Decimal(daysLeft)).rounded()
    }

    var state: State {
        if spent > budget.amount { return .over }
        if fractionSpent > fractionElapsed + 0.1 && fractionSpent > 0.25 { return .spendingFast }
        return .onTrack
    }

    var id: UUID { budget.id }
}

struct BillOccurrence: Identifiable, Hashable {
    var bill: Bill
    var date: Date
    var isOverdue: Bool
    var id: String { "\(bill.id.uuidString)-\(date.timeIntervalSinceReferenceDate)" }
}

struct PaydayPlan {
    var payAmount: Decimal
    var frequency: Frequency
    var lastPayday: Date?
    var nextPayday: Date
    var paydayAfterNext: Date
    var daysUntilPayday: Int
    /// Bills due from today until the day before payday (including overdue ones).
    var billsBeforePayday: [BillOccurrence]
    var billsBeforePaydayTotal: Decimal
    /// Money left after paying those bills.
    var safeToSpend: Decimal
    var safePerDay: Decimal
    /// Bills due in the pay cycle that starts on the next payday.
    var nextCycleBills: [BillOccurrence]
    var nextCycleBillsTotal: Decimal
    var savingsPerPay: Decimal
    /// Next pay, minus bills in that cycle, minus planned savings.
    var nextCycleSpare: Decimal { payAmount - nextCycleBillsTotal - savingsPerPay }
}

struct MonthlyAverages: Equatable {
    var income: Decimal
    var expenses: Decimal
    /// How many days of history the average is based on.
    var daysOfHistory: Int
    var surplus: Decimal { income - expenses }
    var hasEnoughHistory: Bool { daysOfHistory >= 14 }
}

struct SavingsCapacity {
    var averages: MonthlyAverages
    /// A realistic monthly amount: 80% of the usual surplus, rounded down to $10,
    /// leaving a buffer for surprises.
    var realisticMonthly: Decimal {
        guard averages.surplus > 0 else { return 0 }
        let buffered = averages.surplus * Decimal(string: "0.8")!
        return (buffered / 10).rounded(0, .down) * 10
    }
    var realisticWeekly: Decimal { (realisticMonthly * 12 / 52).rounded(0) }
    /// Share of income left over, e.g. 0.15 = 15%.
    var savingsRate: Double {
        guard averages.income > 0 else { return 0 }
        return (averages.surplus / averages.income).doubleValue
    }
}

struct PeriodSummary: Identifiable {
    var interval: DateInterval
    var label: String
    var totals: PeriodTotals
    var movedToSavings: Decimal
    var id: Date { interval.start }
}

struct CategoryChange: Identifiable {
    var category: Category
    var current: Decimal
    var previous: Decimal
    var change: Decimal { current - previous }
    var id: Category { category }
}

struct Suggestion: Identifiable {
    enum Tone { case tip, warning, praise }
    var id: String
    var symbol: String
    var title: String
    var detail: String
    var monthlySaving: Decimal?
    var tone: Tone = .tip
}

// MARK: - Engine

/// All money maths in one place. It is a pure value type so results are
/// predictable and easy to test.
struct FinanceEngine {
    let data: AppData
    let now: Date
    var calendar: Calendar = AppLocale.calendar

    init(data: AppData, now: Date = Date(), calendar: Calendar = AppLocale.calendar) {
        self.data = data
        self.now = now
        self.calendar = calendar
    }

    static let daysPerMonth = Decimal(string: "30.4375")!

    var startOfToday: Date { calendar.startOfDay(for: now) }
    var startOfTomorrow: Date { calendar.date(byAdding: .day, value: 1, to: startOfToday)! }

    // MARK: Balance

    /// Total currently set aside in savings goals.
    var totalInGoals: Decimal { data.goals.reduce(0) { $0 + $1.saved } }

    /// Money you can use right now:
    /// opening balance + income − spending (up to today) − money moved into savings goals.
    var availableBalance: Decimal {
        let flows = data.transactions
            .filter { $0.date < startOfTomorrow }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }
        let moved = data.goals
            .flatMap(\.contributions)
            .filter { $0.date < startOfTomorrow }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return data.settings.openingBalance + flows - moved
    }

    // MARK: Periods

    func interval(for period: BudgetPeriod, containing date: Date) -> DateInterval {
        calendar.dateInterval(of: period.calendarComponent, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    var thisMonth: DateInterval { interval(for: .monthly, containing: now) }
    var thisWeek: DateInterval { interval(for: .weekly, containing: now) }

    func shifted(_ interval: DateInterval, by periods: Int, period: BudgetPeriod) -> DateInterval {
        let moved = calendar.date(byAdding: period.calendarComponent, value: periods, to: interval.start) ?? interval.start
        return self.interval(for: period, containing: moved)
    }

    // MARK: Totals

    func transactions(in interval: DateInterval) -> [Transaction] {
        data.transactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    func totals(in interval: DateInterval) -> PeriodTotals {
        transactions(in: interval).reduce(into: PeriodTotals()) { totals, tx in
            if tx.kind == .income { totals.income += tx.amount } else { totals.expenses += tx.amount }
        }
    }

    func spendingByCategory(in interval: DateInterval) -> [CategoryAmount] {
        var sums: [Category: Decimal] = [:]
        for tx in transactions(in: interval) where tx.kind == .expense {
            sums[tx.category, default: 0] += tx.amount
        }
        let total = sums.values.reduce(0, +)
        return sums
            .map { CategoryAmount(category: $0.key, amount: $0.value, share: total > 0 ? ($0.value / total).doubleValue : 0) }
            .sorted { $0.amount == $1.amount ? $0.category.name < $1.category.name : $0.amount > $1.amount }
    }

    func incomeByCategory(in interval: DateInterval) -> [CategoryAmount] {
        var sums: [Category: Decimal] = [:]
        for tx in transactions(in: interval) where tx.kind == .income {
            sums[tx.category, default: 0] += tx.amount
        }
        let total = sums.values.reduce(0, +)
        return sums
            .map { CategoryAmount(category: $0.key, amount: $0.value, share: total > 0 ? ($0.value / total).doubleValue : 0) }
            .sorted { $0.amount > $1.amount }
    }

    /// Spending per day, with a zero entry for days without spending.
    func dailySpending(in interval: DateInterval) -> [DayAmount] {
        var sums: [Date: Decimal] = [:]
        for tx in transactions(in: interval) where tx.kind == .expense {
            sums[calendar.startOfDay(for: tx.date), default: 0] += tx.amount
        }
        var days: [DayAmount] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(DayAmount(date: day, amount: sums[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    func movedToSavings(in interval: DateInterval) -> Decimal {
        data.goals.flatMap(\.contributions)
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: Budgets

    func status(for budget: Budget) -> BudgetStatus {
        let period = interval(for: budget.period, containing: now)
        let spent = transactions(in: period)
            .filter { $0.kind == .expense && (budget.category == nil || $0.category == budget.category) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let fractionSpent = budget.amount > 0 ? (spent / budget.amount).doubleValue : (spent > 0 ? 1.01 : 0)
        let elapsed = now.timeIntervalSince(period.start) / period.duration
        let daysLeft = max(0, calendar.dateComponents([.day], from: startOfToday, to: period.end).day ?? 0)
        return BudgetStatus(
            budget: budget,
            interval: period,
            spent: spent,
            fractionSpent: fractionSpent,
            fractionElapsed: min(1, max(0, elapsed)),
            daysLeft: daysLeft
        )
    }

    var budgetStatuses: [BudgetStatus] {
        data.budgets
            .sorted { lhs, rhs in
                if (lhs.category == nil) != (rhs.category == nil) { return lhs.category == nil }
                if lhs.period != rhs.period { return lhs.period == .monthly }
                return lhs.name < rhs.name
            }
            .map(status(for:))
    }

    /// The overall budget to headline on the dashboard (monthly first, then weekly).
    var primaryBudgetStatus: BudgetStatus? {
        let overall = data.budgets.filter { $0.category == nil }
        guard let budget = overall.first(where: { $0.period == .monthly }) ?? overall.first else { return nil }
        return status(for: budget)
    }

    // MARK: Bills

    var activeBills: [Bill] { data.bills.filter(\.isActive) }

    var overdueBills: [BillOccurrence] {
        activeBills
            .filter { $0.nextDueDate < startOfToday }
            .map { BillOccurrence(bill: $0, date: $0.nextDueDate, isOverdue: true) }
            .sorted { $0.date < $1.date }
    }

    /// Bill due dates within `interval`; overdue bills are included when `includeOverdue` is set.
    func billsDue(in interval: DateInterval, includeOverdue: Bool = false) -> [BillOccurrence] {
        var result = includeOverdue ? overdueBills : []
        for bill in activeBills {
            for date in bill.dueDates(in: interval, calendar: calendar) {
                result.append(BillOccurrence(bill: bill, date: date, isOverdue: date < startOfToday))
            }
        }
        return result.sorted { $0.date == $1.date ? $0.bill.name < $1.bill.name : $0.date < $1.date }
    }

    /// Overdue bills plus everything due in the next `days` days.
    func upcomingBills(days: Int = 30) -> [BillOccurrence] {
        let end = calendar.date(byAdding: .day, value: days, to: startOfToday) ?? startOfToday
        return billsDue(in: DateInterval(start: startOfToday, end: end), includeOverdue: true)
    }

    /// The typical monthly cost of all repeating bills.
    var monthlyBillsCost: Decimal { activeBills.reduce(0) { $0 + $1.monthlyCost } }

    // MARK: Payday

    func paydayPlan() -> PaydayPlan? {
        guard let pay = data.settings.pay, pay.frequency != .once,
              let next = pay.frequency.nextOccurrence(after: startOfToday, anchor: pay.anchorDate, calendar: calendar),
              let after = pay.frequency.nextOccurrence(after: next, anchor: pay.anchorDate, calendar: calendar)
        else { return nil }

        let last = pay.frequency.previousOccurrence(onOrBefore: startOfToday, anchor: pay.anchorDate, calendar: calendar)
        let before = billsDue(in: DateInterval(start: startOfToday, end: next), includeOverdue: true)
        let beforeTotal = before.reduce(Decimal(0)) { $0 + $1.bill.amount }
        let nextCycle = billsDue(in: DateInterval(start: next, end: after))
        let nextCycleTotal = nextCycle.reduce(Decimal(0)) { $0 + $1.bill.amount }
        let days = max(1, calendar.dateComponents([.day], from: startOfToday, to: next).day ?? 1)
        let safe = availableBalance - beforeTotal

        return PaydayPlan(
            payAmount: pay.amount,
            frequency: pay.frequency,
            lastPayday: last,
            nextPayday: next,
            paydayAfterNext: after,
            daysUntilPayday: days,
            billsBeforePayday: before,
            billsBeforePaydayTotal: beforeTotal,
            safeToSpend: safe,
            safePerDay: safe > 0 ? (safe / Decimal(days)).rounded() : 0,
            nextCycleBills: nextCycle,
            nextCycleBillsTotal: nextCycleTotal,
            savingsPerPay: data.settings.savingsPerPay
        )
    }

    // MARK: Averages and savings

    /// Average monthly income and spending, based on up to the last 90 days of history.
    func monthlyAverages(maxDays: Int = 90) -> MonthlyAverages {
        guard let first = data.transactions.map(\.date).min(), first < startOfTomorrow else {
            return MonthlyAverages(income: 0, expenses: 0, daysOfHistory: 0)
        }
        let earliest = calendar.date(byAdding: .day, value: -maxDays, to: startOfTomorrow)!
        let start = max(calendar.startOfDay(for: first), earliest)
        let window = DateInterval(start: start, end: startOfTomorrow)
        let days = max(1, calendar.dateComponents([.day], from: start, to: startOfTomorrow).day ?? 1)
        let totals = totals(in: window)
        return MonthlyAverages(
            income: (totals.income * FinanceEngine.daysPerMonth / Decimal(days)).rounded(),
            expenses: (totals.expenses * FinanceEngine.daysPerMonth / Decimal(days)).rounded(),
            daysOfHistory: days
        )
    }

    /// Average monthly spending per category over the same window as `monthlyAverages`.
    func monthlySpendingByCategory(maxDays: Int = 90) -> [CategoryAmount] {
        let averages = monthlyAverages(maxDays: maxDays)
        guard averages.daysOfHistory > 0 else { return [] }
        let start = calendar.date(byAdding: .day, value: -averages.daysOfHistory, to: startOfTomorrow)!
        let days = Decimal(averages.daysOfHistory)
        return spendingByCategory(in: DateInterval(start: start, end: startOfTomorrow))
            .map { CategoryAmount(category: $0.category, amount: ($0.amount * FinanceEngine.daysPerMonth / days).rounded(), share: $0.share) }
    }

    var savingsCapacity: SavingsCapacity { SavingsCapacity(averages: monthlyAverages()) }

    // MARK: Reports

    func periodSummaries(_ period: BudgetPeriod, count: Int) -> [PeriodSummary] {
        let current = interval(for: period, containing: now)
        return (0..<count).reversed().map { offset in
            let range = shifted(current, by: -offset, period: period)
            let label: String
            if period == .monthly {
                label = range.start.shortMonth
            } else {
                label = range.start.dayMonth
            }
            return PeriodSummary(interval: range, label: label, totals: totals(in: range), movedToSavings: movedToSavings(in: range))
        }
    }

    func categoryComparison(current: DateInterval, previous: DateInterval) -> [CategoryChange] {
        let now = Dictionary(uniqueKeysWithValues: spendingByCategory(in: current).map { ($0.category, $0.amount) })
        let before = Dictionary(uniqueKeysWithValues: spendingByCategory(in: previous).map { ($0.category, $0.amount) })
        return Set(now.keys).union(before.keys)
            .map { CategoryChange(category: $0, current: now[$0] ?? 0, previous: before[$0] ?? 0) }
            .sorted { max($0.current, $0.previous) > max($1.current, $1.previous) }
    }

    // MARK: Suggestions

    /// Plain-English, realistic ideas for saving money, most valuable first.
    func suggestions() -> [Suggestion] {
        var tips: [Suggestion] = []
        let averages = monthlyAverages()
        guard averages.hasEnoughHistory else { return [] }
        let byCategory = Dictionary(uniqueKeysWithValues: monthlySpendingByCategory().map { ($0.category, $0) })

        func share(_ c: Category) -> Double { byCategory[c]?.share ?? 0 }
        func monthly(_ c: Category) -> Decimal { byCategory[c]?.amount ?? 0 }

        // Spending more than earning.
        if averages.surplus < 0 {
            let biggest = byCategory.values.filter { $0.category != .rent }.max { $0.amount < $1.amount }
            let focus = biggest.map { " Start with \($0.category.name.lowercased()), your biggest flexible cost." } ?? ""
            tips.append(Suggestion(
                id: "overspending",
                symbol: "exclamationmark.triangle.fill",
                title: "You're spending more than you earn",
                detail: "On average you spend \((-averages.surplus).currencyWhole) more than you earn each month.\(focus)",
                tone: .warning
            ))
        }

        // Over budget right now.
        for status in budgetStatuses where status.state == .over {
            tips.append(Suggestion(
                id: "over-\(status.budget.id)",
                symbol: "chart.bar.xaxis",
                title: "Over your \(status.budget.name.lowercased()) budget",
                detail: "You're \((-status.remaining).currency) over this \(status.budget.period.noun). Hold off on extras in this area until it resets.",
                tone: .warning
            ))
        }

        if share(.eatingOut) > 0.08 && monthly(.eatingOut) > 60 {
            let saving = (monthly(.eatingOut) / 4).rounded(0)
            tips.append(Suggestion(
                id: "eating-out",
                symbol: "fork.knife",
                title: "Eat out a little less",
                detail: "Eating out costs about \(monthly(.eatingOut).currencyWhole) a month. Cooking a couple more meals at home and cutting this by a quarter saves around \(saving.currencyWhole) a month.",
                monthlySaving: saving
            ))
        }

        let subscriptions = activeBills.filter { $0.category == .subscriptions && $0.frequency != .once }
        if subscriptions.count >= 2 {
            let total = subscriptions.reduce(Decimal(0)) { $0 + $1.monthlyCost }
            let cheapest = subscriptions.min { $0.monthlyCost < $1.monthlyCost }!
            tips.append(Suggestion(
                id: "subscriptions",
                symbol: "repeat",
                title: "Review your subscriptions",
                detail: "You have \(subscriptions.count) subscriptions costing about \(total.currencyWhole) a month. Cancelling one you rarely use, like \(cheapest.name), saves \((cheapest.monthlyCost * 12).currencyWhole) a year.",
                monthlySaving: cheapest.monthlyCost
            ))
        }

        if share(.shopping) > 0.12 && monthly(.shopping) > 80 {
            let saving = (monthly(.shopping) / 5).rounded(0)
            tips.append(Suggestion(
                id: "shopping",
                symbol: "bag.fill",
                title: "Wait 48 hours before buying",
                detail: "Shopping is about \(monthly(.shopping).currencyWhole) a month. Waiting two days before non-essential buys could cut this by a fifth – around \(saving.currencyWhole) a month.",
                monthlySaving: saving
            ))
        }

        if share(.groceries) > 0.18 && monthly(.groceries) > 300 {
            let saving = (monthly(.groceries) / 10).rounded(0)
            tips.append(Suggestion(
                id: "groceries",
                symbol: "cart.fill",
                title: "Plan meals before you shop",
                detail: "Shopping with a list, buying home brands and checking Aldi or weekly specials can trim groceries by 10% – about \(saving.currencyWhole) a month.",
                monthlySaving: saving
            ))
        }

        if share(.transport) > 0.10 && monthly(.transport) > 100 {
            tips.append(Suggestion(
                id: "transport",
                symbol: "tram.fill",
                title: "Check your transport costs",
                detail: "Transport is about \(monthly(.transport).currencyWhole) a month. Off-peak travel and the weekly fare caps on Opal, Myki and go card can lower this. Concession fares may apply if you study.",
                monthlySaving: (monthly(.transport) / 10).rounded(0)
            ))
        }

        // Categories that jumped compared with the month before.
        let lastMonth = shifted(thisMonth, by: -1, period: .monthly)
        let monthBefore = shifted(thisMonth, by: -2, period: .monthly)
        let changes = categoryComparison(current: lastMonth, previous: monthBefore)
            .filter { $0.category != .rent && $0.previous > 0 && $0.change > 50 && $0.change / $0.previous > Decimal(string: "0.25")! }
            .sorted { $0.change > $1.change }
        if let jump = changes.first {
            tips.append(Suggestion(
                id: "jump-\(jump.category.rawValue)",
                symbol: "arrow.up.right",
                title: "\(jump.category.name) went up",
                detail: "You spent \(jump.change.currencyWhole) more on \(jump.category.name.lowercased()) in \(lastMonth.start.monthYear) than the month before. Worth a quick look.",
                tone: .warning
            ))
        }

        // Saving rate.
        let rate = SavingsCapacity(averages: averages).savingsRate
        if averages.income > 0 && averages.surplus >= 0 && rate < 0.10 {
            let target = (averages.income / 10).rounded(0)
            tips.append(Suggestion(
                id: "save-10",
                symbol: "banknote.fill",
                title: "Aim to save 10% of your income",
                detail: "That's about \(target.currencyWhole) a month. Moving it to savings on payday makes it automatic.",
                monthlySaving: nil
            ))
        } else if rate >= 0.20 {
            tips.append(Suggestion(
                id: "praise",
                symbol: "hand.thumbsup.fill",
                title: "You're saving well",
                detail: "You keep about \(Int((rate * 100).rounded()))% of your income. Keep it up – put the extra towards a goal so it doesn't get spent.",
                tone: .praise
            ))
        }

        let warnings = tips.filter { $0.tone == .warning }
        let savers = tips.filter { $0.tone == .tip }.sorted { ($0.monthlySaving ?? 0) > ($1.monthlySaving ?? 0) }
        let praise = tips.filter { $0.tone == .praise }
        return Array((warnings + savers + praise).prefix(6))
    }
}

// MARK: - Goals

enum GoalPlanner {
    struct Required {
        var perWeek: Decimal
        var perFortnight: Decimal
        var perMonth: Decimal
        var daysLeft: Int
    }

    /// How much to put aside regularly to reach `remaining` by `targetDate`.
    static func required(remaining: Decimal, from now: Date, to targetDate: Date, calendar: Calendar = AppLocale.calendar) -> Required? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: targetDate)).day ?? 0
        guard days > 0 else { return nil }
        guard remaining > 0 else { return Required(perWeek: 0, perFortnight: 0, perMonth: 0, daysLeft: days) }
        let perDay = remaining / Decimal(days)
        // Never ask for less than the whole remaining amount in a single period.
        return Required(
            perWeek: min(remaining, perDay * 7).roundedUpToDollar,
            perFortnight: min(remaining, perDay * 14).roundedUpToDollar,
            perMonth: min(remaining, perDay * FinanceEngine.daysPerMonth).roundedUpToDollar,
            daysLeft: days
        )
    }

    /// When the goal will be reached if `perWeek` is saved every week.
    static func finishDate(remaining: Decimal, perWeek: Decimal, from now: Date, calendar: Calendar = AppLocale.calendar) -> Date? {
        guard remaining > 0 else { return now }
        guard perWeek > 0 else { return nil }
        let weeks = (remaining / perWeek).roundedUpToDollar
        guard let weeksInt = Int(exactly: NSDecimalNumber(decimal: weeks)), weeksInt < 52 * 100 else { return nil }
        return calendar.date(byAdding: .day, value: weeksInt * 7, to: calendar.startOfDay(for: now))
    }
}

// MARK: - What-if

struct WhatIfScenario {
    var monthlyIncome: Decimal
    var monthlyExpenses: Decimal
    /// Change to monthly income, e.g. +200 for extra shifts.
    var incomeChange: Decimal = 0
    /// Change to monthly spending, e.g. -150 for cutting back.
    var expenseChange: Decimal = 0
    /// A one-off cost (positive) or windfall (negative) in the first month.
    var oneOffCost: Decimal = 0
    var startingSavings: Decimal = 0
    var months: Int = 12

    struct Point: Identifiable {
        var month: Int
        var current: Decimal
        var scenario: Decimal
        var id: Int { month }
    }

    var currentMonthly: Decimal { monthlyIncome - monthlyExpenses }
    var newMonthly: Decimal { (monthlyIncome + incomeChange) - max(0, monthlyExpenses + expenseChange) }
    var monthlyDifference: Decimal { newMonthly - currentMonthly }

    /// Savings over time with no changes and with the changes, month by month.
    var points: [Point] {
        var result = [Point(month: 0, current: startingSavings, scenario: startingSavings)]
        var current = startingSavings
        var scenario = startingSavings - oneOffCost
        for month in 1...max(1, months) {
            current += currentMonthly
            scenario += newMonthly
            result.append(Point(month: month, current: current, scenario: scenario))
        }
        return result
    }

    var currentTotal: Decimal { points.last?.current ?? startingSavings }
    var scenarioTotal: Decimal { points.last?.scenario ?? startingSavings }
}
