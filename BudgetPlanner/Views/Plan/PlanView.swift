import SwiftUI

/// Budgets, bills, savings goals and payday planning in one tab.
struct PlanView: View {
    enum Page: String, CaseIterable, Identifiable, Hashable {
        case budgets = "Budgets"
        case bills = "Bills"
        case goals = "Goals"
        case payday = "Payday"
        var id: String { rawValue }
    }

    @State private var section: Page
    /// When shown inside another navigation stack (from the dashboard).
    private let embedded: Bool

    init(initialSection: Page = .budgets, embedded: Bool = false) {
        _section = State(initialValue: initialSection)
        self.embedded = embedded
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            switch section {
            case .budgets: BudgetsView()
            case .bills: BillsView()
            case .goals: GoalsView()
            case .payday: PaydayView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(section.rawValue)
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
    }
}

#Preview {
    PlanView().environment(DataStore.preview())
}
