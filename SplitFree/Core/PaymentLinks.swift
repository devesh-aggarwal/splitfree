import Foundation
import UIKit

/// Deep links that hand off to whichever payment app people already use.
///
/// SplitFree never touches money. It opens the other app with the amount and
/// recipient pre-filled, then records the payment once you come back and confirm
/// it. That's what makes "payment integrations" possible with no fees, no
/// accounts and no server.
@MainActor
enum PaymentLinks {

    struct Option: Identifiable {
        var id: String { method.rawValue }
        var method: PaymentMethod
        var url: URL
        var title: String
        var isInstalled: Bool
    }

    /// Builds the list of apps we can hand off to for this payment.
    static func options(
        for participant: Participant,
        amount: Money,
        note: String
    ) -> [Option] {
        var options: [Option] = []

        if !participant.venmoHandle.isEmpty,
           let url = venmo(handle: participant.venmoHandle, amount: amount, note: note) {
            options.append(
                Option(method: .venmo, url: url, title: "Venmo", isInstalled: canOpen("venmo://"))
            )
        }
        if !participant.paypalHandle.isEmpty,
           let url = paypal(handle: participant.paypalHandle, amount: amount) {
            options.append(
                Option(method: .paypal, url: url, title: "PayPal", isInstalled: true)
            )
        }
        if !participant.cashAppHandle.isEmpty,
           let url = cashApp(handle: participant.cashAppHandle, amount: amount) {
            options.append(
                Option(method: .cashApp, url: url, title: "Cash App", isInstalled: true)
            )
        }
        if !participant.upiHandle.isEmpty,
           let url = upi(handle: participant.upiHandle, name: participant.fullName, amount: amount, note: note) {
            options.append(
                Option(method: .upi, url: url, title: String(localized: "UPI"), isInstalled: canOpen("upi://"))
            )
        }

        return options
    }

    // MARK: - Builders

    /// `venmo://paycharge?txn=pay&recipients=…&amount=…&note=…`
    static func venmo(handle: String, amount: Money, note: String) -> URL? {
        var components = URLComponents(string: "venmo://paycharge")
        components?.queryItems = [
            URLQueryItem(name: "txn", value: "pay"),
            URLQueryItem(name: "recipients", value: cleanHandle(handle)),
            URLQueryItem(name: "amount", value: majorUnitsString(amount)),
            URLQueryItem(name: "note", value: note),
        ]
        return components?.url
    }

    /// PayPal.me works in a browser when the app isn't installed, which makes it
    /// the safest universal fallback.
    static func paypal(handle: String, amount: Money) -> URL? {
        let cleaned = cleanHandle(handle)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://paypal.me/\(cleaned)/\(majorUnitsString(amount))\(amount.currencyCode)")
    }

    static func cashApp(handle: String, amount: Money) -> URL? {
        let cleaned = cleanHandle(handle)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://cash.app/$\(cleaned)/\(majorUnitsString(amount))")
    }

    /// The Indian UPI intent scheme, understood by GPay, PhonePe, Paytm and the
    /// rest.
    static func upi(handle: String, name: String, amount: Money, note: String) -> URL? {
        var components = URLComponents(string: "upi://pay")
        components?.queryItems = [
            URLQueryItem(name: "pa", value: handle),
            URLQueryItem(name: "pn", value: name),
            URLQueryItem(name: "am", value: majorUnitsString(amount)),
            URLQueryItem(name: "cu", value: amount.currencyCode),
            URLQueryItem(name: "tn", value: note),
        ]
        return components?.url
    }

    // MARK: - Helpers

    private static func canOpen(_ scheme: String) -> Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func cleanHandle(_ handle: String) -> String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "$", with: "")
    }

    /// "24.50" - plain decimal, no symbol, which is what every scheme expects.
    private static func majorUnitsString(_ amount: Money) -> String {
        let digits = Currency.fractionDigits(for: amount.currencyCode)
        if digits == 0 { return String(abs(amount.minorUnits)) }
        let magnitude = abs(amount.minorUnits)
        let divisor = Int(pow(10.0, Double(digits)))
        return "\(magnitude / divisor).\(String(format: "%0\(digits)d", magnitude % divisor))"
    }
}
