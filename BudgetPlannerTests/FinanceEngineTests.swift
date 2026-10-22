import XCTest
@testable import BudgetPlanner

final class FinanceEngineTests: XCTestCase {
    private let cal = AppLocale.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func expense(_ amount: Decimal, _ category: Category, _ when: Date) -> Transaction {
        Transaction(kind: .expense, amount: amount, category: category, date: when)
    }

    private func income(_ amount: Decimal, _ when: Date) -> Transaction {
        Transaction(kind: .income, amount: amount, category: .salary, date: when)
    }

    // MARK: Schedules

    func testMonthlyScheduleDoesNotDriftFromMonthEnd() {
        let anchor = date(2026, 1, 31, 0)
        XCTAssertEqual(cal.component(.day, from: Frequency.monthly.occurrence(1, from: anchor)!), 28)
        XCTAssertEqual(cal.component(.day, from: Frequency.monthly.occurrence(2, from: anchor)!), 31)
        let next = Frequency.monthly.nextOccurrence(after: date(2026, 2, 28, 0), anchor: anchor)!
        XCTAssertEqual(cal.dateComponents([.month, .day], from: next), DateComponents(month: 3, day: 31))
    }

    func testNextAndPreviousOccurrence() {
        let anchor = date(2026, 10, 1, 0) // a Thursday
        let next = Frequency.fortnightly.nextOccurrence(after: date(2026, 10, 20, 0), anchor: anchor)!
        XCTAssertEqual(next, date(2026, 10, 29, 0))
        let prev = Frequency.fortnightly.previousOccurrence(onOrBefore: date(2026, 10, 20, 0), anchor: anchor)!
        XCTAssertEqual(prev, date(2026, 10, 15, 0))
        XCTAssertNil(Frequency.fortnightly.previousOccurrence(onOrBefore: date(2026, 9, 1, 0), anchor: anchor))
        // Inclusive on the exact day.
        XCTAssertEqual(Frequency.weekly.nextOccurrence(after: anchor, anchor: anchor, inclusive: true), anchor)
        // Anchors in the future still work.
        XCTAssertEqual(Frequency.weekly.nextOccurrence(after: date(2026, 9, 1, 0), anchor: anchor), anchor)
    }

    // MARK: Balance

    func testAvailableBalance() {
        var data = AppData()
        data.settings.openingBalance = 1_000
        data.transactions = [
            income(500, date(2026, 10, 2)),
            expense(120.55, .groceries, date(2026, 10, 3)),
            expense(999, .shopping, date(2026, 10, 30)), // future-dated: not counted yet
        ]
        data.goals = [SavingsGoal(name: "Trip", target: 1_000, contributions: [
            GoalContribution(date: date(2026, 10, 4), amount: 200),
            GoalContribution(date: date(2026, 10, 5), amount: -50),
        ])]
        let engine = FinanceEngine(data: data, now: date(2026, 10, 22))
        XCTAssertEqual(engine.availableBalance, Decimal(string: "1229.45")!)
        XCTAssertEqual(engine.totalInGoals, 150)
    }

    // MARK: Budgets

    func testBudgetStatus() {
        var data = AppData()
        data.budgets = [
            Budget(category: .groceries, amount: 400, period: .monthly),
            Budget(category: nil, amount: 100, period: .weekly),
        ]
        data.transactions = [
            expense(150, .groceries, date(2026, 10, 2)),
            expense(50, .groceries, date(2026, 9, 28)), // last month
            expense(80, .eatingOut, date(2026, 10, 20)), // Tuesday this week
            expense(30, .groceries, date(2026, 10, 19)), // Monday this week
            expense(40, .groceries, date(2026, 10, 18)), // Sunday – last week
        ]
        let engine = FinanceEngine(data: data, now: date(2026, 10, 22))
        let monthly = engine.status(for: data.budgets[0])
        XCTAssertEqual(monthly.spent, 220)
        XCTAssertEqual(monthly.remaining, 180)
        XCTAssertEqual(monthly.daysLeft, 10) // 22nd to 31st inclusive
        XCTAssertEqual(monthly.perDayLeft, 18)
        XCTAssertEqual(monthly.state, .onTrack)

        let weekly = engine.status(for: data.budgets[1])
        XCTAssertEqual(weekly.spent, 110)
        XCTAssertEqual(weekly.state, .over)
        XCTAssertEqual(engine.primaryBudgetStatus?.budget.id, data.budgets[1].id)
    }

    // MARK: Bills and payday

