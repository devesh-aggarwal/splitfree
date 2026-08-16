import Foundation
import SwiftData

/// How a settle-up payment was made. Only used as a label - SplitFree never
/// touches money itself, it just records what happened and can hand off to
/// the payment app of your choice.
enum PaymentMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case cash, bankTransfer, venmo, paypal, cashApp, upi, zelle, revolut, wise, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bankTransfer: String(localized: "Bank transfer")
        case .venmo: "Venmo"
        case .paypal: "PayPal"
        case .cashApp: "Cash App"
        case .upi: String(localized: "UPI")
        case .zelle: "Zelle"
        case .revolut: "Revolut"
        case .wise: "Wise"
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .cash: "banknote.fill"
        case .bankTransfer: "building.columns.fill"
        case .venmo: "v.circle.fill"
        case .paypal: "p.circle.fill"
        case .cashApp: "dollarsign.circle.fill"
        case .upi: "indianrupeesign.circle.fill"
        case .zelle: "z.circle.fill"
        case .revolut: "r.circle.fill"
        case .wise: "w.circle.fill"
        case .other: "arrow.left.arrow.right.circle.fill"
        }
    }
}

/// A payment from one person to another that cancels out debt.
@Model
final class Settlement {
    var id: UUID = UUID()
    var amountMinorUnits: Int = 0
    var currencyCode: String = "USD"
    var date: Date = Date()
    var createdAt: Date = Date()
    var notes: String = ""
    var updatedAt: Date = Date()

    /// A fingerprint of this row's contents as the server last saw them.
    ///
    /// Sync decides what to push by comparing it against the row's current
    /// fingerprint. A hash is used rather than a dirty flag or a timestamp
    /// because both of those have to be *remembered* at every write site, and
    /// one forgotten line means an edit that silently never syncs. A hash cannot
    /// be forgotten: if the contents differ, it differs.
    var syncedFingerprint: String = ""
    var methodRaw: String = PaymentMethod.cash.rawValue

    var exchangeRateToBase: Double = 1.0
    var baseCurrencyCode: String = "USD"

    /// The person handing money over.
    var fromParticipant: Participant?
    /// The person receiving it.
    var toParticipant: Participant?
    /// Nil for a settle-up between two friends outside any group.
    var group: SpendingGroup?

    init(
        from: Participant?,
        to: Participant?,
        amountMinorUnits: Int,
        currencyCode: String,
        date: Date = Date(),
        method: PaymentMethod = .cash,
        group: SpendingGroup? = nil
    ) {
        self.id = UUID()
        self.fromParticipant = from
        self.toParticipant = to
        self.amountMinorUnits = amountMinorUnits
        self.currencyCode = currencyCode
        self.baseCurrencyCode = currencyCode
        self.date = date
        self.methodRaw = method.rawValue
        self.group = group
        self.createdAt = Date()
    }
}

extension Settlement {
    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .cash }
        set { methodRaw = newValue.rawValue }
    }

    var amount: Money { Money(minorUnits: amountMinorUnits, currencyCode: currencyCode) }

    /// "You paid Ana $30.00"
    var summary: String {
        let payer = fromParticipant?.displayName ?? String(localized: "Someone")
        let payee = toParticipant?.displayName ?? String(localized: "someone")
        return String(
            format: String(localized: "%1$@ paid %2$@ %3$@", comment: "Payer, payee, amount"),
            payer,
            payee,
            amount.formatted()
        )
    }

    var amountInBaseMinorUnits: Int {
        guard currencyCode != baseCurrencyCode else { return amountMinorUnits }
        let fromDigits = Currency.fractionDigits(for: currencyCode)
        let toDigits = Currency.fractionDigits(for: baseCurrencyCode)
        let major = Double(amountMinorUnits) / pow(10, Double(fromDigits))
        return Int((major * exchangeRateToBase * pow(10, Double(toDigits))).rounded())
    }

    func net(for participant: Participant) -> Int {
        if fromParticipant?.id == participant.id { return amountMinorUnits }
        if toParticipant?.id == participant.id { return -amountMinorUnits }
        return 0
    }
}
