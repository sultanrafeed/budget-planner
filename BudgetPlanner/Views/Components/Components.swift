import SwiftUI
import UIKit

// MARK: - Card

/// Rounded card used on the dashboard and insight screens.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Category icon

struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress bar

struct ProgressBar: View {
    /// 0...1 (values above 1 are shown full).
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 8
    /// Optional marker, e.g. how much of the month has passed.
    var marker: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(value > 0 ? height : 0, proxy.size.width * min(1, max(0, value))))
                if let marker {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: height + 6)
                        .offset(x: proxy.size.width * min(1, max(0, marker)) - 1)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Sample data

struct SampleBadge: View {
    var body: some View {
        Text("SAMPLE")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Sample data")
    }
}

/// Explains that sample data is showing and offers to remove it.
struct SampleDataBanner: View {
    @Environment(DataStore.self) private var store
    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "testtube.2")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("You're viewing sample data")
                    .font(.subheadline.weight(.semibold))
                Text("Sample items are marked SAMPLE. Remove them when you're ready to use your own numbers – anything you've added stays.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Remove sample data") { confirmRemove = true }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .confirmationDialog("Remove all sample data?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove sample data", role: .destructive) { store.removeSampleData() }
        } message: {
            Text("Only sample records are removed. Anything you've entered yourself is kept.")
        }
    }
}

// MARK: - Amount input

/// A large currency entry field that accepts digits and one decimal point.
struct AmountField: View {
    let title: String
    @Binding var text: String
    var large: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("$")
                .font(large ? .system(size: 34, weight: .semibold, design: .rounded) : .body)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(large ? .system(size: 44, weight: .semibold, design: .rounded) : .body)
                .minimumScaleFactor(0.5)
                .onChange(of: text) { _, newValue in
                    let cleaned = AmountInput.sanitise(newValue)
                    if cleaned != newValue { text = cleaned }
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

enum AmountInput {
    static let maximum: Decimal = 10_000_000

    /// Keeps digits and a single decimal point with at most two decimal places.
    static func sanitise(_ text: String) -> String {
        var result = ""
        var seenPoint = false
        var decimals = 0
        for char in text {
            if char.isNumber, char.isASCII {
                if seenPoint {
                    guard decimals < 2 else { continue }
                    decimals += 1
                }
                result.append(char)
            } else if (char == "." || char == ","), !seenPoint {
                seenPoint = true
                result.append(".")
            }
        }
        if result.count > 12 { result = String(result.prefix(12)) }
        return result
    }

    static func parse(_ text: String) -> Decimal? {
        guard let value = Decimal(string: sanitise(text), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return value.rounded()
    }

    /// A friendly validation message, or nil when the amount is fine.
    static func problem(with text: String, allowZero: Bool = false) -> String? {
        guard !text.isEmpty else { return "Enter an amount." }
        guard let value = parse(text) else { return "That doesn't look like an amount." }
        if value <= 0 && !(allowZero && value == 0) { return "The amount must be more than $0." }
        if value > maximum { return "That amount is too large." }
        return nil
    }

    /// Text for an existing amount, e.g. 12.5 → "12.50", 300 → "300".
    static func text(for value: Decimal) -> String {
        guard value != 0 else { return "" }
        let rounded = value.rounded()
        return rounded == rounded.rounded(0) ? NSDecimalNumber(decimal: rounded).stringValue
            : String(format: "%.2f", rounded.doubleValue)
    }
}

// MARK: - Rows

struct TransactionRow: View {
    let transaction: Transaction
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.title)
                        .font(.body)
                        .lineLimit(1)
                    if transaction.isSample { SampleBadge() }
                }
                Text(showDate ? "\(transaction.category.name) · \(transaction.date.dayMonth)" : transaction.category.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.kind == .income ? "+" + transaction.amount.currency : "-" + transaction.amount.currency)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.kind == .income ? Theme.income : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Today", "Tomorrow", "In 3 days", "2 days overdue".
func dueLabel(for date: Date, now: Date = Date()) -> String {
    let cal = AppLocale.calendar
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<(-1): return "\(-days) days overdue"
    case -1: return "1 day overdue"
    case 0: return "Due today"
    case 1: return "Due tomorrow"
    case 2...6: return "In \(days) days · \(date.weekdayDayMonth)"
    default: return date.weekdayDayMonth
    }
}

/// "Today", "Yesterday" or "Thu 22 Oct".
func dayHeader(for date: Date, now: Date = Date()) -> String {
    let cal = AppLocale.calendar
    if cal.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
    if cal.isDate(date, equalTo: now, toGranularity: .year) { return date.weekdayDayMonth }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(AppLocale.locale))
}

// MARK: - Share sheet

/// Presents the iOS share sheet for exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Labeled value

struct StatColumn: View {
    let title: String
    let value: Decimal
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.currencyWhole)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