    func testUpcomingBillsIncludeOverdueAndRepeats() {
        var data = AppData()
        data.bills = [
            Bill(name: "Rent", amount: 300, category: .rent, frequency: .weekly, anchorDate: date(2026, 10, 26, 0), nextDueDate: date(2026, 10, 26, 0)),
            Bill(name: "Phone", amount: 35, category: .phoneInternet, frequency: .monthly, anchorDate: date(2026, 10, 12, 0), nextDueDate: date(2026, 10, 12, 0)),
            Bill(name: "Old", amount: 10, category: .otherExpense, frequency: .once, anchorDate: date(2026, 10, 1, 0), nextDueDate: date(2026, 10, 1, 0), isActive: false),
        ]
        let engine = FinanceEngine(data: data, now: date(2026, 10, 22))
        let upcoming = engine.upcomingBills(days: 14)
        XCTAssertEqual(upcoming.map(\.bill.name), ["Phone", "Rent", "Rent"])
        XCTAssertTrue(upcoming[0].isOverdue)
        XCTAssertEqual(upcoming[2].date, date(2026, 11, 2, 0))
        XCTAssertEqual(engine.monthlyBillsCost, Decimal(1300) + 35)
    }

    func testPaydayPlan() {
        var data = AppData()
        data.settings.openingBalance = 800
        data.settings.pay = PaySchedule(amount: 1_200, frequency: .fortnightly, anchorDate: date(2026, 10, 15, 0))
        data.settings.savingsPerPay = 100
        data.bills = [
            Bill(name: "Rent", amount: 300, category: .rent, frequency: .weekly, anchorDate: date(2026, 10, 26, 0), nextDueDate: date(2026, 10, 26, 0)),
        ]
        let engine = FinanceEngine(data: data, now: date(2026, 10, 22))
        let plan = try! XCTUnwrap(engine.paydayPlan())
        XCTAssertEqual(plan.nextPayday, date(2026, 10, 29, 0))
        XCTAssertEqual(plan.lastPayday, date(2026, 10, 15, 0))
        XCTAssertEqual(plan.daysUntilPayday, 7)
        XCTAssertEqual(plan.billsBeforePaydayTotal, 300)
        XCTAssertEqual(plan.safeToSpend, 500)
        XCTAssertEqual(plan.safePerDay, Decimal(string: "71.43")!)
        // Next cycle 29 Oct – 12 Nov: rent on 2 Nov and 9 Nov.
        XCTAssertEqual(plan.nextCycleBillsTotal, 600)
        XCTAssertEqual(plan.nextCycleSpare, 500)
    }

    // MARK: Averages and savings

    func testMonthlyAveragesAndCapacity() {
        var data = AppData()
        let now = date(2026, 10, 22)
        // 60 days of history: $3,000 income, $2,000 spending.
        data.transactions = [
            income(3_000, cal.date(byAdding: .day, value: -59, to: now)!),
            expense(2_000, .rent, cal.date(byAdding: .day, value: -30, to: now)!),
        ]
        let engine = FinanceEngine(data: data, now: now)
        let avg = engine.monthlyAverages()
        XCTAssertEqual(avg.daysOfHistory, 60)
        XCTAssertEqual(avg.income, Decimal(string: "1521.88")!)
        XCTAssertEqual(avg.expenses, Decimal(string: "1014.58")!)
        // Surplus 507.30 × 0.8 = 405.84 → $400 realistic.
        XCTAssertEqual(engine.savingsCapacity.realisticMonthly, 400)
    }

    func testGoalPlanner() {
        let now = date(2026, 10, 22)
        let target = cal.date(byAdding: .day, value: 70, to: now)!
        let req = try! XCTUnwrap(GoalPlanner.required(remaining: 1_000, from: now, to: target))
        XCTAssertEqual(req.perWeek, 100)
        XCTAssertEqual(req.perFortnight, 200)
        XCTAssertEqual(req.perMonth, 435) // 1000/70 × 30.4375 = 434.82 → rounded up
        XCTAssertNil(GoalPlanner.required(remaining: 1_000, from: now, to: now))
        let finish = GoalPlanner.finishDate(remaining: 250, perWeek: 100, from: now)
        XCTAssertEqual(finish, cal.date(byAdding: .day, value: 21, to: cal.startOfDay(for: now)))
        XCTAssertNil(GoalPlanner.finishDate(remaining: 250, perWeek: 0, from: now))
    }

