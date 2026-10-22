import Foundation

/// Realistic demo data for a uni student working part-time in Sydney.
/// Every record is flagged `isSample` so it can be removed in one tap
/// without touching anything the user has entered.
enum SampleData {
    /// Small deterministic random generator so the demo looks the same every time.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Exact decimal from text – float literals are not exact for money.
    private static func dec(_ text: String) -> Decimal { Decimal(string: text)! }

    static func make(now: Date = Date(), calendar: Calendar = AppLocale.calendar) -> AppData {
        var rng = SeededGenerator(state: 2026)
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ date: Date, hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: date)! }
        func money(_ low: Double, _ high: Double) -> Decimal {
            let cents = Int((Double.random(in: low...high, using: &rng) * 100).rounded())
            return Decimal(cents) / 100
        }

        var transactions: [Transaction] = []
        func add(_ kind: TransactionKind, _ amount: Decimal, _ category: Category, _ date: Date, _ note: String) {
            guard date <= now else { return }
            transactions.append(Transaction(kind: kind, amount: amount, category: category, date: date, note: note, isSample: true))
        }

        let historyDays = 120
        let start = day(-historyDays)

        // Paydays: fortnightly on Thursdays. Find the most recent Thursday.
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday … 5 = Thursday
        let lastThursday = day(-((weekday - 5 + 7) % 7))
        let payAnchor = lastThursday
        var payday = payAnchor
        while payday > start { payday = calendar.date(byAdding: .day, value: -14, to: payday)! }

        // Rent is paid weekly on Mondays.
        let lastMonday = day(-((weekday - 2 + 7) % 7))

        // Bills (with due dates that line up with the history below).
        let rentNext = calendar.date(byAdding: .day, value: 7, to: lastMonday)!
        let phoneDay = 12, internetDay = 20, netflixDay = 3, spotifyDay = 15
        func nextMonthly(_ dayOfMonth: Int) -> Date {
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = dayOfMonth
            var date = calendar.date(from: comps)!
            if date < today { date = calendar.date(byAdding: .month, value: 1, to: date)! }
            return date
        }
        let gymNext = calendar.date(byAdding: .day, value: 1, to: payAnchor).map { $0 < today ? calendar.date(byAdding: .day, value: 14, to: $0)! : $0 }!
        let electricityNext = day(9)
        let carInsuranceNext = day(23)

        var bills: [Bill] = [
            Bill(name: "Rent", amount: 320, category: .rent, frequency: .weekly, anchorDate: rentNext, nextDueDate: rentNext, remindDaysBefore: 1, isSample: true),
            Bill(name: "Optus mobile", amount: 35, category: .phoneInternet, frequency: .monthly, anchorDate: nextMonthly(phoneDay), nextDueDate: nextMonthly(phoneDay), remindDaysBefore: 1, isSample: true),
            Bill(name: "NBN (my share)", amount: dec("27.50"), category: .phoneInternet, frequency: .monthly, anchorDate: nextMonthly(internetDay), nextDueDate: nextMonthly(internetDay), remindDaysBefore: 1, isSample: true),
            Bill(name: "Netflix", amount: dec("18.99"), category: .subscriptions, frequency: .monthly, anchorDate: nextMonthly(netflixDay), nextDueDate: nextMonthly(netflixDay), remindDaysBefore: nil, isSample: true),
            Bill(name: "Spotify", amount: dec("13.99"), category: .subscriptions, frequency: .monthly, anchorDate: nextMonthly(spotifyDay), nextDueDate: nextMonthly(spotifyDay), remindDaysBefore: nil, isSample: true),
            Bill(name: "Gym membership", amount: dec("24.90"), category: .subscriptions, frequency: .fortnightly, anchorDate: gymNext, nextDueDate: gymNext, remindDaysBefore: nil, isSample: true),
            Bill(name: "Electricity (share)", amount: dec("186.40"), category: .utilities, frequency: .quarterly, anchorDate: electricityNext, nextDueDate: electricityNext, remindDaysBefore: 3, isSample: true),
            Bill(name: "Car insurance", amount: dec("74.15"), category: .insurance, frequency: .monthly, anchorDate: carInsuranceNext, nextDueDate: carInsuranceNext, remindDaysBefore: 2, isSample: true),
        ]
        bills[0].lastPaidDate = lastMonday

        // Income: fortnightly part-time pay plus the odd extra.
        while payday <= today {
            add(.income, money(1_290, 1_420), .partTime, at(payday, hour: 9), "Woolworths – shifts")
            payday = calendar.date(byAdding: .day, value: 14, to: payday)!
        }
        add(.income, 120, .freelance, at(day(-38), hour: 18), "Maths tutoring")
        add(.income, 150, .freelance, at(day(-11), hour: 18), "Maths tutoring")
        add(.income, dec("412.60"), .taxRefund, at(day(-96), hour: 11), "ATO tax refund")
        add(.income, 50, .giftIncome, at(day(-64), hour: 15), "Birthday money from Nan")

        // Rent every Monday.
        var monday = lastMonday
        while monday > start {
            add(.expense, 320, .rent, at(monday, hour: 8), "Rent")
            monday = calendar.date(byAdding: .day, value: -7, to: monday)!
        }

        // Monthly bills that were already paid.
        for monthsBack in 0...4 {
            func paid(_ dayOfMonth: Int, _ amount: Decimal, _ category: Category, _ note: String) {
                var comps = calendar.dateComponents([.year, .month], from: today)
                comps.day = dayOfMonth
                let thisMonth = calendar.date(from: comps)!
                let date = calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth)!
                if date >= start && date < today { add(.expense, amount, category, at(date, hour: 7), note) }
            }
            paid(phoneDay, 35, .phoneInternet, "Optus mobile")
            paid(internetDay, dec("27.50"), .phoneInternet, "NBN (my share)")
            paid(netflixDay, dec("18.99"), .subscriptions, "Netflix")
            paid(spotifyDay, dec("13.99"), .subscriptions, "Spotify")
            paid(carInsuranceNext.dayOfMonth(calendar), dec("74.15"), .insurance, "Car insurance")
        }
        var gym = calendar.date(byAdding: .day, value: -14, to: gymNext)!
        while gym > start {
            if gym < today { add(.expense, dec("24.90"), .subscriptions, at(gym, hour: 6), "Gym membership") }
            gym = calendar.date(byAdding: .day, value: -14, to: gym)!
        }
        add(.expense, dec("179.85"), .utilities, at(calendar.date(byAdding: .month, value: -3, to: electricityNext)!, hour: 10), "Electricity (share)")

        // Day-to-day spending.
        let groceryStores = ["Woolworths", "Coles", "Aldi"]
        let cafes = ["Coffee", "Guzman y Gomez", "Sushi train", "Thai takeaway", "Boost Juice", "Uber Eats", "Pub dinner"]
        let shops = ["Kmart", "Uniqlo", "Amazon AU", "JB Hi-Fi", "Big W", "Rebel Sport"]
        let fun = ["Movie tickets", "Concert ticket", "Bowling", "Netball fees", "Mini golf"]

        for offset in stride(from: -historyDays, through: 0, by: 1) {
            let date = day(offset)
            let dow = calendar.component(.weekday, from: date)
            // Groceries twice a week.
            if dow == 1 { add(.expense, money(55, 95), .groceries, at(date, hour: 11), groceryStores.randomElement(using: &rng)!) }
            if dow == 4 { add(.expense, money(18, 40), .groceries, at(date, hour: 18), groceryStores.randomElement(using: &rng)!) }
            // Opal top-up / fares on uni days.
            if (2...5).contains(dow) { add(.expense, money(4.20, 9.60), .transport, at(date, hour: 8), "Opal fares") }
            if dow == 6 && Int.random(in: 0..<3, using: &rng) == 0 { add(.expense, money(48, 72), .transport, at(date, hour: 17), "Fuel – Ampol") }
            // Eating out a few times a week.
            if Int.random(in: 0..<10, using: &rng) < 3 { add(.expense, money(5, 28), .eatingOut, at(date, hour: 13), cafes.randomElement(using: &rng)!) }
            // Occasional shopping and fun.
            if Int.random(in: 0..<12, using: &rng) == 0 { add(.expense, money(15, 85), .shopping, at(date, hour: 15), shops.randomElement(using: &rng)!) }
            if Int.random(in: 0..<14, using: &rng) == 0 { add(.expense, money(14, 60), .entertainment, at(date, hour: 19), fun.randomElement(using: &rng)!) }
        }

        add(.expense, dec("129.95"), .education, at(day(-102), hour: 12), "Textbooks – Co-op")
        add(.expense, 45, .education, at(day(-40), hour: 12), "Lab coat & safety glasses")
        add(.expense, dec("32.50"), .personalCare, at(day(-75), hour: 16), "Haircut")
        add(.expense, 34, .personalCare, at(day(-21), hour: 16), "Haircut")
        add(.expense, dec("18.40"), .health, at(day(-58), hour: 10), "Chemist Warehouse")
        add(.expense, 42, .gifts, at(day(-30), hour: 14), "Mum's birthday present")
        add(.expense, 189, .travel, at(day(-88), hour: 20), "Jetstar to Melbourne")
        add(.expense, dec("64.50"), .health, at(day(-6), hour: 10), "GP gap fee")

        // Budgets.
        let budgets = [
            Budget(category: nil, amount: 2_700, period: .monthly, isSample: true),
            Budget(category: .groceries, amount: 400, period: .monthly, isSample: true),
            Budget(category: .eatingOut, amount: 160, period: .monthly, isSample: true),
            Budget(category: .transport, amount: 60, period: .weekly, isSample: true),
            Budget(category: .shopping, amount: 120, period: .monthly, isSample: true),
        ]

        // Savings goals with regular payday contributions.
        func contributions(_ amount: Decimal, every days: Int, count: Int, from first: Date) -> [GoalContribution] {
            (0..<count).compactMap { i in
                let date = calendar.date(byAdding: .day, value: i * days, to: first)!
                return date <= now ? GoalContribution(date: at(date, hour: 10), amount: amount, note: "Payday transfer") : nil
            }
        }
        let firstPay = calendar.date(byAdding: .day, value: -112, to: payAnchor)!
        let goals = [
            SavingsGoal(name: "Emergency fund", symbol: "shield.lefthalf.filled", target: 2_000, targetDate: nil,
                        contributions: [GoalContribution(date: at(day(-110), hour: 10), amount: 400, note: "Starting amount")]
                            + contributions(60, every: 14, count: 9, from: firstPay),
                        createdAt: day(-110), isSample: true),
            SavingsGoal(name: "Japan trip", symbol: "airplane", target: 3_500,
                        targetDate: calendar.date(byAdding: .month, value: 9, to: today),
                        contributions: contributions(80, every: 14, count: 9, from: firstPay),
                        createdAt: day(-110), isSample: true),
            SavingsGoal(name: "New laptop", symbol: "laptopcomputer", target: 1_600,
                        targetDate: calendar.date(byAdding: .month, value: 5, to: today),
                        contributions: [GoalContribution(date: at(day(-96), hour: 12), amount: 300, note: "Part of tax refund")],
                        createdAt: day(-96), isSample: true),
        ]

        var settings = AppSettings()
        settings.openingBalance = 400
        settings.openingBalanceIsSample = true
        settings.pay = PaySchedule(amount: 1_350, frequency: .fortnightly, anchorDate: payAnchor, category: .partTime)
        settings.payIsSample = true
        settings.savingsPerPay = 140

        return AppData(
            transactions: transactions.sorted { $0.date > $1.date },
            bills: bills,
            budgets: budgets,
            goals: goals,
            settings: settings
        )
    }
}

private extension Date {
    func dayOfMonth(_ calendar: Calendar) -> Int { calendar.component(.day, from: self) }
}
