import Foundation
import UserNotifications

/// Schedules local notifications for upcoming bills. Nothing leaves the device.
final class BillReminderScheduler {
    private static let idPrefix = "bill-reminder-"
    /// iOS allows 64 pending notifications per app; leave some headroom.
    private static let maxReminders = 50
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    func reschedule(bills: [Bill], enabled: Bool, now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled, await isAuthorized() else { return }

        let calendar = AppLocale.calendar
        let horizon = calendar.date(byAdding: .day, value: 90, to: now)!
        var requests: [(Date, UNNotificationRequest)] = []

        for bill in bills where bill.isActive {
            guard let daysBefore = bill.remindDaysBefore else { continue }
            let window = DateInterval(start: calendar.startOfDay(for: now), end: horizon)
            for due in bill.dueDates(in: window, calendar: calendar).prefix(3) {
                guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: due)),
                      let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      fire > now
                else { continue }

                let content = UNMutableNotificationContent()
                content.title = Self.title(for: bill, daysBefore: daysBefore)
                content.body = "\(bill.amount.currency) is due on \(due.weekdayDayMonth)."
                content.sound = .default

                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = Self.idPrefix + bill.id.uuidString + "-" + String(Int(due.timeIntervalSince1970))
                requests.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
            }
        }

        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(Self.maxReminders) {
            try? await center.add(request)
        }
    }

    private static func title(for bill: Bill, daysBefore: Int) -> String {
        switch daysBefore {
        case 0: return "\(bill.name) is due today"
        case 1: return "\(bill.name) is due tomorrow"
        default: return "\(bill.name) is due in \(daysBefore) days"
        }
    }
}
