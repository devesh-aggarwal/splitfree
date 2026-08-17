import Testing
import UIKit

@testable import SplitFree

/// End-to-end tests for the image → OCR → items pipeline.
///
/// The parser's text heuristics are covered in `ParsingTests`; these tests
/// exercise the part those skip - Vision text recognition on an actual image.
/// Critically, they include images shaped the way the photo library delivers
/// them: pixel data stored rotated, with an EXIF orientation flag saying how
/// to display it. Ignoring that flag is invisible with scanner output (always
/// upright) but breaks every portrait photo of a receipt.
@Suite("Receipt OCR end to end")
struct ReceiptOCRTests {

    // MARK: - Fixtures

    /// Renders receipt-style text into an upright image large enough for OCR.
    @MainActor
    private func renderReceipt(lines: [(String, String?)]) -> UIImage {
        let width: CGFloat = 800
        let lineHeight: CGFloat = 56
        let height = CGFloat(lines.count) * lineHeight + 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let font = UIFont.monospacedSystemFont(ofSize: 30, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
            ]
            for (index, line) in lines.enumerated() {
                let y = 60 + CGFloat(index) * lineHeight
                (line.0 as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: attributes)
                if let price = line.1 {
                    let size = (price as NSString).size(withAttributes: attributes)
                    (price as NSString).draw(
                        at: CGPoint(x: width - 48 - size.width, y: y),
                        withAttributes: attributes
                    )
                }
            }
        }
    }

    /// Rebuilds an image the way a portrait camera photo is stored: the pixel
    /// buffer physically rotated a quarter turn, and `imageOrientation` set so
    /// that UIKit (but not a naive `cgImage` consumer) displays it upright.
    private func cameraOriented(_ image: UIImage, orientation: UIImage.Orientation) -> UIImage {
        let cgImage = image.cgImage!
        let radians: CGFloat
        switch orientation {
        case .right: radians = -.pi / 2  // stored rotated 90° CCW, flag says rotate CW to view
        case .left: radians = .pi / 2
        case .down: radians = .pi
        default: radians = 0
        }

        let size = CGSize(width: image.size.width, height: image.size.height)
        let rotatedSize = (orientation == .down || orientation == .up)
            ? size
            : CGSize(width: size.height, height: size.width)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
        let rotated = renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            ctx.rotate(by: radians)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(
                cgImage,
                in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            )
        }
        return UIImage(cgImage: rotated.cgImage!, scale: 1, orientation: orientation)
    }

    private var restaurantReceipt: [(String, String?)] {
        [
            ("GREEN LEAF CAFE", nil),
            ("123 Main Street", nil),
            ("Flat White", "4.50"),
            ("Avocado Toast", "12.00"),
            ("Orange Juice", "5.25"),
            ("Subtotal", "21.75"),
            ("Tax", "1.96"),
            ("TOTAL", "23.71"),
            ("Thank you!", nil),
        ]
    }

    private var groceryReceipt: [(String, String?)] {
        [
            ("SUNRISE MARKET", nil),
            ("Bananas", "1.89"),
            ("Whole Milk", "3.49"),
            ("Sourdough Bread", "4.99"),
            ("Peanut Butter", "5.79"),
            ("TOTAL", "16.16"),
        ]
    }

    private var dinnerReceipt: [(String, String?)] {
        [
            ("TRATTORIA ROMA", nil),
            ("2 x Margherita Pizza", "28.00"),
            ("Caesar Salad", "11.50"),
            ("Tiramisu", "8.00"),
            ("Subtotal", "47.50"),
            ("Tax", "4.20"),
            ("Tip", "9.50"),
            ("TOTAL", "61.20"),
        ]
    }

    private func expectParses(_ result: ReceiptParser.Result, itemCount: Int, total: Int, note: String) {
        #expect(result.items.count == itemCount, "\(note): expected \(itemCount) items, got \(result.items.map(\.name))")
        #expect(result.totalMinorUnits == total, "\(note): expected total \(total), got \(String(describing: result.totalMinorUnits))")
    }

    // MARK: - Tests

    @Test("An upright receipt image yields its items")
    @MainActor
    func parsesUprightImage() async {
        let image = renderReceipt(lines: restaurantReceipt)
        let result = await ReceiptParser.parse(image: image, currencyCode: "USD")
        expectParses(result, itemCount: 3, total: 2371, note: "upright")
        #expect(result.items.map(\.name) == ["Flat White", "Avocado Toast", "Orange Juice"])
        #expect(result.taxMinorUnits == 196)
    }

    @Test(
        "A portrait camera photo (rotated pixels + EXIF flag) yields its items",
        arguments: [UIImage.Orientation.right, .left, .down]
    )
    @MainActor
    func parsesCameraOrientedImage(orientation: UIImage.Orientation) async {
        let image = cameraOriented(renderReceipt(lines: restaurantReceipt), orientation: orientation)
        // Sanity: the pixel buffer really is stored non-upright for the rotated cases.
        if orientation != .down {
            #expect(image.cgImage!.width != Int(image.size.width))
        }
        let result = await ReceiptParser.parse(image: image, currencyCode: "USD")
        expectParses(result, itemCount: 3, total: 2371, note: "orientation \(orientation.rawValue)")
    }

    @Test("A grocery receipt photo in portrait orientation parses")
    @MainActor
    func parsesGroceryCameraPhoto() async {
        let image = cameraOriented(renderReceipt(lines: groceryReceipt), orientation: .right)
        let result = await ReceiptParser.parse(image: image, currencyCode: "USD")
        expectParses(result, itemCount: 4, total: 1616, note: "grocery portrait")
        #expect(result.items.map(\.name).contains("Sourdough Bread"))
    }

    @Test("A dinner receipt with quantities, tax and tip parses from a portrait photo")
    @MainActor
    func parsesDinnerCameraPhoto() async {
        let image = cameraOriented(renderReceipt(lines: dinnerReceipt), orientation: .right)
        let result = await ReceiptParser.parse(image: image, currencyCode: "USD")
        expectParses(result, itemCount: 3, total: 6120, note: "dinner portrait")
        #expect(result.taxMinorUnits == 420)
        #expect(result.tipMinorUnits == 950)
        let pizza = result.items.first { $0.name.localizedCaseInsensitiveContains("pizza") }
        #expect(pizza?.quantity == 2)
        // Line totals must survive the quantity split: items + tax + tip = total.
        let itemsSum = result.items.reduce(0) { $0 + $1.amountMinorUnits * $1.quantity }
        #expect(itemsSum + result.taxMinorUnits! + result.tipMinorUnits! == result.totalMinorUnits!)
    }

    @Test("Storage compression keeps a receipt readable")
    @MainActor
    func parsesAfterStorageCompression() async {
        // The editor stores `compressedForStorage()` output; re-parsing from a
        // reloaded photo must still work after that round trip.
        let original = cameraOriented(renderReceipt(lines: groceryReceipt), orientation: .right)
        let data = original.compressedForStorage()!
        let reloaded = UIImage(data: data)!
        let result = await ReceiptParser.parse(image: reloaded, currencyCode: "USD")
        expectParses(result, itemCount: 4, total: 1616, note: "compressed round trip")
    }
}
