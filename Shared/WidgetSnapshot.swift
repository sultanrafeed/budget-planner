import Foundation

/// A small summary the app writes for the home-screen widget.
/// Only totals are shared – never individual transactions.
struct WidgetSnapshot: Codable, Equatable {
    var available: Decimal
    var safeToSpend: Decimal?
    var nextPayday: Date?
    var budgetName: String?
    var budgetAmount: Decimal?
    var budgetRemaining: Decimal?
    var spentThisMonth: Decimal
    var nextBillName: String?
    var nextBillAmount: Decimal?
    var nextBillDate: Date?
    var hideAmounts: Bool
    var isSample: Bool
    var updatedAt: Date

    static let placeholder = WidgetSnapshot(
        available: 1_482.35,
        safeToSpend: 412.80,
        nextPayday: Date().addingTimeInterval(4 * 86_400),
        budgetName: "Monthly budget",
        budgetAmount: 2_600,
        budgetRemaining: 940.15,
        spentThisMonth: 1_659.85,
        nextBillName: "Rent",
        nextBillAmount: 320,
        nextBillDate: Date().addingTimeInterval(2 * 86_400),
        hideAmounts: false,
        isSample: true,
        updatedAt: Date()
    )
}

enum SharedStore {
    private static let snapshotKey = "widgetSnapshot.v1"

    /// The App Group is derived from the app's bundle identifier so it only needs
    /// to be configured in one place (Config/Base.xcconfig).
    static var appGroupID: String {
        var id = Bundle.main.bundleIdentifier ?? "com.example.budgetplanner"
        if id.hasSuffix(".widget") { id = String(id.dropLast(".widget".count)) }
        return "group." + id
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: snapshotKey)
    }
}
