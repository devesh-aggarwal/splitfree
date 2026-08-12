package com.splitfree.core

/**
 * One ISO 4217 currency.
 *
 * This table is generated from the iOS app's `Core/Currency.swift` so the two
 * platforms agree on every code, symbol and minor-unit precision. If they
 * disagreed, the same expense would round differently on each phone.
 */
data class Currency(
    val code: String,
    val name: String,
    val symbol: String,
    val fractionDigits: Int,
    val flag: String,
) {
    val searchText: String get() = "$name $code $symbol".lowercase()
}

object Currencies {

    /** 154 currencies, with the zero- and three-decimal ones marked correctly. */
    val catalog: List<Currency> = listOf(
        Currency("AED", "UAE Dirham", "د.إ", 2, "🇦🇪"),
        Currency("AFN", "Afghan Afghani", "؋", 2, "🇦🇫"),
        Currency("ALL", "Albanian Lek", "L", 2, "🇦🇱"),
        Currency("AMD", "Armenian Dram", "֏", 2, "🇦🇲"),
        Currency("ANG", "Netherlands Antillean Guilder", "ƒ", 2, "🇨🇼"),
        Currency("AOA", "Angolan Kwanza", "Kz", 2, "🇦🇴"),
        Currency("ARS", "Argentine Peso", "\$", 2, "🇦🇷"),
        Currency("AUD", "Australian Dollar", "A\$", 2, "🇦🇺"),
        Currency("AWG", "Aruban Florin", "ƒ", 2, "🇦🇼"),
        Currency("AZN", "Azerbaijani Manat", "₼", 2, "🇦🇿"),
        Currency("BAM", "Bosnia-Herzegovina Mark", "KM", 2, "🇧🇦"),
        Currency("BBD", "Barbadian Dollar", "\$", 2, "🇧🇧"),
        Currency("BDT", "Bangladeshi Taka", "৳", 2, "🇧🇩"),
        Currency("BGN", "Bulgarian Lev", "лв", 2, "🇧🇬"),
        Currency("BHD", "Bahraini Dinar", ".د.ب", 3, "🇧🇭"),
        Currency("BIF", "Burundian Franc", "FBu", 0, "🇧🇮"),
        Currency("BMD", "Bermudan Dollar", "\$", 2, "🇧🇲"),
        Currency("BND", "Brunei Dollar", "\$", 2, "🇧🇳"),
        Currency("BOB", "Bolivian Boliviano", "Bs", 2, "🇧🇴"),
        Currency("BRL", "Brazilian Real", "R\$", 2, "🇧🇷"),
        Currency("BSD", "Bahamian Dollar", "\$", 2, "🇧🇸"),
        Currency("BTN", "Bhutanese Ngultrum", "Nu.", 2, "🇧🇹"),
        Currency("BWP", "Botswanan Pula", "P", 2, "🇧🇼"),
        Currency("BYN", "Belarusian Ruble", "Br", 2, "🇧🇾"),
        Currency("BZD", "Belize Dollar", "\$", 2, "🇧🇿"),
        Currency("CAD", "Canadian Dollar", "C\$", 2, "🇨🇦"),
        Currency("CDF", "Congolese Franc", "FC", 2, "🇨🇩"),
        Currency("CHF", "Swiss Franc", "CHF", 2, "🇨🇭"),
        Currency("CLP", "Chilean Peso", "\$", 0, "🇨🇱"),
        Currency("CNY", "Chinese Yuan", "¥", 2, "🇨🇳"),
        Currency("COP", "Colombian Peso", "\$", 2, "🇨🇴"),
        Currency("CRC", "Costa Rican Colón", "₡", 2, "🇨🇷"),
        Currency("CUP", "Cuban Peso", "\$", 2, "🇨🇺"),
        Currency("CVE", "Cape Verdean Escudo", "\$", 2, "🇨🇻"),
        Currency("CZK", "Czech Koruna", "Kč", 2, "🇨🇿"),
        Currency("DJF", "Djiboutian Franc", "Fdj", 0, "🇩🇯"),
        Currency("DKK", "Danish Krone", "kr", 2, "🇩🇰"),
        Currency("DOP", "Dominican Peso", "\$", 2, "🇩🇴"),
        Currency("DZD", "Algerian Dinar", "د.ج", 2, "🇩🇿"),
        Currency("EGP", "Egyptian Pound", "£", 2, "🇪🇬"),
        Currency("ERN", "Eritrean Nakfa", "Nfk", 2, "🇪🇷"),
        Currency("ETB", "Ethiopian Birr", "Br", 2, "🇪🇹"),
        Currency("EUR", "Euro", "€", 2, "🇪🇺"),
        Currency("FJD", "Fijian Dollar", "\$", 2, "🇫🇯"),
        Currency("FKP", "Falkland Islands Pound", "£", 2, "🇫🇰"),
        Currency("GBP", "British Pound", "£", 2, "🇬🇧"),
        Currency("GEL", "Georgian Lari", "₾", 2, "🇬🇪"),
        Currency("GHS", "Ghanaian Cedi", "₵", 2, "🇬🇭"),
        Currency("GIP", "Gibraltar Pound", "£", 2, "🇬🇮"),
        Currency("GMD", "Gambian Dalasi", "D", 2, "🇬🇲"),
        Currency("GNF", "Guinean Franc", "FG", 0, "🇬🇳"),
        Currency("GTQ", "Guatemalan Quetzal", "Q", 2, "🇬🇹"),
        Currency("GYD", "Guyanaese Dollar", "\$", 2, "🇬🇾"),
        Currency("HKD", "Hong Kong Dollar", "HK\$", 2, "🇭🇰"),
        Currency("HNL", "Honduran Lempira", "L", 2, "🇭🇳"),
        Currency("HRK", "Croatian Kuna", "kn", 2, "🇭🇷"),
        Currency("HTG", "Haitian Gourde", "G", 2, "🇭🇹"),
        Currency("HUF", "Hungarian Forint", "Ft", 2, "🇭🇺"),
        Currency("IDR", "Indonesian Rupiah", "Rp", 2, "🇮🇩"),
        Currency("ILS", "Israeli New Shekel", "₪", 2, "🇮🇱"),
        Currency("INR", "Indian Rupee", "₹", 2, "🇮🇳"),
        Currency("IQD", "Iraqi Dinar", "ع.د", 3, "🇮🇶"),
        Currency("IRR", "Iranian Rial", "﷼", 2, "🇮🇷"),
        Currency("ISK", "Icelandic Króna", "kr", 0, "🇮🇸"),
        Currency("JMD", "Jamaican Dollar", "\$", 2, "🇯🇲"),
        Currency("JOD", "Jordanian Dinar", "د.ا", 3, "🇯🇴"),
        Currency("JPY", "Japanese Yen", "¥", 0, "🇯🇵"),
        Currency("KES", "Kenyan Shilling", "KSh", 2, "🇰🇪"),
        Currency("KGS", "Kyrgystani Som", "с", 2, "🇰🇬"),
        Currency("KHR", "Cambodian Riel", "៛", 2, "🇰🇭"),
        Currency("KMF", "Comorian Franc", "CF", 0, "🇰🇲"),
        Currency("KRW", "South Korean Won", "₩", 0, "🇰🇷"),
        Currency("KWD", "Kuwaiti Dinar", "د.ك", 3, "🇰🇼"),
        Currency("KYD", "Cayman Islands Dollar", "\$", 2, "🇰🇾"),
        Currency("KZT", "Kazakhstani Tenge", "₸", 2, "🇰🇿"),
        Currency("LAK", "Laotian Kip", "₭", 2, "🇱🇦"),
        Currency("LBP", "Lebanese Pound", "ل.ل", 2, "🇱🇧"),
        Currency("LKR", "Sri Lankan Rupee", "Rs", 2, "🇱🇰"),
        Currency("LRD", "Liberian Dollar", "\$", 2, "🇱🇷"),
        Currency("LSL", "Lesotho Loti", "L", 2, "🇱🇸"),
        Currency("LYD", "Libyan Dinar", "ل.د", 3, "🇱🇾"),
        Currency("MAD", "Moroccan Dirham", "د.م.", 2, "🇲🇦"),
        Currency("MDL", "Moldovan Leu", "L", 2, "🇲🇩"),
        Currency("MGA", "Malagasy Ariary", "Ar", 0, "🇲🇬"),
        Currency("MKD", "Macedonian Denar", "ден", 2, "🇲🇰"),
        Currency("MMK", "Myanmar Kyat", "K", 2, "🇲🇲"),
        Currency("MNT", "Mongolian Tugrik", "₮", 2, "🇲🇳"),
        Currency("MOP", "Macanese Pataca", "MOP\$", 2, "🇲🇴"),
        Currency("MUR", "Mauritian Rupee", "₨", 2, "🇲🇺"),
        Currency("MVR", "Maldivian Rufiyaa", ".ރ", 2, "🇲🇻"),
        Currency("MWK", "Malawian Kwacha", "MK", 2, "🇲🇼"),
        Currency("MXN", "Mexican Peso", "\$", 2, "🇲🇽"),
        Currency("MYR", "Malaysian Ringgit", "RM", 2, "🇲🇾"),
        Currency("MZN", "Mozambican Metical", "MT", 2, "🇲🇿"),
        Currency("NAD", "Namibian Dollar", "\$", 2, "🇳🇦"),
        Currency("NGN", "Nigerian Naira", "₦", 2, "🇳🇬"),
        Currency("NIO", "Nicaraguan Córdoba", "C\$", 2, "🇳🇮"),
        Currency("NOK", "Norwegian Krone", "kr", 2, "🇳🇴"),
        Currency("NPR", "Nepalese Rupee", "₨", 2, "🇳🇵"),
        Currency("NZD", "New Zealand Dollar", "NZ\$", 2, "🇳🇿"),
        Currency("OMR", "Omani Rial", "ر.ع.", 3, "🇴🇲"),
        Currency("PAB", "Panamanian Balboa", "B/.", 2, "🇵🇦"),
        Currency("PEN", "Peruvian Sol", "S/", 2, "🇵🇪"),
        Currency("PGK", "Papua New Guinean Kina", "K", 2, "🇵🇬"),
        Currency("PHP", "Philippine Peso", "₱", 2, "🇵🇭"),
        Currency("PKR", "Pakistani Rupee", "₨", 2, "🇵🇰"),
        Currency("PLN", "Polish Złoty", "zł", 2, "🇵🇱"),
        Currency("PYG", "Paraguayan Guarani", "₲", 0, "🇵🇾"),
        Currency("QAR", "Qatari Rial", "ر.ق", 2, "🇶🇦"),
        Currency("RON", "Romanian Leu", "lei", 2, "🇷🇴"),
        Currency("RSD", "Serbian Dinar", "дин", 2, "🇷🇸"),
        Currency("RUB", "Russian Ruble", "₽", 2, "🇷🇺"),
        Currency("RWF", "Rwandan Franc", "FRw", 0, "🇷🇼"),
        Currency("SAR", "Saudi Riyal", "ر.س", 2, "🇸🇦"),
        Currency("SBD", "Solomon Islands Dollar", "\$", 2, "🇸🇧"),
        Currency("SCR", "Seychellois Rupee", "₨", 2, "🇸🇨"),
        Currency("SDG", "Sudanese Pound", "ج.س.", 2, "🇸🇩"),
        Currency("SEK", "Swedish Krona", "kr", 2, "🇸🇪"),
        Currency("SGD", "Singapore Dollar", "S\$", 2, "🇸🇬"),
        Currency("SHP", "St. Helena Pound", "£", 2, "🇸🇭"),
        Currency("SLE", "Sierra Leonean Leone", "Le", 2, "🇸🇱"),
        Currency("SOS", "Somali Shilling", "S", 2, "🇸🇴"),
        Currency("SRD", "Surinamese Dollar", "\$", 2, "🇸🇷"),
        Currency("SSP", "South Sudanese Pound", "£", 2, "🇸🇸"),
        Currency("STN", "São Tomé & Príncipe Dobra", "Db", 2, "🇸🇹"),
        Currency("SVC", "Salvadoran Colón", "₡", 2, "🇸🇻"),
        Currency("SYP", "Syrian Pound", "£", 2, "🇸🇾"),
        Currency("SZL", "Swazi Lilangeni", "E", 2, "🇸🇿"),
        Currency("THB", "Thai Baht", "฿", 2, "🇹🇭"),
        Currency("TJS", "Tajikistani Somoni", "SM", 2, "🇹🇯"),
        Currency("TMT", "Turkmenistani Manat", "m", 2, "🇹🇲"),
        Currency("TND", "Tunisian Dinar", "د.ت", 3, "🇹🇳"),
        Currency("TOP", "Tongan Paʻanga", "T\$", 2, "🇹🇴"),
        Currency("TRY", "Turkish Lira", "₺", 2, "🇹🇷"),
        Currency("TTD", "Trinidad & Tobago Dollar", "\$", 2, "🇹🇹"),
        Currency("TWD", "New Taiwan Dollar", "NT\$", 2, "🇹🇼"),
        Currency("TZS", "Tanzanian Shilling", "TSh", 2, "🇹🇿"),
        Currency("UAH", "Ukrainian Hryvnia", "₴", 2, "🇺🇦"),
        Currency("UGX", "Ugandan Shilling", "USh", 0, "🇺🇬"),
        Currency("USD", "US Dollar", "\$", 2, "🇺🇸"),
        Currency("UYU", "Uruguayan Peso", "\$U", 2, "🇺🇾"),
        Currency("UZS", "Uzbekistani Som", "so'm", 2, "🇺🇿"),
        Currency("VES", "Venezuelan Bolívar", "Bs.", 2, "🇻🇪"),
        Currency("VND", "Vietnamese Dong", "₫", 0, "🇻🇳"),
        Currency("VUV", "Vanuatu Vatu", "VT", 0, "🇻🇺"),
        Currency("WST", "Samoan Tala", "T", 2, "🇼🇸"),
        Currency("XAF", "Central African CFA Franc", "FCFA", 0, "🌍"),
        Currency("XCD", "East Caribbean Dollar", "\$", 2, "🌎"),
        Currency("XOF", "West African CFA Franc", "CFA", 0, "🌍"),
        Currency("XPF", "CFP Franc", "₣", 0, "🇵🇫"),
        Currency("YER", "Yemeni Rial", "﷼", 2, "🇾🇪"),
        Currency("ZAR", "South African Rand", "R", 2, "🇿🇦"),
        Currency("ZMW", "Zambian Kwacha", "ZK", 2, "🇿🇲"),
        Currency("ZWL", "Zimbabwean Dollar", "Z\$", 2, "🇿🇼"),
    )