    func testWhatIf() {
        let scenario = WhatIfScenario(monthlyIncome: 2_400, monthlyExpenses: 2_100, incomeChange: 200, expenseChange: -100, oneOffCost: 300, startingSavings: 1_000, months: 6)
        XCTAssertEqual(scenario.currentMonthly, 300)
        XCTAssertEqual(scenario.newMonthly, 600)
        XCTAssertEqual(scenario.currentTotal, 2_800)
        XCTAssertEqual(scenario.scenarioTotal, 4_300)
        XCTAssertEqual(scenario.points.count, 7)
    }

    func testReportsAndComparison() {
        var data = AppData()
        data.transactions = [
            expense(100, .groceries, date(2026, 9, 5)),
            expense(160, .groceries, date(2026, 10, 5)),
            expense(40, .eatingOut, date(2026, 10, 6)),
            income(900, date(2026, 10, 1)),
        ]
        let engine = FinanceEngine(data: data, now: date(2026, 10, 22))
        let months = engine.periodSummaries(.monthly, count: 3)
        XCTAssertEqual(months.map(\.totals.expenses), [0, 100, 200])
        XCTAssertEqual(months.last?.totals.net, 700)
        let change = engine.categoryComparison(current: engine.thisMonth, previous: engine.shifted(engine.thisMonth, by: -1, period: .monthly))
        XCTAssertEqual(change.first?.category, .groceries)
        XCTAssertEqual(change.first?.change, 60)
        let byCategory = engine.spendingByCategory(in: engine.thisMonth)
        XCTAssertEqual(byCategory.map(\.share), [0.8, 0.2])
    }

    // MARK: CSV

    func testCSVRoundTrip() throws {
        let txs = [
            Transaction(kind: .expense, amount: 12.5, category: .eatingOut, date: date(2026, 10, 3), note: "Lunch, with \"Sam\""),
            Transaction(kind: .income, amount: 1_150, category: .partTime, date: date(2026, 10, 2), note: "=Pay"),
        ]
        let csv = TransactionCSV.export(txs)
        XCTAssertTrue(csv.contains("\"Lunch, with \"\"Sam\"\"\""))
        XCTAssertTrue(csv.contains("'=Pay"))
        let parsed = try TransactionCSV.parse(csv)
        XCTAssertEqual(parsed.skippedRows, [])
        XCTAssertEqual(parsed.transactions.count, 2)
        let lunch = try XCTUnwrap(parsed.transactions.first { $0.kind == .expense })
        XCTAssertEqual(lunch.amount, 12.5)
        XCTAssertEqual(lunch.category, .eatingOut)
        XCTAssertEqual(lunch.note, "Lunch, with \"Sam\"")
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: lunch.date), DateComponents(year: 2026, month: 10, day: 3))
    }

    func testCSVImportWithoutTypeColumn() throws {
        let csv = "Date,Description,Amount\n03/10/2026,Coles,-$54.20\n04/10/2026,Pay,\"1,200.00\"\nbad,row,1\n"
        let result = try TransactionCSV.parse(csv)
        XCTAssertEqual(result.transactions.map(\.kind), [.expense, .income])
        XCTAssertEqual(result.transactions[1].amount, 1_200)
        XCTAssertEqual(result.skippedRows, [4])
        XCTAssertThrowsError(try TransactionCSV.parse("Name,Thing\nA,B"))
    }

    // MARK: Sample data

    func testSampleDataIsFlaggedAndRemovable() {
        let now = date(2026, 10, 22, 15)
        var data = SampleData.make(now: now)
        XCTAssertTrue(data.transactions.allSatisfy(\.isSample))
        XCTAssertTrue(data.bills.allSatisfy(\.isSample))
        XCTAssertTrue(data.transactions.allSatisfy { $0.date <= now })
        XCTAssertTrue(data.bills.allSatisfy { $0.nextDueDate >= self.cal.startOfDay(for: now) })

        let engine = FinanceEngine(data: data, now: now)
        XCTAssertGreaterThan(engine.availableBalance, 500)
        XCTAssertLessThan(engine.availableBalance, 4_000)
        XCTAssertNotNil(engine.paydayPlan())
        XCTAssertFalse(engine.suggestions().isEmpty)

        data.transactions.append(expense(10, .groceries, now))
        data.removeSampleData()
        XCTAssertEqual(data.transactions.count, 1)
        XCTAssertFalse(data.hasSampleData)
        XCTAssertEqual(data.settings.openingBalance, 0)
        XCTAssertNil(data.settings.pay)
    }

    func testBackupRoundTrip() throws {
        let data = SampleData.make(now: date(2026, 10, 22))
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AppData.self, from: encoded)
        XCTAssertEqual(decoded, data)
    }
}
