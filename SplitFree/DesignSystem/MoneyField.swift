import SwiftUI
import UIKit

/// A money input that edits minor units directly.
///
/// The text the user sees is always a valid formatted amount - there is no state
/// where the field shows something that isn't a number. Typing appends digits
/// from the right, the way a card terminal or calculator behaves, so "1250"
/// becomes $12.50 without anyone hunting for the decimal point.
struct MoneyField: View {
    @Binding var minorUnits: Int
    var currencyCode: String
    var font: Font = Typography.money(34, weight: .bold)
    var alignment: TextAlignment = .center
    var tint: Color = Palette.primaryText
    var placeholderZero: Bool = true
    /// Opens the keypad as soon as the field appears - used on the new-expense
    /// screen, where the amount is always the first thing you type.
    var focusesOnAppear: Bool = false

    @State private var digits: String = ""
    @FocusState private var isFocused: Bool

    private var fractionDigits: Int { Currency.fractionDigits(for: currencyCode) }

    var body: some View {
        ZStack {
            // The real field is invisible; it exists to own the keyboard and the
            // caret. Rendering the amount ourselves keeps the formatting exact.
            TextField("", text: $digits)
                .keyboardType(fractionDigits == 0 ? .numberPad : .decimalPad)
                .focused($isFocused)
                .opacity(0.001)
                .frame(height: 1)
                .accessibilityHidden(true)
                .onChange(of: digits) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(12))
                    if filtered != newValue { digits = filtered }
                    minorUnits = Int(filtered) ?? 0
                }
                .onChange(of: minorUnits) { _, newValue in
                    // Keep in sync when something else changes the amount
                    // (currency switch, itemized total adopted).
                    let expected = newValue == 0 ? "" : String(newValue)
                    if expected != digits { digits = expected }
                }

            HStack(spacing: 1) {
                Text(displayText)
                    .font(font)
                    .foregroundStyle(minorUnits == 0 && placeholderZero ? Palette.tertiaryText : tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.quick, value: minorUnits)
                if isFocused {
                    BlinkingCaret(font: font)
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .onAppear {
            digits = minorUnits == 0 ? "" : String(minorUnits)
            if focusesOnAppear {
                // A beat of delay; focusing during the sheet's presentation
                // transition is dropped by UIKit.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    isFocused = true
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Amount"))
        .accessibilityValue(Text(displayText))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isFocused = true }
    }

    private var displayText: String {
        Money(minorUnits: minorUnits, currencyCode: currencyCode).formatted()
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}

/// The insertion caret the hidden text field can't show. Sized by the font it
/// sits beside, so it works at any scale from the big amount entry down to
/// inline row fields.
struct BlinkingCaret: View {
    var font: Font

    @State private var isVisible = true

    var body: some View {
        Text(verbatim: "0")
            .font(font)
            .monospacedDigit()
            .hidden()
            .overlay(
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 2.5)
                    .padding(.vertical, 1)
                    .opacity(isVisible ? 1 : 0)
            )
            .frame(width: 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
            .accessibilityHidden(true)
    }
}

extension UIApplication {
    /// Dismisses whichever keyboard is up, no matter which view owns the focus.
    /// SwiftUI focus state can't reach the hidden field inside `MoneyField`
    /// from an enclosing screen, so the keyboard toolbars use this instead.
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// A compact inline money field for table-style rows (exact splits, payer
/// amounts, line items) where the amount sits at the trailing edge.
struct InlineMoneyField: View {
    @Binding var minorUnits: Int
    var currencyCode: String
    var isHighlighted: Bool = false

    var body: some View {
        MoneyField(
            minorUnits: $minorUnits,
            currencyCode: currencyCode,
            font: Typography.money(17, weight: .semibold),
            alignment: .trailing,
            tint: isHighlighted ? Palette.accent : Palette.primaryText
        )
        .frame(width: 118)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHighlighted ? Palette.accent : .clear, lineWidth: 1.5)
        )
    }
}

/// A number field for percentages and share counts.
struct NumericField: View {
    @Binding var value: Double
    var suffix: String?
    var allowsDecimals: Bool = true
    var width: CGFloat = 92

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField("0", text: $text)
                .keyboardType(allowsDecimals ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(Typography.money(17, weight: .semibold))
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    let allowed = allowsDecimals ? "0123456789.," : "0123456789"
                    let filtered = newValue.filter { allowed.contains($0) }
                    if filtered != newValue { text = filtered }
                    value = Double(filtered.replacingOccurrences(of: ",", with: ".")) ?? 0
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else { return }
                    text = Self.format(newValue, allowsDecimals: allowsDecimals)
                }
            if let suffix {
                Text(suffix)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { text = Self.format(value, allowsDecimals: allowsDecimals) }
    }

    private static func format(_ value: Double, allowsDecimals: Bool) -> String {
        if value == 0 { return "" }
        if !allowsDecimals || value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
