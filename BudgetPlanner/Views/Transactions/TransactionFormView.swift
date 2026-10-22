import SwiftUI

/// Which transaction sheet to show.
enum TransactionSheet: Identifiable {
    case add(TransactionKind)
    case edit(Transaction)

    var id: String {
        switch self {
        case .add(let kind): return "add-\(kind.rawValue)"
        case .edit(let tx): return tx.id.uuidString
        }
    }
}

/// Add or edit an income or expense. Designed so a new expense takes three taps:
/// type the amount, pick a category, save.
struct TransactionFormView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Transaction?
    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var category: Category
    @State private var date: Date
    @State private var note: String
    @State private var showValidation = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    init(sheet: TransactionSheet, suggestedCategory: Category) {
        switch sheet {
        case .add(let kind):
            original = nil
            _kind = State(initialValue: kind)
            _amountText = State(initialValue: "")
            _category = State(initialValue: suggestedCategory.kind == kind ? suggestedCategory : (kind == .expense ? .groceries : .salary))
            _date = State(initialValue: Date())
            _note = State(initialValue: "")
        case .edit(let tx):
            original = tx
            _kind = State(initialValue: tx.kind)
            _amountText = State(initialValue: AmountInput.text(for: tx.amount))
            _category = State(initialValue: tx.category)
            _date = State(initialValue: tx.date)
            _note = State(initialValue: tx.note)
        }
    }

    private var amountProblem: String? { AmountInput.problem(with: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    AmountField(title: "0.00", text: $amountText, large: true)
                        .focused($amountFocused)
                        .padding(.vertical, 4)
                } footer: {
                    if showValidation, let amountProblem {
                        Text(amountProblem).foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    CategoryGrid(kind: kind, selection: $category)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                } header: {
                    Text("Category")
                } footer: {
                    Text(category.examples)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField(kind == .expense ? "Note, e.g. Coles" : "Note, e.g. Pay from work", text: $note)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                if let original {
                    Section {
                        Button("Delete \(original.kind.title.lowercased())", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        if original.isSample {
                            Text("This is a sample record. Saving changes turns it into your own record.")
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? (kind == .expense ? "New Expense" : "New Income") : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
            .onChange(of: kind) { _, newKind in
                if category.kind != newKind {
                    category = store.suggestedCategory(for: newKind)
                }
            }
            .onAppear {
                if original == nil { amountFocused = true }
            }
            .confirmationDialog("Delete this \(kind.title.lowercased())?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original { store.deleteTransactions([original.id]) }
                    dismiss()
                }
            }
            .sensoryFeedback(.error, trigger: showValidation) { _, new in new }
        }
    }

    private func save() {
        guard amountProblem == nil, let amount = AmountInput.parse(amountText) else {
            showValidation = true
            return
        }
        var tx = original ?? Transaction(kind: kind, amount: amount, category: category, date: date)
        tx.kind = kind
        tx.amount = amount
        tx.category = category
        tx.date = date
        tx.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        tx.isSample = false
        store.save(tx)
        dismiss()
    }
}

/// Tappable grid of categories for one kind.
struct CategoryGrid: View {
    let kind: TransactionKind
    @Binding var selection: Category

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Category.all(for: kind)) { category in
                Button {
                    selection = category
                } label: {
                    VStack(spacing: 6) {
                        CategoryIcon(category: category, size: 40)
                            .overlay {
                                if selection == category {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.primary, lineWidth: 2.5)
                                        .padding(-4)
                                }
                            }
                        Text(category.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selection == category ? Color.primary : Color.secondary)
                            .frame(height: 28, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.name)
                .accessibilityAddTraits(selection == category ? .isSelected : [])
            }
        }
    }
}

#Preview {
    TransactionFormView(sheet: .add(.expense), suggestedCategory: .groceries)
        .environment(DataStore.preview())
}

// MARK: - Presenting

private struct TransactionSheetModifier: ViewModifier {
    @Environment(DataStore.self) private var store
    @Binding var item: TransactionSheet?

    func body(content: Content) -> some View {
        content.sheet(item: $item) { sheet in
            let kind: TransactionKind = {
                if case .add(let kind) = sheet { return kind }
                return .expense
            }()
            TransactionFormView(sheet: sheet, suggestedCategory: store.suggestedCategory(for: kind))
        }
    }
}

extension View {
    /// Shows the add/edit transaction form when `item` is set.
    func transactionSheet(_ item: Binding<TransactionSheet?>) -> some View {
        modifier(TransactionSheetModifier(item: item))
    }
}
