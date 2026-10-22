import SwiftUI
import UIKit

enum Theme {
    static let accent = Color("AccentColor")
    static let income = Color.green
    static let expense = Color.primary
    static let warning = Color.orange
    static let danger = Color.red
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)
    static let cornerRadius: CGFloat = 18

    static func color(for state: BudgetStatus.State) -> Color {
        switch state {
        case .onTrack: return .green
        case .spendingFast: return .orange
        case .over: return .red
        }
    }
}

extension Category {
    var color: Color {
        switch self {
        case .rent: return .indigo
        case .groceries: return .green
        case .transport: return .blue
        case .utilities: return .yellow
        case .phoneInternet: return .cyan
        case .insurance: return Color(red: 0.45, green: 0.52, blue: 0.62)
        case .health: return .red
        case .education: return .purple
        case .eatingOut: return .orange
        case .shopping: return .pink
        case .entertainment: return .mint
        case .subscriptions: return .teal
        case .personalCare: return .brown
        case .gifts: return Color(red: 0.86, green: 0.36, blue: 0.55)
        case .travel: return Color(red: 0.2, green: 0.6, blue: 0.86)
        case .otherExpense: return .gray
        case .salary, .partTime: return .green
        case .centrelink: return .blue
        case .freelance: return .teal
        case .taxRefund: return .indigo
        case .giftIncome: return .pink
        case .otherIncome: return .gray
        }
    }
}

extension TransactionKind {
    var color: Color { self == .income ? Theme.income : Theme.expense }
}

extension Decimal {
    /// Colour for a "money left" figure.
    var balanceColor: Color { self < 0 ? Theme.danger : .primary }
}
