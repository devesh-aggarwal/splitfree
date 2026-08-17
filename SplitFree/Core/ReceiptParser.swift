import Foundation
import UIKit
import Vision

/// Pulls line items, tax, tip and a total out of receipt text.
///
/// Receipts have no standard format, so this is heuristic by design: it looks
/// for lines that end in something money-shaped, treats the text to the left as
/// the item name, and recognises a handful of keywords for the summary lines.
/// Whatever it gets wrong is trivially fixable in the itemization editor - the
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

    /// A piece of recognized text and where it sat on the page.
    struct Fragment {
        var text: String
        var frame: CGRect
    }

    /// Runs text recognition over an image.
    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        // A photo's pixel data is often stored rotated, with the orientation
        // flag saying how to display it. Vision reads the raw pixels, so the
        // flag must be passed along or a portrait photo is OCR'd sideways and
        // nothing is recognized. (Scanner output is always upright, which is
        // how this path can look fine in one flow and fail in the other.)
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let preferredLanguages = Locale.preferredLanguages

        return await withCheckedContinuation { continuation in
            // The request and handler are built inside the work item so nothing
            // non-Sendable crosses the concurrency boundary.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                // Only request languages Vision actually supports: one
                // unsupported code (e.g. an "en-IN" device language) makes
                // `perform` throw and OCR silently return nothing at all.
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let usable = preferredLanguages.filter { preferred in
                    supported.contains { $0 == preferred || $0.hasPrefix(preferred.prefix(2)) }
                }
                if !usable.isEmpty {
                    request.recognitionLanguages = usable
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                try? handler.perform([request])

                let observations = request.results ?? []
                let fragments = observations.compactMap { observation -> Fragment? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return Fragment(text: text, frame: observation.boundingBox)
                }
                continuation.resume(returning: assembleLines(from: fragments))
            }
        }
    }

    /// Reunites fragments that share a visual row.
    ///
    /// Vision reports one observation per detected text box, and the wide gap
    /// on a receipt between the item column and the price column means they
    /// arrive as separate boxes. The parser needs "Flat White" and "9.00" back
    /// on one line, in left-to-right order, to see an item at all.
    static func assembleLines(from fragments: [Fragment]) -> [String] {
        // Receipts read top to bottom; Vision reports bottom-up origins.
        let sorted = fragments.sorted { $0.frame.midY > $1.frame.midY }

        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                let tolerance = max(anchor.frame.height, fragment.frame.height) * 0.6
                return abs(anchor.frame.midY - fragment.frame.midY) < tolerance
            }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        return rows.map { row in
            row.sorted { $0.frame.minX < $1.frame.minX }.map(\.text).joined(separator: "  ")
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
                // Prefer the last total seen - receipts often print a running
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

            let (name, parsedQuantity, priceIsLineTotal) = extractQuantity(from: label)
            let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: " .-–—*#:"))
            guard cleaned.count >= 2, amount > 0 else { continue }

            // "2 x Cheeseburger  25.90" prints the line total, but items are
            // stored as unit price × quantity, so the price must be divided or
            // the item counts double. When it doesn't divide evenly the line is
            // kept whole - the sum matters more than the quantity badge.
            var quantity = parsedQuantity
            var unitAmount = amount
            if quantity > 1, priceIsLineTotal {
                if amount % quantity == 0 {
                    unitAmount = amount / quantity
                } else {
                    quantity = 1
                }
            }
            result.items.append(ParsedItem(name: cleaned, amountMinorUnits: unitAmount, quantity: quantity))
        }

        // Drop obvious misreads once we know the total.
        if let total = result.totalMinorUnits, total > 0 {
            result.items = result.items.filter { $0.amountMinorUnits * $0.quantity <= total }
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

    /// Matches 12.50, 1,234.56, 12,50, $8.00, £4 - with or without a symbol.
    private static let amountPattern = #"[$€£¥₹₽₩฿]?\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})\s?[$€£¥₹₽₩฿]?"#

    /// "2 x Latte" or "Latte x2" → quantity 2.
    ///
    /// `priceIsLineTotal` reports what the trailing price means for that form:
    /// "2 x Latte 9.00" prints the extended total, while "2 @ 4.50" quotes the
    /// unit price.
    private static func extractQuantity(from label: String) -> (name: String, quantity: Int, priceIsLineTotal: Bool) {
        if let match = label.range(of: #"^\s*(\d{1,2})\s*[xX×@]\s*"#, options: .regularExpression) {
            let marker = label[match]
            let digits = marker.filter(\.isNumber)
            let quantity = Int(digits) ?? 1
            return (String(label[match.upperBound...]), max(1, quantity), !marker.contains("@"))
        }
        if let match = label.range(of: #"\s*[xX×]\s*(\d{1,2})\s*$"#, options: .regularExpression) {
            let digits = label[match].filter(\.isNumber)
            let quantity = Int(digits) ?? 1
            return (String(label[label.startIndex..<match.lowerBound]), max(1, quantity), true)
        }
        return (label, 1, true)
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

extension CGImagePropertyOrientation {
    /// UIKit and ImageIO number their orientations differently; Vision speaks ImageIO.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
