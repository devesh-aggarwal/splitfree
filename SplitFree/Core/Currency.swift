import Foundation

/// A single ISO 4217 currency.
struct Currency: Identifiable, Hashable, Sendable {
    var code: String
    var name: String
    var symbol: String
    var fractionDigits: Int
    /// Rough country/region flags for the picker. Empty when the currency spans regions.
    var flag: String

    var id: String { code }

    /// "US Dollar (USD)" — used for accessibility labels and search.
    var searchText: String { "\(name) \(code) \(symbol)".lowercased() }
}

extension Currency {
    static func fractionDigits(for code: String) -> Int {
        catalogByCode[code.uppercased()]?.fractionDigits ?? 2
    }

    static func symbol(for code: String) -> String {
        catalogByCode[code.uppercased()]?.symbol ?? code.uppercased()
    }

    static func name(for code: String) -> String {
        catalogByCode[code.uppercased()]?.name
            ?? Locale.autoupdatingCurrent.localizedString(forCurrencyCode: code)
            ?? code.uppercased()
    }

    static func flag(for code: String) -> String {
        catalogByCode[code.uppercased()]?.flag ?? "🏳️"
    }

    static func currency(for code: String) -> Currency {
        catalogByCode[code.uppercased()]
            ?? Currency(code: code.uppercased(), name: name(for: code), symbol: code.uppercased(), fractionDigits: 2, flag: "🏳️")
    }

    static func exists(_ code: String) -> Bool {
        catalogByCode[code.uppercased()] != nil
    }

    /// The device's currency if we support it, otherwise USD.
    static var deviceDefaultCode: String {
        let code = Locale.autoupdatingCurrent.currency?.identifier.uppercased() ?? "USD"
        return exists(code) ? code : "USD"
    }

