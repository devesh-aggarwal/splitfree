import Foundation
import Testing

@testable import SplitFree

@MainActor
@Suite("Receipt parser")
struct ReceiptParserTests {

    @Test("A typical restaurant receipt yields items, tax, tip and total")
    func parsesRestaurantReceipt() {
        let lines = [
            "NOPA RESTAURANT",
            "560 Divisadero St",
            "Table 12   Server: Sam",
            "2 x Margherita pizza      24.00",
            "Caesar salad              11.50",
            "Sparkling water            4.00",
            "Subtotal                  39.50",
            "Tax                        3.55",
            "Tip                        7.90",
            "TOTAL                     50.95",
            "VISA ****4242",
            "Thank you!",
        ]
        let result = ReceiptParser.parse(lines: lines, currencyCode: "USD")

        #expect(result.subtotalMinorUnits == 3950)
        #expect(result.taxMinorUnits == 355)
        #expect(result.tipMinorUnits == 790)
        #expect(result.totalMinorUnits == 5095)

        let names = result.items.map(\.name)
        #expect(names.contains("Margherita pizza"))
        #expect(names.contains("Caesar salad"))
        #expect(names.contains("Sparkling water"))
        // Card and header lines must not become line items.
        #expect(!names.contains { $0.contains("VISA") })
        #expect(!names.contains { $0.contains("NOPA") })
    }

    @Test("A leading quantity is lifted off the item name")
    func parsesQuantity() {
        let result = ReceiptParser.parse(lines: ["3 x Croissant   9.00"], currencyCode: "USD")
        let item = result.items.first
        #expect(item?.quantity == 3)
        #expect(item?.name == "Croissant")
        #expect(item?.amountMinorUnits == 900)
    }

    @Test("Comma decimals are read correctly")
    func parsesEuropeanFormat() {
        let result = ReceiptParser.parse(lines: ["Café con leche   2,40"], currencyCode: "EUR")
        #expect(result.items.first?.amountMinorUnits == 240)
    }

    @Test("Lines with no money on them are ignored")
    func ignoresNonPriceLines() {
        let result = ReceiptParser.parse(
            lines: ["Welcome to our store", "Open 9-5", "Have a nice day"],
            currencyCode: "USD"
        )
        #expect(result.items.isEmpty)
        #expect(result.totalMinorUnits == nil)
    }

    @Test("Items priced above the printed total are discarded as misreads")
    func discardsImpossibleItems() {
        let result = ReceiptParser.parse(
            lines: ["Coffee    3.00", "Barcode 999999    9999.99", "TOTAL    3.00"],
            currencyCode: "USD"
        )
        #expect(result.items.count == 1)
        #expect(result.items.first?.name == "Coffee")
    }

    @Test("Garbage input never crashes the parser")
    func handlesGarbage() {
        let result = ReceiptParser.parse(lines: ["", "...", "%%%", "1", "$"], currencyCode: "USD")
        #expect(result.items.isEmpty)
    }
}

@MainActor
@Suite("Transaction importer")
struct TransactionImporterTests {

    @Test("A single-amount bank CSV is read with the columns inferred")
    func parsesSimpleStatement() {
        let csv = """
        Date,Description,Amount
        2026-08-01,TESCO EXPRESS,-42.50
        2026-08-03,UBER TRIP,-18.20
        2026-08-05,SALARY,2500.00
        """
        let result = TransactionImporter.parse(csv: csv, defaultCurrency: "GBP")

        #expect(result.mapping.isUsable)
        // The salary is money coming in, so it isn't an expense.
        #expect(result.rows.count == 2)
        #expect(result.rows.contains { $0.descriptionText == "TESCO EXPRESS" && $0.amountMinorUnits == 4250 })
        #expect(result.rows.contains { $0.descriptionText == "UBER TRIP" && $0.amountMinorUnits == 1820 })
    }

