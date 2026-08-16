import Foundation

/// An exact monetary amount stored as integer minor units (cents, paise, yen, …).
///
/// Every amount in SplitFree is an integer. Splitting, settling and balance math
/// all operate on minor units so a bill can never gain or lose a cent to binary
/// floating-point drift. `Decimal`/`Double` appear only at the edges: parsing what
/// a person typed, and formatting what they read back.
struct Money: Hashable, Codable, Sendable {
    /// Amount in the currency's smallest unit. Signed: negative means "owed to".
    var minorUnits: Int
    /// ISO 4217 alphabetic code, e.g. `USD`.
    var currencyCode: String

    init(minorUnits: Int, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    init(amount: Decimal, currencyCode: String) {
        let scale = Currency.fractionDigits(for: currencyCode)
        let factor = pow(Decimal(10), scale)
        var raw = amount * factor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .bankers)
        self.minorUnits = NSDecimalNumber(decimal: rounded).intValue
        self.currencyCode = currencyCode
    }

    static func zero(_ currencyCode: String) -> Money {
        Money(minorUnits: 0, currencyCode: currencyCode)
    }

    var isZero: Bool { minorUnits == 0 }
    var isNegative: Bool { minorUnits < 0 }
    var isPositive: Bool { minorUnits > 0 }
    var magnitude: Money { Money(minorUnits: abs(minorUnits), currencyCode: currencyCode) }

    /// The amount as a decimal in major units - for display and for rate math only.
    var decimalValue: Decimal {
        let scale = Currency.fractionDigits(for: currencyCode)
        return Decimal(minorUnits) / pow(Decimal(10), scale)
    }

    var doubleValue: Double { NSDecimalNumber(decimal: decimalValue).doubleValue }

    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Cannot add \(lhs.currencyCode) to \(rhs.currencyCode)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currencyCode: lhs.currencyCode)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Cannot subtract \(rhs.currencyCode) from \(lhs.currencyCode)")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currencyCode: lhs.currencyCode)
    }

    static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits, currencyCode: value.currencyCode)
    }

    static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.minorUnits < rhs.minorUnits }
}

extension Money {
    /// Formats using the user's locale but the amount's own currency.
    func formatted(showsSign: Bool = false, showsCurrencyCode: Bool = false) -> String {
        CurrencyFormatting.string(
            minorUnits: minorUnits,
            currencyCode: currencyCode,
            showsSign: showsSign,
            showsCurrencyCode: showsCurrencyCode
        )
    }

    /// Magnitude only - used where the sign is carried by surrounding copy
    /// ("you owe" / "owes you") rather than a minus glyph.
    func formattedAbsolute(showsCurrencyCode: Bool = false) -> String {
        magnitude.formatted(showsCurrencyCode: showsCurrencyCode)
    }
}

enum CurrencyFormatting {
    private static let cache = FormatterCache()

    static func string(
        minorUnits: Int,
        currencyCode: String,
        showsSign: Bool = false,
        showsCurrencyCode: Bool = false
    ) -> String {
        let formatter = cache.formatter(for: currencyCode, showsCurrencyCode: showsCurrencyCode)
        let scale = Currency.fractionDigits(for: currencyCode)
        let value = Decimal(minorUnits) / pow(Decimal(10), scale)
        let base = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        if showsSign && minorUnits > 0 { return "+" + base }
        return base
    }

    /// Parses free-typed input ("12.50", "1 234,56", "$8") into minor units.
    static func parse(_ text: String, currencyCode: String) -> Int? {
        let stripped = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !stripped.isEmpty else { return nil }

        // Whichever separator appears last is the decimal separator; the other groups.
        let lastDot = stripped.lastIndex(of: ".")
        let lastComma = stripped.lastIndex(of: ",")
        var normalized = stripped
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            if dot > comma {
                normalized = stripped.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = stripped.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            }
        case (nil, .some):
            normalized = stripped.replacingOccurrences(of: ",", with: ".")
        default:
            break
        }

        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Money(amount: decimal, currencyCode: currencyCode).minorUnits
    }

    /// A short symbol suitable for inline use next to a text field.
    static func symbol(for currencyCode: String) -> String {
        Currency.symbol(for: currencyCode)
    }
}

/// `NumberFormatter` construction is expensive; these are reused across the app.
private final class FormatterCache: @unchecked Sendable {
    private var storage: [String: NumberFormatter] = [:]
    private let lock = NSLock()

    func formatter(for currencyCode: String, showsCurrencyCode: Bool) -> NumberFormatter {
        let key = "\(currencyCode)|\(showsCurrencyCode)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[key] { return existing }
        let formatter = NumberFormatter()
        formatter.numberStyle = showsCurrencyCode ? .currencyISOCode : .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.autoupdatingCurrent
        let digits = Currency.fractionDigits(for: currencyCode)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        if Currency.symbol(for: currencyCode) != currencyCode && !showsCurrencyCode {
            formatter.currencySymbol = Currency.symbol(for: currencyCode)
        }
        storage[key] = formatter
        return formatter
    }
}
