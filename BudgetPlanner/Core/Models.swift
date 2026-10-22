import Foundation

// MARK: - Transactions

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "Expense" : "Income" }
}

/// Categories for money in and money out, based on common Australian living costs.
enum Category: String, Codable, CaseIterable, Identifiable {
    // Expenses
    case rent
    case groceries
    case transport
    case utilities
    case phoneInternet
    case insurance
    case health
    case education
    case eatingOut
    case shopping
    case entertainment
    case subscriptions
    case personalCare
    case gifts
    case travel
    case otherExpense

    // Income
    case salary
    case partTime
    case centrelink
    case freelance
    case taxRefund
    case giftIncome
    case otherIncome

    var id: String { rawValue }

    var kind: TransactionKind {
        switch self {
        case .salary, .partTime, .centrelink, .freelance, .taxRefund, .giftIncome, .otherIncome:
            return .income
        default:
            return .expense
        }
    }

    var name: String {
        switch self {
        case .rent: return "Rent"
        case .groceries: return "Groceries"
        case .transport: return "Transport"
        case .utilities: return "Bills & Utilities"
        case .phoneInternet: return "Phone & Internet"
        case .insurance: return "Insurance"
        case .health: return "Health"
        case .education: return "Education"
        case .eatingOut: return "Eating Out"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .subscriptions: return "Subscriptions"
        case .personalCare: return "Personal Care"
        case .gifts: return "Gifts & Donations"
        case .travel: return "Travel"
        case .otherExpense: return "Other"
        case .salary: return "Salary"
        case .partTime: return "Part-time Work"
        case .centrelink: return "Centrelink"
        case .freelance: return "Side Work"
        case .taxRefund: return "Tax Refund"
        case .giftIncome: return "Gift"
        case .otherIncome: return "Other Income"
        }
    }

    /// Everyday Australian examples, shown as a hint in forms.
    var examples: String {
        switch self {
        case .rent: return "Rent, board, bond, strata"
        case .groceries: return "Woolworths, Coles, Aldi, IGA"
        case .transport: return "Opal, Myki, go card, fuel, rego, tolls"
        case .utilities: return "Electricity, gas, water"
        case .phoneInternet: return "Mobile plan, NBN"
        case .insurance: return "Car, contents, health cover"
        case .health: return "GP gap, pharmacy, dentist"
        case .education: return "Uni fees, textbooks, courses"
        case .eatingOut: return "Takeaway, cafés, coffee"
        case .shopping: return "Clothes, Kmart, online"
        case .entertainment: return "Movies, concerts, sport"
        case .subscriptions: return "Netflix, Spotify, gym"
        case .personalCare: return "Haircut, toiletries"
        case .gifts: return "Presents, charity"
        case .travel: return "Flights, accommodation"
        case .otherExpense: return "Anything else"
        case .salary: return "Full-time pay"
        case .partTime: return "Casual or part-time shifts"
        case .centrelink: return "Youth Allowance, payments"
        case .freelance: return "Tutoring, gigs, selling items"
        case .taxRefund: return "ATO refund"
        case .giftIncome: return "Money from family or friends"
        case .otherIncome: return "Interest, refunds, other"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .rent: return "house.fill"
        case .groceries: return "cart.fill"
        case .transport: return "tram.fill"
        case .utilities: return "bolt.fill"
        case .phoneInternet: return "wifi"
        case .insurance: return "shield.fill"
        case .health: return "cross.case.fill"
        case .education: return "graduationcap.fill"
        case .eatingOut: return "fork.knife"
        case .shopping: return "bag.fill"
        case .entertainment: return "ticket.fill"
        case .subscriptions: return "repeat"
        case .personalCare: return "scissors"
        case .gifts: return "gift.fill"
        case .travel: return "airplane"
        case .otherExpense: return "ellipsis.circle.fill"
        case .salary: return "briefcase.fill"
        case .partTime: return "clock.fill"
        case .centrelink: return "building.columns.fill"
        case .freelance: return "laptopcomputer"
        case .taxRefund: return "doc.text.fill"
        case .giftIncome: return "heart.fill"
        case .otherIncome: return "plus.circle.fill"
        }
    }

    static func all(for kind: TransactionKind) -> [Category] {
        allCases.filter { $0.kind == kind }
    }

    static var expenseCategories: [Category] { all(for: .expense) }
    static var incomeCategories: [Category] { all(for: .income) }

