package com.splitfree.core

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * An exact monetary amount stored as integer minor units (cents, paise, yen, …).
 *
 * Every amount in SplitFree is an integer. Splitting, settling and balance math
 * all operate on minor units so a bill can never gain or lose a cent to binary
 * floating-point drift. [BigDecimal] and [Double] appear only at the edges:
 * parsing what a person typed, and formatting what they read back.
 *
 * This mirrors `Money` in the iOS app exactly. The two must agree, or the same
 * expense would produce different splits on different phones.
 */
data class Money(val minorUnits: Long, val currencyCode: String) {

    val isZero: Boolean get() = minorUnits == 0L
    val isNegative: Boolean get() = minorUnits < 0
    val isPositive: Boolean get() = minorUnits > 0
    val magnitude: Money get() = Money(kotlin.math.abs(minorUnits), currencyCode)

    /** The amount in major units, for display and rate math only. */
    val decimalValue: BigDecimal
        get() = BigDecimal(minorUnits).movePointLeft(Currencies.fractionDigits(currencyCode))

    operator fun plus(other: Money): Money {
        require(currencyCode == other.currencyCode) { "Cannot add $currencyCode to ${other.currencyCode}" }
        return Money(minorUnits + other.minorUnits, currencyCode)
    }

    operator fun minus(other: Money): Money {
        require(currencyCode == other.currencyCode) { "Cannot subtract ${other.currencyCode} from $currencyCode" }
        return Money(minorUnits - other.minorUnits, currencyCode)
    }

    operator fun unaryMinus(): Money = Money(-minorUnits, currencyCode)

    /** Formats in the user's locale but this amount's own currency. */
    fun formatted(showsSign: Boolean = false, showsCurrencyCode: Boolean = false): String =
        CurrencyFormatting.string(minorUnits, currencyCode, showsSign, showsCurrencyCode)

    /**
     * Magnitude only, for places where the surrounding copy carries the sign
     * ("you owe" / "owes you") rather than a minus glyph.
     */
    fun formattedAbsolute(showsCurrencyCode: Boolean = false): String =
        magnitude.formatted(showsCurrencyCode = showsCurrencyCode)

    companion object {
        fun zero(currencyCode: String) = Money(0, currencyCode)

        fun fromDecimal(amount: BigDecimal, currencyCode: String): Money {
            val scale = Currencies.fractionDigits(currencyCode)
            // HALF_EVEN matches the banker's rounding the iOS app uses.
            val scaled = amount.movePointRight(scale).setScale(0, RoundingMode.HALF_EVEN)
            return Money(scaled.toLong(), currencyCode)
        }
    }
}

object CurrencyFormatting {

    // NumberFormat construction is expensive and these are reused constantly.
    private val cache = ConcurrentHashMap<String, NumberFormat>()

    fun string(
        minorUnits: Long,
        currencyCode: String,
        showsSign: Boolean = false,
        showsCurrencyCode: Boolean = false,
    ): String {
        val formatter = formatter(currencyCode, showsCurrencyCode)
        val digits = Currencies.fractionDigits(currencyCode)
        val value = BigDecimal(minorUnits).movePointLeft(digits)
        val base = formatter.format(value)
        return if (showsSign && minorUnits > 0) "+$base" else base
    }

    private fun formatter(currencyCode: String, showsCurrencyCode: Boolean): NumberFormat =
        cache.getOrPut("$currencyCode|$showsCurrencyCode") {
            val digits = Currencies.fractionDigits(currencyCode)
            val format = NumberFormat.getCurrencyInstance(Locale.getDefault())
            runCatching {
                format.currency = java.util.Currency.getInstance(currencyCode)
            }
            format.minimumFractionDigits = digits
            format.maximumFractionDigits = digits
            if (format is java.text.DecimalFormat) {
                val symbols = format.decimalFormatSymbols
                // Java only knows the symbols for currencies it ships; fall back
                // to our own table so every one of the 154 renders sensibly.
                symbols.currencySymbol =
                    if (showsCurrencyCode) currencyCode.uppercase() else Currencies.symbol(currencyCode)
                format.decimalFormatSymbols = symbols
            }
            format
        }

    /** Parses free-typed input ("12.50", "1 234,56", "$8") into minor units. */
    fun parse(text: String, currencyCode: String): Long? {
        val stripped = text.filter { it.isDigit() || it == '.' || it == ',' || it == '-' }
        if (stripped.isEmpty()) return null

        // Whichever separator comes last is the decimal separator; the other groups.
        val lastDot = stripped.lastIndexOf('.')
        val lastComma = stripped.lastIndexOf(',')
        val normalized = when {
            lastDot >= 0 && lastComma >= 0 ->
                if (lastDot > lastComma) stripped.replace(",", "")
                else stripped.replace(".", "").replace(',', '.')
            lastComma >= 0 -> stripped.replace(',', '.')
            else -> stripped
        }

        val decimal = normalized.toBigDecimalOrNull() ?: return null
        return Money.fromDecimal(decimal, currencyCode).minorUnits
    }

    fun symbol(currencyCode: String): String = Currencies.symbol(currencyCode)
}