    static func search(_ query: String) -> [Currency] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return catalog }
        return catalog.filter { $0.searchText.contains(trimmed) }
    }

    /// Currencies the person is most likely to want, floated to the top of pickers.
    static func suggestedCodes(recent: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for code in [deviceDefaultCode] + recent + ["USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD"] {
            let upper = code.uppercased()
            guard exists(upper), seen.insert(upper).inserted else { continue }
            result.append(upper)
        }
        return Array(result.prefix(8))
    }

    static let catalogByCode: [String: Currency] = {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.code, $0) })
    }()

    /// 160 ISO 4217 currencies with correct minor-unit precision.
    /// Zero-decimal (JPY, KRW, VND, CLP, …) and three-decimal (BHD, KWD, TND, …)
    /// currencies are marked so `Money` never invents fractional yen.
    static let catalog: [Currency] = [
        Currency(code: "AED", name: "UAE Dirham", symbol: "د.إ", fractionDigits: 2, flag: "🇦🇪"),
        Currency(code: "AFN", name: "Afghan Afghani", symbol: "؋", fractionDigits: 2, flag: "🇦🇫"),
        Currency(code: "ALL", name: "Albanian Lek", symbol: "L", fractionDigits: 2, flag: "🇦🇱"),
        Currency(code: "AMD", name: "Armenian Dram", symbol: "֏", fractionDigits: 2, flag: "🇦🇲"),
        Currency(code: "ANG", name: "Netherlands Antillean Guilder", symbol: "ƒ", fractionDigits: 2, flag: "🇨🇼"),
        Currency(code: "AOA", name: "Angolan Kwanza", symbol: "Kz", fractionDigits: 2, flag: "🇦🇴"),
        Currency(code: "ARS", name: "Argentine Peso", symbol: "$", fractionDigits: 2, flag: "🇦🇷"),
        Currency(code: "AUD", name: "Australian Dollar", symbol: "A$", fractionDigits: 2, flag: "🇦🇺"),
        Currency(code: "AWG", name: "Aruban Florin", symbol: "ƒ", fractionDigits: 2, flag: "🇦🇼"),
        Currency(code: "AZN", name: "Azerbaijani Manat", symbol: "₼", fractionDigits: 2, flag: "🇦🇿"),
        Currency(code: "BAM", name: "Bosnia-Herzegovina Mark", symbol: "KM", fractionDigits: 2, flag: "🇧🇦"),
        Currency(code: "BBD", name: "Barbadian Dollar", symbol: "$", fractionDigits: 2, flag: "🇧🇧"),
        Currency(code: "BDT", name: "Bangladeshi Taka", symbol: "৳", fractionDigits: 2, flag: "🇧🇩"),
        Currency(code: "BGN", name: "Bulgarian Lev", symbol: "лв", fractionDigits: 2, flag: "🇧🇬"),
        Currency(code: "BHD", name: "Bahraini Dinar", symbol: ".د.ب", fractionDigits: 3, flag: "🇧🇭"),
        Currency(code: "BIF", name: "Burundian Franc", symbol: "FBu", fractionDigits: 0, flag: "🇧🇮"),
        Currency(code: "BMD", name: "Bermudan Dollar", symbol: "$", fractionDigits: 2, flag: "🇧🇲"),
        Currency(code: "BND", name: "Brunei Dollar", symbol: "$", fractionDigits: 2, flag: "🇧🇳"),
        Currency(code: "BOB", name: "Bolivian Boliviano", symbol: "Bs", fractionDigits: 2, flag: "🇧🇴"),
        Currency(code: "BRL", name: "Brazilian Real", symbol: "R$", fractionDigits: 2, flag: "🇧🇷"),
        Currency(code: "BSD", name: "Bahamian Dollar", symbol: "$", fractionDigits: 2, flag: "🇧🇸"),
        Currency(code: "BTN", name: "Bhutanese Ngultrum", symbol: "Nu.", fractionDigits: 2, flag: "🇧🇹"),
        Currency(code: "BWP", name: "Botswanan Pula", symbol: "P", fractionDigits: 2, flag: "🇧🇼"),
        Currency(code: "BYN", name: "Belarusian Ruble", symbol: "Br", fractionDigits: 2, flag: "🇧🇾"),
        Currency(code: "BZD", name: "Belize Dollar", symbol: "$", fractionDigits: 2, flag: "🇧🇿"),
        Currency(code: "CAD", name: "Canadian Dollar", symbol: "C$", fractionDigits: 2, flag: "🇨🇦"),
        Currency(code: "CDF", name: "Congolese Franc", symbol: "FC", fractionDigits: 2, flag: "🇨🇩"),
        Currency(code: "CHF", name: "Swiss Franc", symbol: "CHF", fractionDigits: 2, flag: "🇨🇭"),
        Currency(code: "CLP", name: "Chilean Peso", symbol: "$", fractionDigits: 0, flag: "🇨🇱"),
        Currency(code: "CNY", name: "Chinese Yuan", symbol: "¥", fractionDigits: 2, flag: "🇨🇳"),
        Currency(code: "COP", name: "Colombian Peso", symbol: "$", fractionDigits: 2, flag: "🇨🇴"),
        Currency(code: "CRC", name: "Costa Rican Colón", symbol: "₡", fractionDigits: 2, flag: "🇨🇷"),
        Currency(code: "CUP", name: "Cuban Peso", symbol: "$", fractionDigits: 2, flag: "🇨🇺"),
        Currency(code: "CVE", name: "Cape Verdean Escudo", symbol: "$", fractionDigits: 2, flag: "🇨🇻"),
        Currency(code: "CZK", name: "Czech Koruna", symbol: "Kč", fractionDigits: 2, flag: "🇨🇿"),
        Currency(code: "DJF", name: "Djiboutian Franc", symbol: "Fdj", fractionDigits: 0, flag: "🇩🇯"),
        Currency(code: "DKK", name: "Danish Krone", symbol: "kr", fractionDigits: 2, flag: "🇩🇰"),
        Currency(code: "DOP", name: "Dominican Peso", symbol: "$", fractionDigits: 2, flag: "🇩🇴"),
        Currency(code: "DZD", name: "Algerian Dinar", symbol: "د.ج", fractionDigits: 2, flag: "🇩🇿"),
        Currency(code: "EGP", name: "Egyptian Pound", symbol: "£", fractionDigits: 2, flag: "🇪🇬"),
        Currency(code: "ERN", name: "Eritrean Nakfa", symbol: "Nfk", fractionDigits: 2, flag: "🇪🇷"),
        Currency(code: "ETB", name: "Ethiopian Birr", symbol: "Br", fractionDigits: 2, flag: "🇪🇹"),
        Currency(code: "EUR", name: "Euro", symbol: "€", fractionDigits: 2, flag: "🇪🇺"),
        Currency(code: "FJD", name: "Fijian Dollar", symbol: "$", fractionDigits: 2, flag: "🇫🇯"),
        Currency(code: "FKP", name: "Falkland Islands Pound", symbol: "£", fractionDigits: 2, flag: "🇫🇰"),
        Currency(code: "GBP", name: "British Pound", symbol: "£", fractionDigits: 2, flag: "🇬🇧"),
        Currency(code: "GEL", name: "Georgian Lari", symbol: "₾", fractionDigits: 2, flag: "🇬🇪"),
        Currency(code: "GHS", name: "Ghanaian Cedi", symbol: "₵", fractionDigits: 2, flag: "🇬🇭"),
        Currency(code: "GIP", name: "Gibraltar Pound", symbol: "£", fractionDigits: 2, flag: "🇬🇮"),
        Currency(code: "GMD", name: "Gambian Dalasi", symbol: "D", fractionDigits: 2, flag: "🇬🇲"),
        Currency(code: "GNF", name: "Guinean Franc", symbol: "FG", fractionDigits: 0, flag: "🇬🇳"),
        Currency(code: "GTQ", name: "Guatemalan Quetzal", symbol: "Q", fractionDigits: 2, flag: "🇬🇹"),
        Currency(code: "GYD", name: "Guyanaese Dollar", symbol: "$", fractionDigits: 2, flag: "🇬🇾"),
        Currency(code: "HKD", name: "Hong Kong Dollar", symbol: "HK$", fractionDigits: 2, flag: "🇭🇰"),
        Currency(code: "HNL", name: "Honduran Lempira", symbol: "L", fractionDigits: 2, flag: "🇭🇳"),
        Currency(code: "HRK", name: "Croatian Kuna", symbol: "kn", fractionDigits: 2, flag: "🇭🇷"),
        Currency(code: "HTG", name: "Haitian Gourde", symbol: "G", fractionDigits: 2, flag: "🇭🇹"),
        Currency(code: "HUF", name: "Hungarian Forint", symbol: "Ft", fractionDigits: 2, flag: "🇭🇺"),
        Currency(code: "IDR", name: "Indonesian Rupiah", symbol: "Rp", fractionDigits: 2, flag: "🇮🇩"),
        Currency(code: "ILS", name: "Israeli New Shekel", symbol: "₪", fractionDigits: 2, flag: "🇮🇱"),
        Currency(code: "INR", name: "Indian Rupee", symbol: "₹", fractionDigits: 2, flag: "🇮🇳"),
        Currency(code: "IQD", name: "Iraqi Dinar", symbol: "ع.د", fractionDigits: 3, flag: "🇮🇶"),
        Currency(code: "IRR", name: "Iranian Rial", symbol: "﷼", fractionDigits: 2, flag: "🇮🇷"),
        Currency(code: "ISK", name: "Icelandic Króna", symbol: "kr", fractionDigits: 0, flag: "🇮🇸"),
        Currency(code: "JMD", name: "Jamaican Dollar", symbol: "$", fractionDigits: 2, flag: "🇯🇲"),
        Currency(code: "JOD", name: "Jordanian Dinar", symbol: "د.ا", fractionDigits: 3, flag: "🇯🇴"),
        Currency(code: "JPY", name: "Japanese Yen", symbol: "¥", fractionDigits: 0, flag: "🇯🇵"),
        Currency(code: "KES", name: "Kenyan Shilling", symbol: "KSh", fractionDigits: 2, flag: "🇰🇪"),
        Currency(code: "KGS", name: "Kyrgystani Som", symbol: "с", fractionDigits: 2, flag: "🇰🇬"),
        Currency(code: "KHR", name: "Cambodian Riel", symbol: "៛", fractionDigits: 2, flag: "🇰🇭"),
        Currency(code: "KMF", name: "Comorian Franc", symbol: "CF", fractionDigits: 0, flag: "🇰🇲"),
        Currency(code: "KRW", name: "South Korean Won", symbol: "₩", fractionDigits: 0, flag: "🇰🇷"),
        Currency(code: "KWD", name: "Kuwaiti Dinar", symbol: "د.ك", fractionDigits: 3, flag: "🇰🇼"),
        Currency(code: "KYD", name: "Cayman Islands Dollar", symbol: "$", fractionDigits: 2, flag: "🇰🇾"),
        Currency(code: "KZT", name: "Kazakhstani Tenge", symbol: "₸", fractionDigits: 2, flag: "🇰🇿"),
        Currency(code: "LAK", name: "Laotian Kip", symbol: "₭", fractionDigits: 2, flag: "🇱🇦"),
        Currency(code: "LBP", name: "Lebanese Pound", symbol: "ل.ل", fractionDigits: 2, flag: "🇱🇧"),
        Currency(code: "LKR", name: "Sri Lankan Rupee", symbol: "Rs", fractionDigits: 2, flag: "🇱🇰"),
        Currency(code: "LRD", name: "Liberian Dollar", symbol: "$", fractionDigits: 2, flag: "🇱🇷"),
        Currency(code: "LSL", name: "Lesotho Loti", symbol: "L", fractionDigits: 2, flag: "🇱🇸"),
        Currency(code: "LYD", name: "Libyan Dinar", symbol: "ل.د", fractionDigits: 3, flag: "🇱🇾"),
        Currency(code: "MAD", name: "Moroccan Dirham", symbol: "د.م.", fractionDigits: 2, flag: "🇲🇦"),
        Currency(code: "MDL", name: "Moldovan Leu", symbol: "L", fractionDigits: 2, flag: "🇲🇩"),
        Currency(code: "MGA", name: "Malagasy Ariary", symbol: "Ar", fractionDigits: 0, flag: "🇲🇬"),
        Currency(code: "MKD", name: "Macedonian Denar", symbol: "ден", fractionDigits: 2, flag: "🇲🇰"),
        Currency(code: "MMK", name: "Myanmar Kyat", symbol: "K", fractionDigits: 2, flag: "🇲🇲"),
        Currency(code: "MNT", name: "Mongolian Tugrik", symbol: "₮", fractionDigits: 2, flag: "🇲🇳"),
        Currency(code: "MOP", name: "Macanese Pataca", symbol: "MOP$", fractionDigits: 2, flag: "🇲🇴"),
        Currency(code: "MUR", name: "Mauritian Rupee", symbol: "₨", fractionDigits: 2, flag: "🇲🇺"),
        Currency(code: "MVR", name: "Maldivian Rufiyaa", symbol: ".ރ", fractionDigits: 2, flag: "🇲🇻"),
        Currency(code: "MWK", name: "Malawian Kwacha", symbol: "MK", fractionDigits: 2, flag: "🇲🇼"),
        Currency(code: "MXN", name: "Mexican Peso", symbol: "$", fractionDigits: 2, flag: "🇲🇽"),
        Currency(code: "MYR", name: "Malaysian Ringgit", symbol: "RM", fractionDigits: 2, flag: "🇲🇾"),
        Currency(code: "MZN", name: "Mozambican Metical", symbol: "MT", fractionDigits: 2, flag: "🇲🇿"),
        Currency(code: "NAD", name: "Namibian Dollar", symbol: "$", fractionDigits: 2, flag: "🇳🇦"),
        Currency(code: "NGN", name: "Nigerian Naira", symbol: "₦", fractionDigits: 2, flag: "🇳🇬"),
        Currency(code: "NIO", name: "Nicaraguan Córdoba", symbol: "C$", fractionDigits: 2, flag: "🇳🇮"),
        Currency(code: "NOK", name: "Norwegian Krone", symbol: "kr", fractionDigits: 2, flag: "🇳🇴"),
        Currency(code: "NPR", name: "Nepalese Rupee", symbol: "₨", fractionDigits: 2, flag: "🇳🇵"),
        Currency(code: "NZD", name: "New Zealand Dollar", symbol: "NZ$", fractionDigits: 2, flag: "🇳🇿"),
        Currency(code: "OMR", name: "Omani Rial", symbol: "ر.ع.", fractionDigits: 3, flag: "🇴🇲"),
        Currency(code: "PAB", name: "Panamanian Balboa", symbol: "B/.", fractionDigits: 2, flag: "🇵🇦"),
        Currency(code: "PEN", name: "Peruvian Sol", symbol: "S/", fractionDigits: 2, flag: "🇵🇪"),
        Currency(code: "PGK", name: "Papua New Guinean Kina", symbol: "K", fractionDigits: 2, flag: "🇵🇬"),
        Currency(code: "PHP", name: "Philippine Peso", symbol: "₱", fractionDigits: 2, flag: "🇵🇭"),
        Currency(code: "PKR", name: "Pakistani Rupee", symbol: "₨", fractionDigits: 2, flag: "🇵🇰"),
        Currency(code: "PLN", name: "Polish Złoty", symbol: "zł", fractionDigits: 2, flag: "🇵🇱"),
        Currency(code: "PYG", name: "Paraguayan Guarani", symbol: "₲", fractionDigits: 0, flag: "🇵🇾"),
        Currency(code: "QAR", name: "Qatari Rial", symbol: "ر.ق", fractionDigits: 2, flag: "🇶🇦"),
        Currency(code: "RON", name: "Romanian Leu", symbol: "lei", fractionDigits: 2, flag: "🇷🇴"),
        Currency(code: "RSD", name: "Serbian Dinar", symbol: "дин", fractionDigits: 2, flag: "🇷🇸"),
        Currency(code: "RUB", name: "Russian Ruble", symbol: "₽", fractionDigits: 2, flag: "🇷🇺"),
        Currency(code: "RWF", name: "Rwandan Franc", symbol: "FRw", fractionDigits: 0, flag: "🇷🇼"),
        Currency(code: "SAR", name: "Saudi Riyal", symbol: "ر.س", fractionDigits: 2, flag: "🇸🇦"),
        Currency(code: "SBD", name: "Solomon Islands Dollar", symbol: "$", fractionDigits: 2, flag: "🇸🇧"),
        Currency(code: "SCR", name: "Seychellois Rupee", symbol: "₨", fractionDigits: 2, flag: "🇸🇨"),
        Currency(code: "SDG", name: "Sudanese Pound", symbol: "ج.س.", fractionDigits: 2, flag: "🇸🇩"),
        Currency(code: "SEK", name: "Swedish Krona", symbol: "kr", fractionDigits: 2, flag: "🇸🇪"),
        Currency(code: "SGD", name: "Singapore Dollar", symbol: "S$", fractionDigits: 2, flag: "🇸🇬"),
        Currency(code: "SHP", name: "St. Helena Pound", symbol: "£", fractionDigits: 2, flag: "🇸🇭"),
        Currency(code: "SLE", name: "Sierra Leonean Leone", symbol: "Le", fractionDigits: 2, flag: "🇸🇱"),
        Currency(code: "SOS", name: "Somali Shilling", symbol: "S", fractionDigits: 2, flag: "🇸🇴"),
        Currency(code: "SRD", name: "Surinamese Dollar", symbol: "$", fractionDigits: 2, flag: "🇸🇷"),
        Currency(code: "SSP", name: "South Sudanese Pound", symbol: "£", fractionDigits: 2, flag: "🇸🇸"),
        Currency(code: "STN", name: "São Tomé & Príncipe Dobra", symbol: "Db", fractionDigits: 2, flag: "🇸🇹"),
        Currency(code: "SVC", name: "Salvadoran Colón", symbol: "₡", fractionDigits: 2, flag: "🇸🇻"),
        Currency(code: "SYP", name: "Syrian Pound", symbol: "£", fractionDigits: 2, flag: "🇸🇾"),
        Currency(code: "SZL", name: "Swazi Lilangeni", symbol: "E", fractionDigits: 2, flag: "🇸🇿"),
        Currency(code: "THB", name: "Thai Baht", symbol: "฿", fractionDigits: 2, flag: "🇹🇭"),
        Currency(code: "TJS", name: "Tajikistani Somoni", symbol: "SM", fractionDigits: 2, flag: "🇹🇯"),
        Currency(code: "TMT", name: "Turkmenistani Manat", symbol: "m", fractionDigits: 2, flag: "🇹🇲"),
        Currency(code: "TND", name: "Tunisian Dinar", symbol: "د.ت", fractionDigits: 3, flag: "🇹🇳"),
        Currency(code: "TOP", name: "Tongan Paʻanga", symbol: "T$", fractionDigits: 2, flag: "🇹🇴"),
        Currency(code: "TRY", name: "Turkish Lira", symbol: "₺", fractionDigits: 2, flag: "🇹🇷"),
        Currency(code: "TTD", name: "Trinidad & Tobago Dollar", symbol: "$", fractionDigits: 2, flag: "🇹🇹"),
        Currency(code: "TWD", name: "New Taiwan Dollar", symbol: "NT$", fractionDigits: 2, flag: "🇹🇼"),
        Currency(code: "TZS", name: "Tanzanian Shilling", symbol: "TSh", fractionDigits: 2, flag: "🇹🇿"),
        Currency(code: "UAH", name: "Ukrainian Hryvnia", symbol: "₴", fractionDigits: 2, flag: "🇺🇦"),
        Currency(code: "UGX", name: "Ugandan Shilling", symbol: "USh", fractionDigits: 0, flag: "🇺🇬"),
        Currency(code: "USD", name: "US Dollar", symbol: "$", fractionDigits: 2, flag: "🇺🇸"),
        Currency(code: "UYU", name: "Uruguayan Peso", symbol: "$U", fractionDigits: 2, flag: "🇺🇾"),
        Currency(code: "UZS", name: "Uzbekistani Som", symbol: "so'm", fractionDigits: 2, flag: "🇺🇿"),
        Currency(code: "VES", name: "Venezuelan Bolívar", symbol: "Bs.", fractionDigits: 2, flag: "🇻🇪"),
        Currency(code: "VND", name: "Vietnamese Dong", symbol: "₫", fractionDigits: 0, flag: "🇻🇳"),
        Currency(code: "VUV", name: "Vanuatu Vatu", symbol: "VT", fractionDigits: 0, flag: "🇻🇺"),
        Currency(code: "WST", name: "Samoan Tala", symbol: "T", fractionDigits: 2, flag: "🇼🇸"),
        Currency(code: "XAF", name: "Central African CFA Franc", symbol: "FCFA", fractionDigits: 0, flag: "🌍"),
        Currency(code: "XCD", name: "East Caribbean Dollar", symbol: "$", fractionDigits: 2, flag: "🌎"),
        Currency(code: "XOF", name: "West African CFA Franc", symbol: "CFA", fractionDigits: 0, flag: "🌍"),
        Currency(code: "XPF", name: "CFP Franc", symbol: "₣", fractionDigits: 0, flag: "🇵🇫"),
        Currency(code: "YER", name: "Yemeni Rial", symbol: "﷼", fractionDigits: 2, flag: "🇾🇪"),
        Currency(code: "ZAR", name: "South African Rand", symbol: "R", fractionDigits: 2, flag: "🇿🇦"),
        Currency(code: "ZMW", name: "Zambian Kwacha", symbol: "ZK", fractionDigits: 2, flag: "🇿🇲"),
        Currency(code: "ZWL", name: "Zimbabwean Dollar", symbol: "Z$", fractionDigits: 2, flag: "🇿🇼"),
    ]
}
