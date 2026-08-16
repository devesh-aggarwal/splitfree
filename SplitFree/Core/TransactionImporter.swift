import Foundation
import SwiftData

/// Reads a bank or card export and turns the rows into expenses.
///
/// Bank CSVs have no common format, so the importer sniffs the header for the
/// columns it needs and lets you correct the mapping before anything is
/// created. Nothing is written until you confirm.
@MainActor
enum TransactionImporter {

    struct Row: Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var descriptionText: String
        var amountMinorUnits: Int
        var currencyCode: String
        /// Guessed from the description; editable in the review list.
        var category: ExpenseCategory
        var isSelected: Bool = true
    }

    struct ColumnMapping {
        var dateIndex: Int?
        var descriptionIndex: Int?
        var amountIndex: Int?
        /// Some exports split debits and credits into two columns.
        var debitIndex: Int?
        var creditIndex: Int?
        var currencyIndex: Int?

        var isUsable: Bool {
            dateIndex != nil && descriptionIndex != nil && (amountIndex != nil || debitIndex != nil)
        }
    }

    struct ParseResult {
        var headers: [String] = []
        var mapping = ColumnMapping()
        var rows: [Row] = []
        var skippedCount = 0
        var warning: String?
    }

    // MARK: - Parsing

    static func parse(csv: String, defaultCurrency: String) -> ParseResult {
        var result = ParseResult()
        let lines = splitLines(csv)
        guard lines.count > 1 else {
            result.warning = String(localized: "That file doesn't look like a CSV with a header row.")
            return result
        }

        let headers = parseRow(lines[0])
        result.headers = headers
        result.mapping = inferMapping(from: headers)

        guard result.mapping.isUsable else {
            result.warning = String(localized: "Couldn't work out which columns hold the date, description and amount. Pick them below.")
            return result
        }

        result.rows = rows(from: Array(lines.dropFirst()), mapping: result.mapping, defaultCurrency: defaultCurrency, skipped: &result.skippedCount)
        return result
    }

    /// Re-reads the rows after the user corrects the column mapping.
    static func rows(
        from dataLines: [String],
        mapping: ColumnMapping,
        defaultCurrency: String,
        skipped: inout Int
    ) -> [Row] {
        var rows: [Row] = []
        skipped = 0

        for line in dataLines {
            let fields = parseRow(line)
            guard !fields.isEmpty, fields.contains(where: { !$0.isEmpty }) else { continue }

            guard let dateIndex = mapping.dateIndex,
                  let descriptionIndex = mapping.descriptionIndex,
                  dateIndex < fields.count,
                  descriptionIndex < fields.count,
                  let date = parseDate(fields[dateIndex])
            else {
                skipped += 1
                continue
            }

            let currency = mapping.currencyIndex
                .flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces).uppercased() : nil }
                .flatMap { Currency.exists($0) ? $0 : nil }
                ?? defaultCurrency

            // Only money going *out* becomes an expense. How to tell depends on
            // the shape of the file.
            var spendMinorUnits: Int?

            if let debitIndex = mapping.debitIndex, debitIndex < fields.count {
                // A debit/credit pair is unambiguous: the credit column is
                // income and its rows are dropped outright.
                let debit = CurrencyFormatting.parse(fields[debitIndex], currencyCode: currency) ?? 0
                spendMinorUnits = debit != 0 ? abs(debit) : nil
            } else if let amountIndex = mapping.amountIndex, amountIndex < fields.count {
                // A single amount column signs spending negative by convention,
                // but not every bank agrees - so a positive amount is only
                // treated as income when the description also reads like one.
                let amount = CurrencyFormatting.parse(fields[amountIndex], currencyCode: currency) ?? 0
                let isIncome = amount > 0 && looksLikeCredit(fields[descriptionIndex])
                spendMinorUnits = isIncome ? nil : abs(amount)
            }

            guard let magnitude = spendMinorUnits, magnitude != 0 else {
                skipped += 1
                continue
            }

            let description = fields[descriptionIndex].trimmingCharacters(in: .whitespaces)
            rows.append(
                Row(
                    date: date,
                    descriptionText: description.isEmpty ? String(localized: "Imported transaction") : description,
                    amountMinorUnits: magnitude,
                    currencyCode: currency,
                    category: ExpenseCategory.suggestion(for: description) ?? .general
                )
            )
        }

        return rows.sorted { $0.date > $1.date }
    }

    private static func looksLikeCredit(_ description: String) -> Bool {
        let text = description.lowercased()
        return ["refund", "payment received", "credit", "deposit", "salary", "payroll", "interest"]
            .contains { text.contains($0) }
    }

    // MARK: - Column inference

    private static func inferMapping(from headers: [String]) -> ColumnMapping {
        var mapping = ColumnMapping()
        for (index, raw) in headers.enumerated() {
            let header = raw.lowercased().trimmingCharacters(in: .whitespaces)
            if mapping.dateIndex == nil, ["date", "transaction date", "posted date", "posting date", "fecha", "datum"].contains(where: { header.contains($0) }) {
                mapping.dateIndex = index
            }
            if mapping.descriptionIndex == nil, ["description", "details", "narrative", "memo", "payee", "merchant", "name", "reference"].contains(where: { header.contains($0) }) {
                mapping.descriptionIndex = index
            }
            if mapping.amountIndex == nil, header == "amount" || header.contains("amount") && !header.contains("foreign") {
                mapping.amountIndex = index
            }
            if mapping.debitIndex == nil, ["debit", "withdrawal", "money out", "paid out"].contains(where: { header.contains($0) }) {
                mapping.debitIndex = index
            }
            if mapping.creditIndex == nil, ["credit", "deposit", "money in", "paid in"].contains(where: { header.contains($0) }) {
                mapping.creditIndex = index
            }
            if mapping.currencyIndex == nil, header.contains("currency") {
                mapping.currencyIndex = index
            }
        }
        // A debit/credit pair beats a single amount column when both are present.
        if mapping.debitIndex != nil && mapping.creditIndex != nil {
            mapping.amountIndex = nil
        }
        return mapping
    }

    // MARK: - Field parsing

    /// Splits on newlines that aren't inside a quoted field.
    private static func splitLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if (character == "\n" || character == "\r") && !inQuotes {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(current) }
        return lines
    }

    /// RFC 4180 field splitting, including `""` as an escaped quote.
    static func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",", ";", "\t": fields.append(current); current = ""
                default: current.append(character)
                }
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \u{FEFF}")) }
    }

    private static let dateFormats = [
        "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy", "MM-dd-yyyy",
        "yyyy/MM/dd", "dd.MM.yyyy", "d MMM yyyy", "dd MMM yyyy", "MMM d, yyyy",
        "yyyy-MM-dd'T'HH:mm:ss", "dd/MM/yy", "MM/dd/yy",
    ]

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    // MARK: - Committing

    /// Creates one expense per selected row, split according to the chosen
    /// participants. The importing user is always the payer, since these come
    /// off their own statement.
    @discardableResult
    static func commit(
        rows: [Row],
        group: SpendingGroup?,
        participants: [Participant],
        payer: Participant,
        splitEqually: Bool,
        baseCurrencyCode: String,
        rates: ExchangeRateTable,
        in context: ModelContext
    ) -> Int {
        let selected = rows.filter(\.isSelected)
        guard !selected.isEmpty, !participants.isEmpty else { return 0 }

        for row in selected {
            let expense = Expense(
                title: row.descriptionText,
                amountMinorUnits: row.amountMinorUnits,
                currencyCode: row.currencyCode,
                date: row.date,
                category: row.category,
                splitMethod: splitEqually ? .equal : .exact,
                group: group
            )
            expense.baseCurrencyCode = baseCurrencyCode
            expense.exchangeRateToBase = rates.rate(from: row.currencyCode, to: baseCurrencyCode) ?? 1
            context.insert(expense)

            let ids = participants.map(\.id)
            let allocations = splitEqually
                ? SplitCalculator.equal(total: row.amountMinorUnits, among: ids)
                : [SplitCalculator.Allocation(participantID: payer.id, amountMinorUnits: row.amountMinorUnits, weight: 1)]

            let shares = allocations.compactMap { allocation -> (Participant, Int, Double)? in
                guard let person = participants.first(where: { $0.id == allocation.participantID }) else { return nil }
                return (person, allocation.amountMinorUnits, allocation.weight)
            }

            Ledger.applySplit(
                to: expense,
                payers: [(payer, row.amountMinorUnits)],
                shares: shares.map { (participant: $0.0, amountMinorUnits: $0.1, weight: $0.2) },
                in: context
            )
        }

        Ledger.log(
            .transactionsImported,
            headline: String(
                localized: "Imported ^[\(selected.count) transaction](inflect: true)",
                comment: "Count"
            ),
            detail: group?.displayName ?? String(localized: "No group"),
            groupID: group?.id,
            groupName: group?.name ?? "",
            in: context
        )

        try? context.save()
        return selected.count
    }
}
