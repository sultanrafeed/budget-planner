import SwiftUI

/// Every income and expense, grouped by day, with search, filters and export.
struct TransactionsView: View {
    @Environment(DataStore.self) private var store

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All", expenses = "Spending", income = "Income"
        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var kindFilter: KindFilter = .all
    @State private var categoryFilter: Category?
    /// Start of the month to show, or nil for all time.
    @State private var monthFilter: Date?
    @State private var sheet: TransactionSheet?
    @State private var exported: ExportedFile?

    private var filtered: [Transaction] {
        let cal = AppLocale.calendar
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.transactions
            .filter { tx in
                switch kindFilter {
                case .all: break
                case .expenses: if tx.kind != .expense { return false }
                case .income: if tx.kind != .income { return false }
                }
                if let categoryFilter, tx.category != categoryFilter { return false }
                if let monthFilter, !cal.isDate(tx.date, equalTo: monthFilter, toGranularity: .month) { return false }
                guard !query.isEmpty else { return true }
                return tx.note.lowercased().contains(query)
                    || tx.category.name.lowercased().contains(query)
                    || tx.amount.currency.contains(query)
                    || NSDecimalNumber(decimal: tx.amount).stringValue.contains(query)
            }
            .sorted { $0.date > $1.date }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Transaction]
        var id: Date { day }
    }

    private func groups(_ items: [Transaction]) -> [DayGroup] {
        let cal = AppLocale.calendar
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }

    /// Months that have transactions, newest first.
    private var months: [Date] {
        let cal = AppLocale.calendar
        let starts = Set(store.data.transactions.compactMap { cal.dateInterval(of: .month, for: $0.date)?.start })
        return starts.sorted(by: >)
    }

    private var isFiltered: Bool {
        kindFilter != .all || categoryFilter != nil || monthFilter != nil || !search.isEmpty
    }

    var body: some View {
        NavigationStack {
            let items = filtered
            List {
                if store.data.hasSampleData && !isFiltered {
                    SampleDataBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if !items.isEmpty {
                    Section {
                        summary(items)
                    }
                }

                ForEach(groups(items)) { group in
                    Section {
                        ForEach(group.items) { tx in
                            Button { sheet = .edit(tx) } label: {
                                TransactionRow(transaction: tx)
                            }
                            .tint(.primary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteTransactions([tx.id])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { sheet = .edit(tx) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayHeader(for: group.day))
                            Spacer()
                            let net = group.items.reduce(Decimal(0)) { $0 + $1.signedAmount }
                            Text(net.signedCurrency).monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if items.isEmpty {
                    if store.data.transactions.isEmpty {
                        ContentUnavailableView {
                            Label("No transactions yet", systemImage: "tray")
                        } description: {
                            Text("Add your income and spending to see where your money goes.")
                        } actions: {
                            Button("Add an expense") { sheet = .add(.expense) }
                                .buttonStyle(.borderedProminent)
                        }
                    } else if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView("Nothing matches these filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search notes, categories or amounts")
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterMenu
                    Menu {
                        Button { sheet = .add(.expense) } label: { Label("Add expense", systemImage: "minus.circle") }
                        Button { sheet = .add(.income) } label: { Label("Add income", systemImage: "plus.circle") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    } primaryAction: {
                        sheet = .add(.expense)
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
            .transactionSheet($sheet)
            .sheet(item: $exported) { file in
                ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
            }
        }
    }

    private func summary(_ items: [Transaction]) -> some View {
        let income = items.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let spent = items.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatColumn(title: "Money in", value: income, color: Theme.income)
                StatColumn(title: "Money out", value: spent)
                StatColumn(title: "Difference", value: income - spent, color: (income - spent).balanceColor)
            }
            Text("\(items.count) \(items.count == 1 ? "transaction" : "transactions")\(filterDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var filterDescription: String {
        var parts: [String] = []
        if let monthFilter { parts.append(monthFilter.monthYear) }
        if let categoryFilter { parts.append(categoryFilter.name) }
        if kindFilter != .all { parts.append(kindFilter.rawValue.lowercased()) }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $kindFilter) {
                ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Menu("Month") {
                Picker("Month", selection: $monthFilter) {
                    Text("All time").tag(Date?.none)
                    ForEach(months, id: \.self) { Text($0.monthYear).tag(Date?.some($0)) }
                }
            }
            Menu("Category") {
                Picker("Category", selection: $categoryFilter) {
                    Text("All categories").tag(Category?.none)
                    ForEach(Category.allCases) { Label($0.name, systemImage: $0.symbol).tag(Category?.some($0)) }
                }
            }
            if isFiltered {
                Button("Clear filters", role: .destructive) {
                    kindFilter = .all
                    categoryFilter = nil
                    monthFilter = nil
                    search = ""
                }
            }
            Divider()
            Button {
                do {
                    exported = ExportedFile(url: try store.csvFile(for: filtered))
                } catch {
                    store.errorMessage = "Couldn't create the export. \(error.localizedDescription)"
                }
            } label: {
                Label(isFiltered ? "Export these (CSV)" : "Export all (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(filtered.isEmpty)
        } label: {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
        .accessibilityLabel("Filter and export")
    }
}

#Preview {
    TransactionsView().environment(DataStore.preview())
}
