import Foundation
import Observation

/// A set of exchange rates quoted against a single base currency.
struct ExchangeRateTable: Codable, Sendable, Equatable {
    var baseCode: String
    /// Currency code → units of that currency per 1 unit of `baseCode`.
    var rates: [String: Double]
    var fetchedAt: Date
    /// True when these came from the bundled snapshot rather than the network.
    var isOffline: Bool

    static let empty = ExchangeRateTable(baseCode: "USD", rates: ["USD": 1], fetchedAt: .distantPast, isOffline: true)

    func rate(from: String, to: String) -> Double? {
        let from = from.uppercased()
        let to = to.uppercased()
        if from == to { return 1 }
        guard let fromRate = rates[from], let toRate = rates[to], fromRate > 0 else { return nil }
        // Both are quoted against the base, so cross-rate via the base.
        return toRate / fromRate
    }

    /// Converts between currencies, respecting each one's minor-unit precision.
    /// Returns 0 when we have no rate rather than guessing.
    func convert(minorUnits: Int, from: String, to: String) -> Int {
        if from.uppercased() == to.uppercased() { return minorUnits }
        guard let rate = rate(from: from, to: to) else { return 0 }
        let fromDigits = Currency.fractionDigits(for: from)
        let toDigits = Currency.fractionDigits(for: to)
        let major = Double(minorUnits) / pow(10, Double(fromDigits))
        return Int((major * rate * pow(10, Double(toDigits))).rounded())
    }

    var ageDescription: String {
        guard fetchedAt != .distantPast else {
            return String(localized: "Built-in rates")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }
}

/// Fetches and caches exchange rates.
///
/// Rates are cached on disk and the bundled snapshot is always available, so
/// conversion works on a plane with no signal. A refresh is attempted at most
/// once every six hours, and a failure is never fatal - we just keep using
/// whatever we already have.
@Observable
@MainActor
final class ExchangeRateService {
    private(set) var table: ExchangeRateTable
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let cacheURL: URL
    private let session: URLSession
    private static let refreshInterval: TimeInterval = 6 * 60 * 60

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheURL = caches.appendingPathComponent("exchange-rates.json")

        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(ExchangeRateTable.self, from: data) {
            self.table = cached
        } else {
            self.table = ExchangeRateService.bundledTable
        }
    }

    var needsRefresh: Bool {
        Date().timeIntervalSince(table.fetchedAt) > Self.refreshInterval
    }

    func refreshIfNeeded() async {
        guard needsRefresh, !isRefreshing else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await fetchRates()
            table = fetched
            lastError = nil
            if let data = try? JSONEncoder().encode(fetched) {
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            // Keep the previous table - stale rates beat no rates.
            lastError = error.localizedDescription
        }
    }

    private func fetchRates() async throws -> ExchangeRateTable {
        // A keyless, rate-limited public endpoint. If it's unavailable we fall
        // back to the cached or bundled table rather than failing the feature.
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExchangeRateError.badResponse
        }

        struct Payload: Decodable {
            let result: String?
            let base_code: String?
            let rates: [String: Double]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let rates = payload.rates, !rates.isEmpty else { throw ExchangeRateError.badResponse }

        // Keep only currencies we can actually display.
        let filtered = rates.filter { Currency.exists($0.key) }
        return ExchangeRateTable(
            baseCode: payload.base_code ?? "USD",
            rates: filtered,
            fetchedAt: Date(),
            isOffline: false
        )
    }

    enum ExchangeRateError: LocalizedError {
        case badResponse
        var errorDescription: String? {
            String(localized: "Couldn't reach the rate service. Using saved rates.")
        }
    }