    /// Matches a category from free text (used by CSV import).
    static func match(_ text: String, kind: TransactionKind) -> Category {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = allCases.first(where: { $0.kind == kind && ($0.name.lowercased() == needle || $0.rawValue.lowercased() == needle) }) {
            return exact
        }
        if !needle.isEmpty, let loose = allCases.first(where: { $0.kind == kind && $0.name.lowercased().contains(needle) }) {
            return loose
        }
        return kind == .income ? .otherIncome : .otherExpense
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Category(rawValue: raw) ?? .otherExpense
    }
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: TransactionKind
    /// Always positive. Use `signedAmount` for balance maths.
    var amount: Decimal
    var category: Category
    var date: Date
    var note: String = ""
    var isSample: Bool = false
    /// Set when the transaction was created by marking a bill as paid.
    var billID: UUID? = nil

    var signedAmount: Decimal { kind == .income ? amount : -amount }
    var title: String { note.isEmpty ? category.name : note }
}

// MARK: - Repeating schedules

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case once
    case weekly
    case fortnightly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: return "One-off"
        case .weekly: return "Weekly"
        case .fortnightly: return "Fortnightly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    /// How many times this happens in a year (0 for one-off).
    var timesPerYear: Decimal {
        switch self {
        case .once: return 0
        case .weekly: return 52
        case .fortnightly: return 26
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }

    static var payFrequencies: [Frequency] { [.weekly, .fortnightly, .monthly] }

    /// The n-th occurrence counted from `anchor` (n = 0 is the anchor itself).
    /// Months are added from the anchor each time so that, for example, a bill
    /// due on the 31st stays on the last day of shorter months without drifting.
    func occurrence(_ n: Int, from anchor: Date, calendar: Calendar = AppLocale.calendar) -> Date? {
        switch self {
        case .once: return n == 0 ? anchor : nil
        case .weekly: return calendar.date(byAdding: .day, value: 7 * n, to: anchor)
        case .fortnightly: return calendar.date(byAdding: .day, value: 14 * n, to: anchor)
        case .monthly: return calendar.date(byAdding: .month, value: n, to: anchor)
        case .quarterly: return calendar.date(byAdding: .month, value: 3 * n, to: anchor)
        case .yearly: return calendar.date(byAdding: .year, value: n, to: anchor)
        }
    }

    /// Index of the first occurrence strictly after `date` (or on/after when `inclusive`).
    private func firstIndex(after date: Date, anchor: Date, inclusive: Bool, calendar: Calendar) -> Int? {
        // Jump close to the target first so long-running schedules stay fast.
        let days = calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
        var n: Int
        switch self {
        case .once: n = 0
        case .weekly: n = max(0, days / 7 - 1)
        case .fortnightly: n = max(0, days / 14 - 1)
        case .monthly: n = max(0, days / 31 - 1)
        case .quarterly: n = max(0, days / 92 - 1)
        case .yearly: n = max(0, days / 366 - 1)
        }
        for _ in 0..<500 {
            guard let candidate = occurrence(n, from: anchor, calendar: calendar) else { return nil }
            if inclusive ? candidate >= date : candidate > date { return n }
            n += 1
        }
        return nil
    }

    /// First occurrence strictly after `date` (or on/after when `inclusive`).
    func nextOccurrence(after date: Date, anchor: Date, inclusive: Bool = false, calendar: Calendar = AppLocale.calendar) -> Date? {
        guard let n = firstIndex(after: date, anchor: anchor, inclusive: inclusive, calendar: calendar) else { return nil }
        return occurrence(n, from: anchor, calendar: calendar)
    }

    /// The occurrence on or before `date`, if any.
    func previousOccurrence(onOrBefore date: Date, anchor: Date, calendar: Calendar = AppLocale.calendar) -> Date? {
        guard anchor <= date else { return nil }
        if self == .once { return anchor }
        guard let n = firstIndex(after: date, anchor: anchor, inclusive: false, calendar: calendar), n > 0 else { return nil }
        return occurrence(n - 1, from: anchor, calendar: calendar)
    }
}

// MARK: - Bills