    @Test("Categories are guessed from the merchant name")
    func guessesCategories() {
        let csv = """
        Date,Description,Amount
        2026-08-01,UBER TRIP HELP.UBER.COM,-18.20
        2026-08-02,STARBUCKS STORE 123,-5.40
        2026-08-03,SHELL PETROL STATION,-60.00
        """
        let result = TransactionImporter.parse(csv: csv, defaultCurrency: "GBP")
        let byName = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.descriptionText, $0.category) })
        #expect(byName["UBER TRIP HELP.UBER.COM"] == .taxi)
        #expect(byName["STARBUCKS STORE 123"] == .coffee)
        #expect(byName["SHELL PETROL STATION"] == .fuel)
    }

    @Test("A debit/credit column pair is handled")
    func parsesDebitCreditColumns() {
        let csv = """
        Transaction Date,Details,Money out,Money in
        01/08/2026,COOP FOOD,23.10,
        02/08/2026,REFUND,,15.00
        """
        let result = TransactionImporter.parse(csv: csv, defaultCurrency: "GBP")
        #expect(result.mapping.debitIndex != nil)
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.amountMinorUnits == 2310)
    }

    @Test("Quoted fields containing commas stay intact")
    func handlesQuotedFields() {
        let fields = TransactionImporter.parseRow("""
        2026-08-01,"SMITH, JOHN & CO","1,234.56"
        """)
        #expect(fields.count == 3)
        #expect(fields[1] == "SMITH, JOHN & CO")
        #expect(fields[2] == "1,234.56")
    }

    @Test("Escaped double quotes survive parsing")
    func handlesEscapedQuotes() {
        let fields = TransactionImporter.parseRow("a,\"say \"\"hi\"\"\",b")
        #expect(fields == ["a", "say \"hi\"", "b"])
    }

    @Test("Common date formats are all understood")
    func parsesDateFormats() {
        for text in ["2026-08-01", "01/08/2026", "08/01/2026", "1 Aug 2026", "01.08.2026"] {
            #expect(TransactionImporter.parseDate(text) != nil, "failed on \(text)")
        }
        #expect(TransactionImporter.parseDate("not a date") == nil)
    }

    @Test("A file with no header row is reported rather than half-read")
    func rejectsHeaderlessFile() {
        let result = TransactionImporter.parse(csv: "just one line", defaultCurrency: "USD")
        #expect(result.warning != nil)
        #expect(result.rows.isEmpty)
    }

    @Test("Unrecognised columns produce a warning instead of wrong data")
    func reportsUnknownColumns() {
        let csv = """
        Col1,Col2,Col3
        a,b,c
        """
        let result = TransactionImporter.parse(csv: csv, defaultCurrency: "USD")
        #expect(!result.mapping.isUsable)
        #expect(result.warning != nil)
    }

    @Test("Rows with an unreadable date are counted as skipped, not silently dropped")
    func countsSkippedRows() {
        let csv = """
        Date,Description,Amount
        2026-08-01,GOOD ROW,-10.00
        nonsense,BAD ROW,-10.00
        """
        let result = TransactionImporter.parse(csv: csv, defaultCurrency: "USD")
        #expect(result.rows.count == 1)
        #expect(result.skippedCount == 1)
    }
}

@Suite("Category suggestions")
struct CategorySuggestionTests {

    @Test("Everyday descriptions map to sensible categories")
    func suggestsFromTitle() {
        #expect(ExpenseCategory.suggestion(for: "Dinner at Nopa") == .diningOut)
        #expect(ExpenseCategory.suggestion(for: "Uber to the airport") == .taxi)
        #expect(ExpenseCategory.suggestion(for: "Airbnb in Alfama") == .hotel)
        #expect(ExpenseCategory.suggestion(for: "August rent") == .rent)
        #expect(ExpenseCategory.suggestion(for: "Netflix") == .subscriptions)
    }

    @Test("An unrecognisable description suggests nothing rather than guessing")
    func noSuggestionForUnknown() {
        #expect(ExpenseCategory.suggestion(for: "asdfgh") == nil)
        #expect(ExpenseCategory.suggestion(for: "") == nil)
    }

    @Test("Every category belongs to exactly one group")
    func categoryGroupsCoverEverything() {
        let grouped = CategoryGroup.allCases.flatMap(\.categories)
        #expect(Set(grouped) == Set(ExpenseCategory.allCases))
        #expect(grouped.count == ExpenseCategory.allCases.count)
    }
}

@Suite("Recurrence")
struct RecurrenceTests {

    @Test("Each frequency advances by the right interval")
    func frequencyAdvances() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        let calendar = Calendar(identifier: .gregorian)
        let start = try #require(calendar.date(from: components))

        #expect(calendar.dateComponents([.day], from: start, to: RecurrenceFrequency.daily.nextDate(after: start, calendar: calendar)).day == 1)
        #expect(calendar.dateComponents([.day], from: start, to: RecurrenceFrequency.weekly.nextDate(after: start, calendar: calendar)).day == 7)
        #expect(calendar.dateComponents([.day], from: start, to: RecurrenceFrequency.biweekly.nextDate(after: start, calendar: calendar)).day == 14)
        #expect(calendar.dateComponents([.month], from: start, to: RecurrenceFrequency.monthly.nextDate(after: start, calendar: calendar)).month == 1)
        #expect(calendar.dateComponents([.month], from: start, to: RecurrenceFrequency.quarterly.nextDate(after: start, calendar: calendar)).month == 3)
        #expect(calendar.dateComponents([.year], from: start, to: RecurrenceFrequency.yearly.nextDate(after: start, calendar: calendar)).year == 1)
    }

    @Test("A rule set on the 31st clamps into February instead of skipping it")
    func monthlyClampsToShortMonths() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 31
        let calendar = Calendar(identifier: .gregorian)
        let start = try #require(calendar.date(from: components))

        let next = RecurrenceFrequency.monthly.nextDate(after: start, calendar: calendar)
        let parts = calendar.dateComponents([.month, .day], from: next)
        #expect(parts.month == 2)
        #expect(parts.day == 28)
    }
}
