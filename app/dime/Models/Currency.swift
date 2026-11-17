//
//  Currency.swift
//  dime
//
//  Created by Rafael Soh on 5/9/22.
//

import Foundation

struct Currency: Hashable {
    let name: String
    let code: String
    let symbol: String
}

extension Locale {
    func localizedCurrencySymbol(forCurrencyCode currencyCode: String) -> String? {
        guard let languageCode = languageCode, let regionCode = regionCode else { return nil }

        let components: [String: String] = [
            NSLocale.Key.languageCode.rawValue: languageCode,
            NSLocale.Key.countryCode.rawValue: regionCode,
            NSLocale.Key.currencyCode.rawValue: currencyCode
        ]

        let identifier = Locale.identifier(fromComponents: components)

        return Locale(identifier: identifier).currencySymbol
    }
}

extension Currency {
    static var currencyCodes: [String] = ["AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN", "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BOV", "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF", "CHW", "CLF", "CLP", "CNY", "COP", "COU", "CRC", "CUC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL", "HRK", "HTG", "HUF", "IDR", "ILS", "INR", "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR", "LRD", "LSL", "LTL", "LVL", "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MUR", "MVR", "MWK", "MXN", "MXV", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLL", "SOS", "SRD", "SSP", "STD", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD", "UYU", "UZS", "VND", "VUV", "WST", "XAF", "XAG", "XAU", "XBA", "XBB", "XCD", "XDR", "XFU", "XOF", "XPD", "XPF", "XPT", "YER", "ZAR", "ZMW"]

    static var allCurrencies: [Currency] {
        let currencies: [Currency] = currencyCodes.compactMap {
            let name = Locale.current.localizedString(forCurrencyCode: $0) ?? ""
            let symbol = Locale.current.localizedCurrencySymbol(forCurrencyCode: $0) ?? ""
            return Currency(name: name, code: $0, symbol: symbol)
        }
        return currencies
    }
}

/// Exchange rates for entering transactions in a foreign currency.
/// Rates come from Frankfurter (ECB reference rates) and are cached per currency pair,
/// so the last known rate is still available offline.
enum ExchangeRates {
    private static let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
    private static let recentKey = "recentEntryCurrencies"

    struct FrankfurterResponse: Decodable {
        let rates: [String: Double]
    }

    static func cachedRate(from: String, to: String) -> Double? {
        let value = defaults?.double(forKey: "rate_\(from)_\(to)") ?? 0
        return value > 0 ? value : nil
    }

    static func cache(rate: Double, from: String, to: String) {
        defaults?.set(rate, forKey: "rate_\(from)_\(to)")
    }

    /// Rate to convert 1 unit of `from` into `to`, for the given day.
    static func fetchRate(from: String, to: String, on date: Date) async throws -> Double {
        let path: String
        if Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date.now) {
            path = "latest"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            path = formatter.string(from: date)
        }

        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(path)?from=\(from)&to=\(to)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let rate = try JSONDecoder().decode(FrankfurterResponse.self, from: data).rates[to], rate > 0 else {
            throw URLError(.cannotParseResponse)
        }

        cache(rate: rate, from: from, to: to)
        return rate
    }

    static var recentCurrencies: [String] {
        defaults?.stringArray(forKey: recentKey) ?? []
    }

    static func markRecent(_ code: String) {
        var list = recentCurrencies.filter { $0 != code }
        list.insert(code, at: 0)
        defaults?.set(Array(list.prefix(5)), forKey: recentKey)
    }

    static func fractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    /// Converts an amount and rounds it to the target currency's minor units.
    static func convert(_ amount: Double, rate: Double, to code: String) -> Double {
        let factor = pow(10, Double(fractionDigits(for: code)))
        return (amount * rate * factor).rounded() / factor
    }
}
