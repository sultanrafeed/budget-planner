import Foundation
import Observation
import WidgetKit

/// Owns all app data, saves it to disk and keeps reminders and the widget in sync.
@MainActor
@Observable
final class DataStore {
    private(set) var data: AppData
    /// A user-facing error message, shown as an alert.
    var errorMessage: String?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let reminders = BillReminderScheduler()

    var engine: FinanceEngine { FinanceEngine(data: data, now: Date()) }
    var settings: AppSettings { data.settings }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BudgetPlanner", isDirectory: true).appendingPathComponent("data.json")
    }

    /// - Parameter fileURL: where to save; `nil` keeps everything in memory (previews).
    init(fileURL: URL? = DataStore.defaultFileURL, initialData: AppData? = nil) {
        self.fileURL = fileURL
        if let initialData {
            data = initialData
        } else if let fileURL {
            switch Self.load(from: fileURL) {
            case .success(let loaded):
                data = loaded
            case .failure(let error):
                data = AppData()
                errorMessage = error.localizedDescription
            }
        } else {
            data = AppData()
        }
    }

    static func preview() -> DataStore {
        var sample = SampleData.make()
        sample.settings.hasOnboarded = true
        return DataStore(fileURL: nil, initialData: sample)
    }

    // MARK: - Loading and saving

    private enum LoadError: LocalizedError {
        case unreadable(keptCopyAt: String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "Your saved data couldn't be read, so the app started fresh. A copy was kept as \"\(name)\". You can restore a backup from Settings."
            }
        }
    }

    private static func load(from url: URL) -> Result<AppData, Error> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(AppData()) }
        do {
            let raw = try Data(contentsOf: url)
            return .success(try JSONDecoder().decode(AppData.self, from: raw))
        } catch {
            // Keep the unreadable file so nothing is lost.
            let name = "data-unreadable-\(Int(Date().timeIntervalSince1970)).json"
            let copy = url.deletingLastPathComponent().appendingPathComponent(name)
            try? FileManager.default.moveItem(at: url, to: copy)
            return .failure(LoadError.unreadable(keptCopyAt: name))
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            // `.completeFileProtection` keeps the file encrypted while the iPhone is locked.
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
        }
    }

    /// Applies a change, saves, and refreshes everything that depends on the data.
    private func commit(rescheduleReminders: Bool = false, _ change: (inout AppData) -> Void) {
        change(&data)
        persist()
        refreshWidget()
        if rescheduleReminders { refreshReminders() }
    }

    /// Call on launch and when returning to the app.
    func appBecameActive() {
        refreshWidget()
        refreshReminders()
    }

    // MARK: - Transactions

    func save(_ transaction: Transaction) {
        commit { data in
            if let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) {
                data.transactions[index] = transaction
            } else {
                data.transactions.append(transaction)
            }
        }
    }

    func deleteTransactions(_ ids: Set<UUID>) {
        commit { $0.transactions.removeAll { ids.contains($0.id) } }
    }

    /// The category used most often in recent entries, for quick adding.
    func suggestedCategory(for kind: TransactionKind) -> Category {
        let recent = data.transactions
            .filter { $0.kind == kind && !$0.isSample }
            .sorted { $0.date > $1.date }
            .prefix(30)
        let counts = Dictionary(grouping: recent, by: \.category).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? (kind == .expense ? .groceries : .salary)
    }

    // MARK: - Bills

    func save(_ bill: Bill) {
        commit(rescheduleReminders: true) { data in
            if let index = data.bills.firstIndex(where: { $0.id == bill.id }) {
                data.bills[index] = bill
            } else {
                data.bills.append(bill)
            }
        }
    }

    func deleteBill(_ id: UUID) {
        commit(rescheduleReminders: true) { $0.bills.removeAll { $0.id == id } }
    }

    /// Records the bill as an expense and moves it to its next due date.
    func markPaid(_ billID: UUID, amount: Decimal? = nil, on date: Date = Date()) {
        commit(rescheduleReminders: true) { data in
            guard let index = data.bills.firstIndex(where: { $0.id == billID }) else { return }
            let bill = data.bills[index]
            data.transactions.append(Transaction(
                kind: .expense,
                amount: amount ?? bill.amount,
                category: bill.category,
                date: date,
                note: bill.name,
                isSample: bill.isSample,
                billID: bill.id
            ))
            data.bills[index].lastPaidDate = date
            Self.advance(&data.bills[index])
        }
    }

    /// Moves a bill to its next due date without recording a payment.
    func skip(_ billID: UUID) {
        commit(rescheduleReminders: true) { data in
            guard let index = data.bills.firstIndex(where: { $0.id == billID }) else { return }
            Self.advance(&data.bills[index])
        }
    }

    private static func advance(_ bill: inout Bill) {
        if let next = bill.frequency.nextOccurrence(after: bill.nextDueDate, anchor: bill.anchorDate) {
            bill.nextDueDate = next
        } else {
            bill.isActive = false
        }
    }

    // MARK: - Budgets

    func save(_ budget: Budget) {
        commit { data in
            if let index = data.budgets.firstIndex(where: { $0.id == budget.id }) {
                data.budgets[index] = budget
            } else {
                data.budgets.append(budget)
            }
        }
    }

    func deleteBudget(_ id: UUID) {
        commit { $0.budgets.removeAll { $0.id == id } }
    }

    // MARK: - Goals

    func save(_ goal: SavingsGoal) {
        commit { data in
            if let index = data.goals.firstIndex(where: { $0.id == goal.id }) {
                data.goals[index] = goal
            } else {
                data.goals.append(goal)
            }
        }
    }

    func deleteGoal(_ id: UUID) {
        commit { $0.goals.removeAll { $0.id == id } }
    }

    func addContribution(_ contribution: GoalContribution, to goalID: UUID) {
        commit { data in
            guard let index = data.goals.firstIndex(where: { $0.id == goalID }) else { return }
            data.goals[index].contributions.append(contribution)
        }
    }

    func deleteContribution(_ contributionID: UUID, from goalID: UUID) {
        commit { data in
            guard let index = data.goals.firstIndex(where: { $0.id == goalID }) else { return }
            data.goals[index].contributions.removeAll { $0.id == contributionID }
        }
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        commit(rescheduleReminders: true) { change(&$0.settings) }
    }

    /// Records the usual pay as income today.
    func recordPay() {
        guard let pay = data.settings.pay else { return }
        save(Transaction(kind: .income, amount: pay.amount, category: pay.category, date: Date(), note: "Pay"))
    }

    // MARK: - Sample data

    /// Adds sample records alongside anything the user has already entered.
    func loadSampleData() {
        let sample = SampleData.make()
        commit(rescheduleReminders: true) { data in
            data.removeSampleData()
            data.transactions += sample.transactions
            data.bills += sample.bills
            data.budgets += sample.budgets
            data.goals += sample.goals
            if data.settings.openingBalance == 0 {
                data.settings.openingBalance = sample.settings.openingBalance
                data.settings.openingBalanceIsSample = true
            }
            if data.settings.pay == nil {
                data.settings.pay = sample.settings.pay
                data.settings.savingsPerPay = sample.settings.savingsPerPay
                data.settings.payIsSample = true
            }
        }
    }

    func removeSampleData() {
        commit(rescheduleReminders: true) { $0.removeSampleData() }
    }

    /// Deletes everything and returns to the welcome screen.
    func eraseAllData() {
        commit(rescheduleReminders: true) { data in
            data = AppData()
        }
    }

    // MARK: - Backup, restore and export

    enum TransferError: LocalizedError {
        case notABackup
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file isn't a Budget Planner backup."
            case .newerVersion: return "This backup was made by a newer version of the app. Please update the app first."
            }
        }
    }

    func backupFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget Planner Backup \(Self.fileDate()).json")
        try encoder.encode(data).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func csvFile(for transactions: [Transaction]? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget Planner Transactions \(Self.fileDate()).csv")
        let text = TransactionCSV.export(transactions ?? data.transactions)
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Replaces all data with a backup.
    func restoreBackup(from url: URL) throws {
        let raw = try Self.readSecurityScoped(url)
        let restored: AppData
        do {
            restored = try JSONDecoder().decode(AppData.self, from: raw)
        } catch {
            throw TransferError.notABackup
        }
        guard restored.version <= AppData.currentVersion else { throw TransferError.newerVersion }
        commit(rescheduleReminders: true) { data in
            data = restored
            data.settings.hasOnboarded = true
        }
    }

    /// Adds transactions from a CSV file. Returns (imported, skipped) counts.
    func importCSV(from url: URL) throws -> (imported: Int, skipped: Int) {
        let raw = try Self.readSecurityScoped(url)
        guard let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) else {
            throw TransactionCSV.ImportError.empty
        }
        let result = try TransactionCSV.parse(text)
        commit { $0.transactions += result.transactions }
        return (result.transactions.count, result.skippedRows.count)
    }

    private static func readSecurityScoped(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private static func fileDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: Date())
    }

    // MARK: - Widget and reminders

    private func refreshWidget() {
        let engine = self.engine
        let budget = engine.primaryBudgetStatus
        let nextBill = engine.upcomingBills(days: 60).first
        let plan = engine.paydayPlan()
        let snapshot = WidgetSnapshot(
            available: engine.availableBalance,
            safeToSpend: plan?.safeToSpend,
            nextPayday: plan?.nextPayday,
            budgetName: budget.map { "\($0.budget.period.title) budget" },
            budgetAmount: budget?.budget.amount,
            budgetRemaining: budget?.remaining,
            spentThisMonth: engine.totals(in: engine.thisMonth).expenses,
            nextBillName: nextBill?.bill.name,
            nextBillAmount: nextBill?.bill.amount,
            nextBillDate: nextBill?.date,
            hideAmounts: data.settings.hideWidgetAmounts,
            isSample: data.hasSampleData,
            updatedAt: Date()
        )
        var previous = SharedStore.load()
        previous?.updatedAt = snapshot.updatedAt
        if previous != snapshot {
            SharedStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func refreshReminders() {
        let bills = data.bills
        let enabled = data.settings.billRemindersEnabled && data.settings.hasOnboarded
        Task { await reminders.reschedule(bills: bills, enabled: enabled) }
    }

    /// Asks for notification permission. Returns whether reminders can be shown.
    func requestReminderPermission() async -> Bool {
        let granted = await reminders.requestAuthorization()
        refreshReminders()
        return granted
    }
}
