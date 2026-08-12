import Foundation
import UIKit
import Vision

/// Pulls line items, tax, tip and a total out of receipt text.
///
/// Receipts have no standard format, so this is heuristic by design: it looks
/// for lines that end in something money-shaped, treats the text to the left as
/// the item name, and recognises a handful of keywords for the summary lines.
/// Whatever it gets wrong is trivially fixable in the itemization editor — the
/// goal is to save typing, not to be authoritative.
enum ReceiptParser {

    struct Result {
        var items: [ParsedItem] = []
        var subtotalMinorUnits: Int?
        var taxMinorUnits: Int?
        var tipMinorUnits: Int?
        var totalMinorUnits: Int?
        var rawText: String = ""
    }

    struct ParsedItem {
        var name: String
        var amountMinorUnits: Int
        var quantity: Int = 1
    }

    // MARK: - OCR

    /// Runs text recognition over an image.
    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        let languages = Locale.preferredLanguages

        return await withCheckedContinuation { continuation in
            // The request and handler are built inside the work item so nothing
            // non-Sendable crosses the concurrency boundary.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])

                let observations = request.results ?? []
                // Receipts read top to bottom; Vision reports bottom-up origins.
                let lines = observations
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
        }
    }

    // MARK: - Parsing

    static func parse(lines: [String], currencyCode: String) -> Result {
        var result = Result()
        result.rawText = lines.joined(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let (label, amount) = splitLabelAndAmount(trimmed, currencyCode: currencyCode) else { continue }

            let lowered = label.lowercased()

            // Subtotal must be tested first: "subtotal" contains "total", so
            // checking the other way round swallows it.
            if matches(lowered, keywords: subtotalKeywords) {
                result.subtotalMinorUnits = amount
                continue
            }
            if matches(lowered, keywords: totalKeywords) {
                // Prefer the last total seen — receipts often print a running
                // total above and the amount actually due below.
                result.totalMinorUnits = amount
                continue
            }
            if matches(lowered, keywords: taxKeywords) {
                result.taxMinorUnits = (result.taxMinorUnits ?? 0) + amount
                continue
            }
            if matches(lowered, keywords: tipKeywords) {
                result.tipMinorUnits = amount
                continue
            }
            if matches(lowered, keywords: ignoreKeywords) { continue }

            let (name, quantity) = extractQuantity(from: label)
            let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: " .-–—*#:"))
            guard cleaned.count >= 2, amount > 0 else { continue }
            // A "line item" costing more than the printed total is a misread.
            result.items.append(ParsedItem(name: cleaned, amountMinorUnits: amount, quantity: quantity))
        }

        // Drop obvious misreads once we know the total.
        if let total = result.totalMinorUnits, total > 0 {
            result.items = result.items.filter { $0.amountMinorUnits <= total }
        }

        return result
    }

    static func parse(image: UIImage, currencyCode: String) async -> Result {
        let lines = await recognizeText(in: image)
        return parse(lines: lines, currencyCode: currencyCode)
    }

    // MARK: - Helpers

    /// Splits "Margherita pizza    14.50" into ("Margherita pizza", 1450).
    /// Returns nil when the line has no trailing money-shaped token.
    private static func splitLabelAndAmount(_ line: String, currencyCode: String) -> (String, Int)? {
        guard let match = line.range(of: amountPattern, options: [.regularExpression, .backwards]) else {
            return nil
        }
        // The amount must actually finish the line (allowing a trailing symbol
        // or letter like "A" for a tax class), or it's an item code.
        let tail = line[match.upperBound...].trimmingCharacters(in: .whitespaces)
        guard tail.count <= 2 else { return nil }

        let amountText = String(line[match])
        guard let minorUnits = CurrencyFormatting.parse(amountText, currencyCode: currencyCode), minorUnits != 0 else {
            return nil
        }
        let label = String(line[line.startIndex..<match.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        return (label, abs(minorUnits))
    }

    /// Matches 12.50, 1,234.56, 12,50, $8.00, £4 — with or without a symbol.
    private static let amountPattern = #"[$€£¥₹₽₩฿]?\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})\s?[$€£¥₹₽₩฿]?"#

    /// "2 x Latte" or "Latte x2" → quantity 2.
    private static func extractQuantity(from label: String) -> (name: String, quantity: Int) {
        if let match = label.range(of: #"^\s*(\d{1,2})\s*[xX×@]\s*"#, options: .regularExpression) {
            let digits = label[match].filter(\.isNumber)
            let quantity = Int(digits) ?? 1
            return (String(label[match.upperBound...]), max(1, quantity))
        }
        if let match = label.range(of: #"\s*[xX×]\s*(\d{1,2})\s*$"#, options: .regularExpression) {
            let digits = label[match].filter(\.isNumber)
            let quantity = Int(digits) ?? 1
            return (String(label[label.startIndex..<match.lowerBound]), max(1, quantity))
        }
        return (label, 1)
    }

    private static func matches(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    // Keyword lists cover the languages the app ships in.
    private static let totalKeywords = [
        "total", "amount due", "balance due", "grand total", "importe", "montant",
        "gesamt", "totale", "合計", "总计", "कुल", "总额", "à payer", "zu zahlen",
    ]
    private static let subtotalKeywords = [
        "subtotal", "sub total", "sub-total", "zwischensumme", "sous-total", "subtotale", "小計",
    ]
    private static let taxKeywords = [
        "tax", "vat", "gst", "hst", "pst", "iva", "tva", "mwst", "steuer", "impuesto", "sales tax", "税",
    ]
    private static let tipKeywords = [
        "tip", "gratuity", "service charge", "propina", "pourboire", "trinkgeld", "mancia", "service fee",
    ]
    private static let ignoreKeywords = [
        "change", "cash", "card", "visa", "mastercard", "amex", "debit", "credit",
        "auth", "approval", "terminal", "merchant", "receipt", "invoice", "order #",
        "table", "server", "cashier", "tel", "phone", "www", "http", "thank you",
        "date", "time", "ref", "trans", "account", "balance", "points", "member",
    ]
}