struct Bill: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Decimal
    var category: Category
    var frequency: Frequency
    /// The first due date. Repeats are counted from here.
    var anchorDate: Date
    /// The next unpaid due date.
    var nextDueDate: Date
    /// Days before the due date to send a reminder; nil means no reminder.
    var remindDaysBefore: Int? = 1
    var isActive: Bool = true
    var lastPaidDate: Date? = nil
    var isSample: Bool = false

    /// Roughly what this bill costs per month, for planning.
    var monthlyCost: Decimal {
        frequency == .once ? 0 : (amount * frequency.timesPerYear / 12).rounded()
    }

    /// Due dates of this bill that fall in `interval`, starting from the next unpaid one.
    func dueDates(in interval: DateInterval, calendar: Calendar = AppLocale.calendar) -> [Date] {
        guard isActive else { return [] }
        var dates: [Date] = []
        var current: Date? = nextDueDate
        // Overdue bills are shown once, on their original due date.
        while let date = current, date < interval.end {
            if date >= interval.start { dates.append(date) }
            if frequency == .once || dates.count > 400 { break }
            current = frequency.nextOccurrence(after: date, anchor: anchorDate, calendar: calendar)
        }
        return dates
    }
}

// MARK: - Budgets

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }
    var title: String { self == .weekly ? "Weekly" : "Monthly" }
    var noun: String { self == .weekly ? "week" : "month" }
    var calendarComponent: Calendar.Component { self == .weekly ? .weekOfYear : .month }
}

struct Budget: Identifiable, Codable, Hashable {
    var id = UUID()
    /// nil means "all spending".
    var category: Category?
    var amount: Decimal
    var period: BudgetPeriod
    var isSample: Bool = false

    var name: String { category?.name ?? "All spending" }
}

// MARK: - Savings goals

struct GoalContribution: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    /// Positive = money put aside, negative = money taken out.
    var amount: Decimal
    var note: String = ""
}

struct SavingsGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String = "star.fill"
    var target: Decimal
    var targetDate: Date? = nil
    var contributions: [GoalContribution] = []
    var createdAt: Date = Date()
    var isSample: Bool = false

    var saved: Decimal { contributions.reduce(0) { $0 + $1.amount } }
    var remaining: Decimal { max(0, target - saved) }
    var isComplete: Bool { target > 0 && saved >= target }
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, (saved / target).doubleValue))
    }

    static let symbolChoices = [
        "star.fill", "shield.lefthalf.filled", "airplane", "car.fill", "laptopcomputer",
        "house.fill", "graduationcap.fill", "gift.fill", "heart.fill", "iphone",
        "bicycle", "pawprint.fill", "music.note", "camera.fill", "sparkles",
    ]
}

// MARK: - Settings

struct PaySchedule: Codable, Hashable {
    /// Usual take-home pay (after tax).
    var amount: Decimal
    var frequency: Frequency
    /// Any known payday. Future paydays are counted from it.
    var anchorDate: Date
    var category: Category = .salary
}

struct AppSettings: Codable, Hashable {
    /// Money you had when you started using the app.
    var openingBalance: Decimal = 0
    var openingBalanceIsSample: Bool = false
    var pay: PaySchedule? = nil
    var payIsSample: Bool = false
    /// How much you plan to move to savings each payday.
    var savingsPerPay: Decimal = 0
    var appLockEnabled: Bool = false
    var billRemindersEnabled: Bool = true
    var hideWidgetAmounts: Bool = false
    var hasOnboarded: Bool = false
}

/// Everything the app stores. Saved as a single encrypted-at-rest file.
struct AppData: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = AppData.currentVersion
    var transactions: [Transaction] = []
    var bills: [Bill] = []
    var budgets: [Budget] = []
    var goals: [SavingsGoal] = []
    var settings = AppSettings()

    var hasSampleData: Bool {
        transactions.contains(where: \.isSample)
            || bills.contains(where: \.isSample)
            || budgets.contains(where: \.isSample)
            || goals.contains(where: \.isSample)
            || settings.openingBalanceIsSample
            || settings.payIsSample
    }

    var hasRealData: Bool {
        transactions.contains { !$0.isSample }
            || bills.contains { !$0.isSample }
            || budgets.contains { !$0.isSample }
            || goals.contains { !$0.isSample }
    }

    /// Removes every sample record and keeps everything the user entered.
    mutating func removeSampleData() {
        transactions.removeAll(where: \.isSample)
        bills.removeAll(where: \.isSample)
        budgets.removeAll(where: \.isSample)
        goals.removeAll(where: \.isSample)
        if settings.openingBalanceIsSample {
            settings.openingBalance = 0
            settings.openingBalanceIsSample = false
        }
        if settings.payIsSample {
            settings.pay = nil
            settings.savingsPerPay = 0
            settings.payIsSample = false
        }
    }
}