    private val byCode: Map<String, Currency> = catalog.associateBy { it.code }

    fun fractionDigits(code: String): Int = byCode[code.uppercase()]?.fractionDigits ?: 2

    fun symbol(code: String): String = byCode[code.uppercase()]?.symbol ?: code.uppercase()

    fun name(code: String): String = byCode[code.uppercase()]?.name ?: code.uppercase()

    fun flag(code: String): String = byCode[code.uppercase()]?.flag ?: "\uD83C\uDFF3\uFE0F"

    fun exists(code: String): Boolean = byCode.containsKey(code.uppercase())

    fun currency(code: String): Currency =
        byCode[code.uppercase()] ?: Currency(code.uppercase(), code.uppercase(), code.uppercase(), 2, "\uD83C\uDFF3\uFE0F")

    fun search(query: String): List<Currency> {
        val trimmed = query.trim().lowercase()
        if (trimmed.isEmpty()) return catalog
        return catalog.filter { it.searchText.contains(trimmed) }
    }

    /** The device's currency when we support it, otherwise USD. */
    fun deviceDefault(): String {
        val code = runCatching {
            java.util.Currency.getInstance(java.util.Locale.getDefault()).currencyCode
        }.getOrNull()?.uppercase() ?: "USD"
        return if (exists(code)) code else "USD"
    }

    /** Currencies the person is most likely to want, floated to the top of pickers. */
    fun suggested(recent: List<String>): List<String> {
        val seen = LinkedHashSet<String>()
        for (code in listOf(deviceDefault()) + recent + listOf("USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD")) {
            val upper = code.uppercase()
            if (exists(upper)) seen.add(upper)
        }
        return seen.take(8)
    }
}
