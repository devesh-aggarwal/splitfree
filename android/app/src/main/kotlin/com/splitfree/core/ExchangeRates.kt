package com.splitfree.core

import kotlinx.serialization.Serializable
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToLong

/** A set of exchange rates quoted against a single base currency. */
@Serializable
data class ExchangeRateTable(
    val baseCode: String,
    /** Currency code to units of that currency per 1 unit of [baseCode]. */
    val rates: Map<String, Double>,
    /** Epoch millis. Zero means the bundled snapshot, never fetched. */
    val fetchedAtMillis: Long,
    /** True when these came from the bundled snapshot rather than the network. */
    val isOffline: Boolean,
) {

    fun rate(from: String, to: String): Double? {
        val f = from.uppercase()
        val t = to.uppercase()
        if (f == t) return 1.0
        val fromRate = rates[f] ?: return null
        val toRate = rates[t] ?: return null
        if (fromRate <= 0) return null
        // Both are quoted against the base, so cross-rate through the base.
        return toRate / fromRate
    }

    /**
     * Converts between currencies, respecting each one's minor-unit precision.
     * Returns 0 when we have no rate, rather than guessing.
     */
    fun convert(minorUnits: Long, from: String, to: String): Long {
        if (from.uppercase() == to.uppercase()) return minorUnits
        val rate = rate(from, to) ?: return 0
        val fromDigits = Currencies.fractionDigits(from)
        val toDigits = Currencies.fractionDigits(to)
        val major = minorUnits / 10.0.pow(fromDigits)
        return (major * rate * 10.0.pow(toDigits)).roundToLong()
    }

    companion object {
        /**
         * Approximate rates shipped with the app so conversion always works
         * offline. These are a snapshot, not live quotes. The UI labels them as
         * such and any successful refresh replaces them.
         *
         * Generated from the iOS app's bundled table so both stay in step.
         */
        val bundled = ExchangeRateTable(
            baseCode = "USD",
            rates = buildMap {
                put("USD", 1.0)
                put("EUR", 0.92)
                put("GBP", 0.79)
                put("JPY", 152.0)
                put("CNY", 7.24)
                put("INR", 83.4)
                put("CAD", 1.36)
                put("AUD", 1.52)
                put("CHF", 0.90)
                put("HKD", 7.82)
                put("SGD", 1.35)
                put("NZD", 1.65)
                put("SEK", 10.6)
                put("NOK", 10.8)
                put("DKK", 6.87)
                put("PLN", 4.02)
                put("CZK", 23.2)
                put("HUF", 360.0)
                put("RON", 4.58)
                put("BGN", 1.80)
                put("TRY", 32.3)
                put("RUB", 92.0)
                put("UAH", 39.5)
                put("ILS", 3.72)
                put("AED", 3.67)
                put("SAR", 3.75)
                put("QAR", 3.64)
                put("KWD", 0.308)
                put("BHD", 0.376)
                put("OMR", 0.385)
                put("JOD", 0.709)
                put("EGP", 47.5)
                put("ZAR", 18.7)
                put("NGN", 1450.0)
                put("KES", 132.0)
                put("GHS", 13.2)
                put("MAD", 10.0)
                put("TND", 3.12)
                put("DZD", 134.0)
                put("ETB", 57.0)
                put("TZS", 2600.0)
                put("UGX", 3800.0)
                put("XOF", 604.0)
                put("XAF", 604.0)
                put("BRL", 5.05)
                put("MXN", 17.0)
                put("ARS", 870.0)
                put("CLP", 950.0)
                put("COP", 3900.0)
                put("PEN", 3.72)
                put("UYU", 39.0)
                put("BOB", 6.91)
                put("PYG", 7300.0)
                put("VES", 36.0)
                put("KRW", 1340.0)
                put("TWD", 32.0)
                put("THB", 36.2)
                put("VND", 24800.0)
                put("IDR", 15700.0)
                put("MYR", 4.72)
                put("PHP", 56.2)
                put("PKR", 278.0)
                put("BDT", 110.0)
                put("LKR", 305.0)
                put("NPR", 133.0)
                put("MMK", 2100.0)
                put("KHR", 4100.0)
                put("LAK", 20800.0)
                put("MNT", 3400.0)
                put("KZT", 450.0)
                put("UZS", 12600.0)
                put("AZN", 1.70)
                put("GEL", 2.65)
                put("AMD", 388.0)
                put("BYN", 3.27)
                put("MDL", 17.7)
                put("RSD", 108.0)
                put("MKD", 56.6)
                put("BAM", 1.80)
                put("ISK", 138.0)
                put("HRK", 6.93)
                put("ALL", 94.0)
                put("DOP", 58.5)
                put("GTQ", 7.80)
                put("CRC", 510.0)
                put("HNL", 24.7)
                put("NIO", 36.8)
                put("PAB", 1.0)
                put("JMD", 155.0)
                put("TTD", 6.78)
                put("BBD", 2.0)
                put("BSD", 1.0)
                put("BZD", 2.0)
                put("XCD", 2.70)
                put("AWG", 1.79)
                put("ANG", 1.79)
                put("CUP", 24.0)
                put("HTG", 132.0)
                put("GYD", 209.0)
                put("SRD", 35.0)
                put("SVC", 8.75)
                put("CVE", 101.0)
                put("FJD", 2.25)
                put("PGK", 3.80)
                put("SBD", 8.45)
                put("TOP", 2.35)
                put("VUV", 119.0)
                put("WST", 2.72)
                put("XPF", 110.0)
                put("BND", 1.35)
                put("MOP", 8.05)
                put("AFN", 72.0)
                put("IRR", 42000.0)
                put("IQD", 1310.0)
                put("LBP", 89500.0)
                put("SYP", 13000.0)
                put("YER", 250.0)
                put("LYD", 4.85)
                put("SDG", 601.0)
                put("SSP", 1300.0)
                put("ERN", 15.0)
                put("DJF", 178.0)
                put("SOS", 571.0)
                put("RWF", 1300.0)
                put("BIF", 2860.0)
                put("KMF", 452.0)
                put("MGA", 4500.0)
                put("MUR", 46.5)
                put("SCR", 13.5)
                put("MVR", 15.4)
                put("BTN", 83.4)
                put("MWK", 1730.0)
                put("ZMW", 26.0)
                put("ZWL", 25.0)
                put("BWP", 13.7)
                put("NAD", 18.7)
                put("LSL", 18.7)
                put("SZL", 18.7)
                put("MZN", 63.9)
                put("AOA", 850.0)
                put("CDF", 2800.0)
                put("GMD", 67.0)
                put("GNF", 8600.0)
                put("LRD", 194.0)
                put("SLE", 22.7)
                put("STN", 22.5)
                put("TJS", 10.9)
                put("TMT", 3.50)
                put("KGS", 89.0)
                put("FKP", 0.79)
                put("GIP", 0.79)
                put("SHP", 0.79)
                put("BMD", 1.0)
                put("KYD", 0.83)
            },
            fetchedAtMillis = 0L,
            isOffline = true,
        )
    }
}