    /// Approximate rates shipped with the app so conversion always works offline.
    /// These are a snapshot, not live quotes - the UI labels them as such and any
    /// successful refresh replaces them.
    nonisolated static let bundledTable = ExchangeRateTable(
        baseCode: "USD",
        rates: [
            "USD": 1.0, "EUR": 0.92, "GBP": 0.79, "JPY": 152.0, "CNY": 7.24,
            "INR": 83.4, "CAD": 1.36, "AUD": 1.52, "CHF": 0.90, "HKD": 7.82,
            "SGD": 1.35, "NZD": 1.65, "SEK": 10.6, "NOK": 10.8, "DKK": 6.87,
            "PLN": 4.02, "CZK": 23.2, "HUF": 360.0, "RON": 4.58, "BGN": 1.80,
            "TRY": 32.3, "RUB": 92.0, "UAH": 39.5, "ILS": 3.72, "AED": 3.67,
            "SAR": 3.75, "QAR": 3.64, "KWD": 0.308, "BHD": 0.376, "OMR": 0.385,
            "JOD": 0.709, "EGP": 47.5, "ZAR": 18.7, "NGN": 1450.0, "KES": 132.0,
            "GHS": 13.2, "MAD": 10.0, "TND": 3.12, "DZD": 134.0, "ETB": 57.0,
            "TZS": 2600.0, "UGX": 3800.0, "XOF": 604.0, "XAF": 604.0,
            "BRL": 5.05, "MXN": 17.0, "ARS": 870.0, "CLP": 950.0, "COP": 3900.0,
            "PEN": 3.72, "UYU": 39.0, "BOB": 6.91, "PYG": 7300.0, "VES": 36.0,
            "KRW": 1340.0, "TWD": 32.0, "THB": 36.2, "VND": 24800.0, "IDR": 15700.0,
            "MYR": 4.72, "PHP": 56.2, "PKR": 278.0, "BDT": 110.0, "LKR": 305.0,
            "NPR": 133.0, "MMK": 2100.0, "KHR": 4100.0, "LAK": 20800.0, "MNT": 3400.0,
            "KZT": 450.0, "UZS": 12600.0, "AZN": 1.70, "GEL": 2.65, "AMD": 388.0,
            "BYN": 3.27, "MDL": 17.7, "RSD": 108.0, "MKD": 56.6, "BAM": 1.80,
            "ISK": 138.0, "HRK": 6.93, "ALL": 94.0,
            "DOP": 58.5, "GTQ": 7.80, "CRC": 510.0, "HNL": 24.7, "NIO": 36.8,
            "PAB": 1.0, "JMD": 155.0, "TTD": 6.78, "BBD": 2.0, "BSD": 1.0,
            "BZD": 2.0, "XCD": 2.70, "AWG": 1.79, "ANG": 1.79, "CUP": 24.0,
            "HTG": 132.0, "GYD": 209.0, "SRD": 35.0, "SVC": 8.75, "CVE": 101.0,
            "FJD": 2.25, "PGK": 3.80, "SBD": 8.45, "TOP": 2.35, "VUV": 119.0,
            "WST": 2.72, "XPF": 110.0, "BND": 1.35, "MOP": 8.05,
            "AFN": 72.0, "IRR": 42000.0, "IQD": 1310.0, "LBP": 89500.0, "SYP": 13000.0,
            "YER": 250.0, "LYD": 4.85, "SDG": 601.0, "SSP": 1300.0, "ERN": 15.0,
            "DJF": 178.0, "SOS": 571.0, "RWF": 1300.0, "BIF": 2860.0, "KMF": 452.0,
            "MGA": 4500.0, "MUR": 46.5, "SCR": 13.5, "MVR": 15.4, "BTN": 83.4,
            "MWK": 1730.0, "ZMW": 26.0, "ZWL": 25.0, "BWP": 13.7, "NAD": 18.7,
            "LSL": 18.7, "SZL": 18.7, "MZN": 63.9, "AOA": 850.0, "CDF": 2800.0,
            "GMD": 67.0, "GNF": 8600.0, "LRD": 194.0, "SLE": 22.7, "STN": 22.5,
            "TJS": 10.9, "TMT": 3.50, "KGS": 89.0, "FKP": 0.79, "GIP": 0.79,
            "SHP": 0.79, "BMD": 1.0, "KYD": 0.83,
        ],
        fetchedAt: .distantPast,
        isOffline: true
    )
}
