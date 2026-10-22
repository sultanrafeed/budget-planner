import Foundation

/// Australian defaults used everywhere in the app and widget.
enum AppLocale {
    static let locale = Locale(identifier: "en_AU")
    static let currencyCode = "AUD"

    /// Gregorian calendar with weeks starting on Monday, as is usual in Australia.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        cal.timeZone = .current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()
}

extension Decimal {
    /// "$1,234.56"
    var currency: String {
        formatted(.currency(code: AppLocale.currencyCode).locale(AppLocale.locale))
    }

    /// "$1,235" – for headline numbers and chart labels.
    var currencyWhole: String {
        formatted(.currency(code: AppLocale.currencyCode).locale(AppLocale.locale).precision(.fractionLength(0)))
    }

    /// "+$12.00" / "-$12.00"
    var signedCurrency: String {
        self < 0 ? "-" + (-self).currency : "+" + currency
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Rounds to `scale` decimal places (half-up by default).
    func rounded(_ scale: Int = 2, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Rounds up to the nearest whole dollar, useful for "save $X a week" advice.
    var roundedUpToDollar: Decimal { rounded(0, .up) }
}

extension Date {
    /// "22/10/2026"
    var dayMonthYear: String {
        formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(AppLocale.locale))
    }

    /// "Thu 22 Oct"
    var weekdayDayMonth: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLocale.locale))
    }

    /// "22 Oct"
    var dayMonth: String {
        formatted(.dateTime.day().month(.abbreviated).locale(AppLocale.locale))
    }

    /// "22 October 2026"
    var longDate: String {
        formatted(.dateTime.day().month(.wide).year().locale(AppLocale.locale))
    }

    /// "October 2026"
    var monthYear: String {
        formatted(.dateTime.month(.wide).year().locale(AppLocale.locale))
    }

    /// "Oct"
    var shortMonth: String {
        formatted(.dateTime.month(.abbreviated).locale(AppLocale.locale))
    }
}
