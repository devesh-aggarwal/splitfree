import Foundation
import Testing

@testable import SplitFree

@Suite("Money")
struct MoneyTests {

    @Test("Decimal amounts convert to minor units without floating-point drift")
    func decimalToMinorUnits() {
        #expect(Money(amount: Decimal(string: "12.50")!, currencyCode: "USD").minorUnits == 1250)
        #expect(Money(amount: Decimal(string: "0.07")!, currencyCode: "USD").minorUnits == 7)
        #expect(Money(amount: Decimal(string: "1234.56")!, currencyCode: "EUR").minorUnits == 123_456)
    }

    @Test("Zero-decimal currencies never gain a fractional unit")
    func zeroDecimalCurrencies() {
        #expect(Currency.fractionDigits(for: "JPY") == 0)
        #expect(Money(amount: Decimal(string: "1500")!, currencyCode: "JPY").minorUnits == 1500)
        #expect(Money(minorUnits: 1500, currencyCode: "JPY").decimalValue == Decimal(1500))
    }

    @Test("Three-decimal currencies keep their extra precision")
    func threeDecimalCurrencies() {
        #expect(Currency.fractionDigits(for: "KWD") == 3)
        #expect(Money(amount: Decimal(string: "1.234")!, currencyCode: "KWD").minorUnits == 1234)
    }

    @Test("Arithmetic is exact")
    func arithmetic() {
        let a = Money(minorUnits: 1000, currencyCode: "USD")
        let b = Money(minorUnits: 333, currencyCode: "USD")
        #expect((a - b).minorUnits == 667)
        #expect((a + b).minorUnits == 1333)
        #expect((-a).minorUnits == -1000)
        #expect(a.magnitude.minorUnits == 1000)
        #expect((-a).magnitude.minorUnits == 1000)
    }

    // MARK: - Parsing

    @Test("Typed amounts parse regardless of separator convention")
    func parsingSeparators() {
        #expect(CurrencyFormatting.parse("12.50", currencyCode: "USD") == 1250)
        #expect(CurrencyFormatting.parse("12,50", currencyCode: "USD") == 1250)
        #expect(CurrencyFormatting.parse("1,234.56", currencyCode: "USD") == 123_456)
        #expect(CurrencyFormatting.parse("1.234,56", currencyCode: "USD") == 123_456)
        #expect(CurrencyFormatting.parse("$8", currencyCode: "USD") == 800)
        #expect(CurrencyFormatting.parse("€ 45,00", currencyCode: "EUR") == 4500)
    }

    @Test("Nonsense input parses to nothing rather than zero")
    func parsingRejectsGarbage() {
        #expect(CurrencyFormatting.parse("", currencyCode: "USD") == nil)
        #expect(CurrencyFormatting.parse("abc", currencyCode: "USD") == nil)
    }

    @Test("A parsed amount round-trips back through formatting")
    func parseFormatRoundTrip() {
        for text in ["0.01", "9.99", "100.00", "12345.67"] {
            let minorUnits = CurrencyFormatting.parse(text, currencyCode: "USD")
            #expect(minorUnits != nil)
            let value = Money(minorUnits: minorUnits!, currencyCode: "USD").decimalValue
            #expect(value == Decimal(string: text)!)
        }
    }

    // MARK: - Currency catalogue

    @Test("The catalogue covers more than 100 currencies with unique codes")
    func catalogueIntegrity() {
        #expect(Currency.catalog.count > 100)
        let codes = Set(Currency.catalog.map(\.code))
        #expect(codes.count == Currency.catalog.count, "duplicate currency codes")
        #expect(Currency.catalog.allSatisfy { $0.code.count == 3 })
        #expect(Currency.catalog.allSatisfy { (0...3).contains($0.fractionDigits) })
    }

    @Test("Searching finds a currency by name, code and symbol")
    func currencySearch() {
        #expect(Currency.search("dollar").contains { $0.code == "USD" })
        #expect(Currency.search("jpy").contains { $0.code == "JPY" })
        #expect(Currency.search("₹").contains { $0.code == "INR" })
    }

    @Test("An unknown code degrades gracefully instead of crashing")
    func unknownCurrency() {
        #expect(Currency.fractionDigits(for: "ZZZ") == 2)
        #expect(Currency.exists("ZZZ") == false)
        #expect(Currency.currency(for: "ZZZ").code == "ZZZ")
    }
}

@Suite("Exchange rates")
struct ExchangeRateTests {

    private var table: ExchangeRateTable {
        ExchangeRateTable(
            baseCode: "USD",
            rates: ["USD": 1, "EUR": 0.5, "JPY": 100],
            fetchedAt: Date(),
            isOffline: false
        )
    }

    @Test("Cross-rates go through the base currency")
    func crossRate() {
        #expect(table.rate(from: "USD", to: "EUR") == 0.5)
        #expect(table.rate(from: "EUR", to: "USD") == 2)
        #expect(table.rate(from: "USD", to: "USD") == 1)
    }

    @Test("Conversion respects each currency's precision")
    func conversionPrecision() {
        // $10.00 → ¥1000, and yen has no minor units.
        #expect(table.convert(minorUnits: 1000, from: "USD", to: "JPY") == 1000)
        // ¥1000 → $10.00
        #expect(table.convert(minorUnits: 1000, from: "JPY", to: "USD") == 1000)
        #expect(table.convert(minorUnits: 1000, from: "USD", to: "EUR") == 500)
    }

    @Test("A missing rate returns zero rather than a made-up number")
    func missingRate() {
        #expect(table.rate(from: "USD", to: "XYZ") == nil)
        #expect(table.convert(minorUnits: 1000, from: "USD", to: "XYZ") == 0)
    }

    @Test("The bundled offline table covers every currency in the picker")
    func bundledTableCoverage() {
        let bundled = ExchangeRateService.bundledTable
        let missing = Currency.catalog.map(\.code).filter { bundled.rates[$0] == nil }
        #expect(missing.isEmpty, "no offline rate for: \(missing)")
    }
}
