import Foundation

/// Spreadsheet-friendly export and import of transactions.
enum TransactionCSV {
    static let header = ["Date", "Type", "Category", "Description", "Amount (AUD)", "Sample"]

    // MARK: Export

    static func export(_ transactions: [Transaction]) -> String {
        var lines = [header.joined(separator: ",")]
        for tx in transactions.sorted(by: { $0.date > $1.date }) {
            let fields = [
                tx.date.dayMonthYear,
                tx.kind.title,
                tx.category.name,
                tx.note,
                plainAmount(tx.signedAmount),
                tx.isSample ? "Yes" : "No",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func plainAmount(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value.rounded()).stringValue
    }

    private static func escape(_ field: String) -> String {
        var value = field
        // Stop spreadsheet apps from treating text as a formula.
        if let first = value.first, "=+-@".contains(first), Decimal(string: value) == nil {
            value = "'" + value
        }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: Import

    struct ImportResult {
        var transactions: [Transaction]
        var skippedRows: [Int]
    }

    enum ImportError: LocalizedError {
        case empty
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .empty: return "The file has no rows to import."
            case .missingColumns: return "The file needs at least Date and Amount columns. Export a CSV from this app to see the expected layout."
            }
        }
    }

    /// Imports a CSV with columns Date, Amount and optionally Type, Category, Description.
    /// Dates use the Australian day/month/year order. Negative amounts are treated as spending
    /// when there is no Type column.
    static func parse(_ text: String) throws -> ImportResult {
        let rows = parseRows(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let headerRow = rows.first else { throw ImportError.empty }
        let names = headerRow.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ options: [String]) -> Int? {
            names.firstIndex { name in options.contains { name.hasPrefix($0) } }
        }
        guard let dateCol = column(["date"]), let amountCol = column(["amount", "value"]) else {
            throw ImportError.missingColumns
        }
        let typeCol = column(["type", "kind"])
        let categoryCol = column(["category"])
        let noteCol = column(["description", "note", "details", "payee"])

        var result = ImportResult(transactions: [], skippedRows: [])
        for (index, row) in rows.dropFirst().enumerated() {
            func field(_ col: Int?) -> String {
                guard let col, col < row.count else { return "" }
                return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let date = parseDate(field(dateCol)), let rawAmount = parseAmount(field(amountCol)), rawAmount != 0 else {
                result.skippedRows.append(index + 2)
                continue
            }
            let typeText = field(typeCol).lowercased()
            let kind: TransactionKind
            if typeText.hasPrefix("inc") || typeText == "credit" {
                kind = .income
            } else if typeText.hasPrefix("exp") || typeText == "debit" {
                kind = .expense
            } else {
                kind = rawAmount < 0 ? .expense : .income
            }
            let note = field(noteCol)
            result.transactions.append(Transaction(
                kind: kind,
                amount: abs(rawAmount),
                category: Category.match(field(categoryCol), kind: kind),
                date: date,
                note: String(note.prefix(120))
            ))
        }
        return result
    }

    static func parseAmount(_ text: String) -> Decimal? {
        var cleaned = text.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "AUD", with: "")
            .replacingOccurrences(of: " ", with: "")
        var negative = false
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            negative = true
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" })
        else { return nil }
        return negative ? -value : value
    }

    static func parseDate(_ text: String) -> Date? {
        let formats = ["dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "d/M/yy", "yyyy-MM-dd", "dd-MM-yyyy", "d MMM yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.calendar = AppLocale.calendar
        formatter.timeZone = AppLocale.calendar.timeZone
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                // Store at midday so the date never shifts across time zones.
                return AppLocale.calendar.date(byAdding: .hour, value: 12, to: AppLocale.calendar.startOfDay(for: date))
            }
        }
        return nil
    }

    /// RFC 4180-style parser that handles quotes, escaped quotes and new lines in fields.
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text.replacingOccurrences(of: "\u{FEFF}", with: "")).makeIterator()
        var pending: Character? = nil

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n":
                row.append(field); field = ""
                rows.append(row); row = []
            case "\r":
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
