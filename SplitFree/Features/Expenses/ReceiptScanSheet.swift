import SwiftUI
import VisionKit

/// Wraps `VNDocumentCameraViewController` so a receipt can be captured with
/// perspective correction and edge detection rather than a plain photo.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}

/// Scan → read → review. The parsed items are shown before anything is applied,
/// because OCR on a crumpled receipt is a suggestion, not a fact.
struct ReceiptScanSheet: View {
    var onApply: (UIImage?, ReceiptParser.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var phase: Phase = .scanning
    @State private var scannedImage: UIImage?
    @State private var parsed: ReceiptParser.Result?

    private enum Phase {
        case scanning, reading, review, unavailable
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    if VNDocumentCameraViewController.isSupported {
                        DocumentScannerView { images in
                            handleScan(images)
                        } onCancel: {
                            dismiss()
                        }
                        .ignoresSafeArea()
                    } else {
                        unavailableState
                    }
                case .reading:
                    readingState
                case .review:
                    reviewState
                case .unavailable:
                    unavailableState
                }
            }
            .navigationTitle(phase == .review ? Text("Review the receipt") : Text("Scan a receipt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .scanning {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel") }
                    }
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { apply() } label: { Text("Use these").fontWeight(.semibold) }
                    }
                }
            }
        }
    }

    // MARK: - States

    private var readingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading the receipt…")
                .font(Typography.rowSubtitle)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    private var unavailableState: some View {
        EmptyStateView(
            symbol: "camera.metering.unknown",
            title: String(localized: "Scanning isn't available"),
            message: String(localized: "This device can't scan documents. You can still attach a photo of the receipt and add the items yourself."),
            actionTitle: String(localized: "Close")
        ) { dismiss() }
        .frame(maxHeight: .infinity)
        .screenBackground()
    }

    @ViewBuilder
    private var reviewState: some View {
        if let parsed {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = scannedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }

                    if parsed.items.isEmpty {
                        InfoBanner(
                            symbol: "exclamationmark.triangle.fill",
                            text: String(localized: "No line items were recognized. The photo will still be attached, and you can add the items by hand."),
                            tint: Palette.categoryOrange
                        )
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(parsed.items.enumerated()), id: \.offset) { index, item in
                                    HStack {
                                        Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                                            .font(Typography.rowTitle)
                                            .foregroundStyle(Palette.primaryText)
                                        Spacer()
                                        Text(
                                            Money(
                                                minorUnits: item.amountMinorUnits * item.quantity,
                                                currencyCode: settings.baseCurrencyCode
                                            ).formatted()
                                        )
                                        .font(Typography.rowMoney)
                                        .foregroundStyle(Palette.secondaryText)
                                    }
                                    .padding(Metrics.cardPadding)

                                    if index < parsed.items.count - 1 {
                                        Divider().overlay(Palette.separator).padding(.leading, Metrics.cardPadding)
                                    }
                                }
                            }
                        }
                    }

                    summaryCard(parsed)
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
        }
    }

    private func summaryCard(_ parsed: ReceiptParser.Result) -> some View {
        Card {
            VStack(spacing: 8) {
                if let subtotal = parsed.subtotalMinorUnits {
                    summaryRow(String(localized: "Subtotal"), subtotal)
                }
                if let tax = parsed.taxMinorUnits {
                    summaryRow(String(localized: "Tax"), tax)
                }
                if let tip = parsed.tipMinorUnits {
                    summaryRow(String(localized: "Tip"), tip)
                }
                if let total = parsed.totalMinorUnits {
                    Divider().overlay(Palette.separator)
                    summaryRow(String(localized: "Total"), total, isBold: true)
                }
                if parsed.subtotalMinorUnits == nil && parsed.totalMinorUnits == nil {
                    Text("No totals were recognized.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ amount: Int, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isBold ? Typography.rowTitle : Typography.rowSubtitle)
                .foregroundStyle(isBold ? Palette.primaryText : Palette.secondaryText)
            Spacer()
            Text(Money(minorUnits: amount, currencyCode: settings.baseCurrencyCode).formatted())
                .font(isBold ? Typography.rowMoney : Typography.rowSubtitle)
                .foregroundStyle(Palette.primaryText)
        }
    }

    // MARK: - Actions

    private func handleScan(_ images: [UIImage]) {
        guard let first = images.first else {
            dismiss()
            return
        }
        scannedImage = first
        phase = .reading
        Task {
            let result = await ReceiptParser.parse(image: first, currencyCode: settings.baseCurrencyCode)
            parsed = result
            phase = .review
            Haptics.success()
        }
    }

    private func apply() {
        onApply(scannedImage, parsed ?? ReceiptParser.Result())
        dismiss()
    }
}
