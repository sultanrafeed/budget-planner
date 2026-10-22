import SwiftUI
import WidgetKit

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(BudgetEntry(date: Date(), snapshot: context.isPreview ? (SharedStore.load() ?? .placeholder) : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        // The app reloads the widget whenever data changes; refresh after midnight
        // too so "due tomorrow" style labels stay correct.
        let entry = BudgetEntry(date: Date(), snapshot: SharedStore.load())
        let cal = AppLocale.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        completion(Timeline(entries: [entry], policy: .after(tomorrow.addingTimeInterval(60))))
    }
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: medium(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            case .accessoryInline: Text("Available \(amount(snapshot.available, snapshot))")
            default: small(snapshot)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.title2).foregroundStyle(Color("AccentColor"))
                Text("Open Budget Planner to set up this widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func amount(_ value: Decimal, _ snapshot: WidgetSnapshot, whole: Bool = false) -> String {
        snapshot.hideAmounts ? "$•••" : (whole ? value.currencyWhole : value.currency)
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if s.isSample {
                    Text("SAMPLE").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
                }
            }
            Text(amount(s.available, s, whole: true))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(s.available < 0 ? Color.red : Color.primary)
            Spacer(minLength: 2)
            if let remaining = s.budgetRemaining {
                Text(remaining >= 0 ? "\(amount(remaining, s, whole: true)) left in budget" : "\(amount(-remaining, s, whole: true)) over budget")
                    .font(.caption2)
                    .foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            if let name = s.nextBillName, let date = s.nextBillDate {
                Text("\(name) · \(shortDue(date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(amount(s.available, s, whole: true))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(s.available < 0 ? Color.red : Color.primary)
                if let safe = s.safeToSpend, let payday = s.nextPayday {
                    Text("\(amount(safe, s, whole: true)) safe until payday (\(payday.dayMonth))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if s.isSample {
                    Text("SAMPLE DATA").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if let remaining = s.budgetRemaining, let total = s.budgetAmount {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.budgetName ?? "Budget").font(.caption2).foregroundStyle(.secondary)
                        Text(remaining >= 0 ? "\(amount(remaining, s, whole: true)) left" : "\(amount(-remaining, s, whole: true)) over")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(remaining < 0 ? Color.red : Color.primary)
                        ProgressView(value: min(1, max(0, total > 0 ? ((total - remaining) / total).doubleValue : 0)))
                            .tint(remaining < 0 ? Color.red : Color("AccentColor"))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent this month").font(.caption2).foregroundStyle(.secondary)
                        Text(amount(s.spentThisMonth, s, whole: true)).font(.subheadline.weight(.semibold))
                    }
                }
                if let name = s.nextBillName, let date = s.nextBillDate, let billAmount = s.nextBillAmount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next bill").font(.caption2).foregroundStyle(.secondary)
                        Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(amount(billAmount, s)) · \(shortDue(date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Available \(amount(s.available, s, whole: true))")
                .font(.headline)
                .widgetAccentable()
            if let remaining = s.budgetRemaining {
                Text(remaining >= 0 ? "\(amount(remaining, s, whole: true)) left in budget" : "Over budget")
                    .font(.caption)
            }
            if let name = s.nextBillName, let date = s.nextBillDate {
                Text("\(name) \(shortDue(date))").font(.caption)
            }
        }
    }

    private func shortDue(_ date: Date) -> String {
        let cal = AppLocale.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "overdue"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return date.weekdayDayMonth
        }
    }
}

struct BudgetWidget: Widget {
    let kind = "BudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget")
        .description("Your available money, budget left and next bill.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
    }
}

#Preview(as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .placeholder)
}
