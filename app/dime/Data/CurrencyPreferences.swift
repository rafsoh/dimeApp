//
//  CurrencyPreferences.swift
//  dime
//

import Foundation

enum CurrencyDigits {
    // ISO 4217 minor units that aren't 2. Entry is capped at 3 digits.
    private static let exceptions: [String: Int] = [
        "BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0, "KMF": 0, "KRW": 0, "PYG": 0,
        "RWF": 0, "UGX": 0, "VND": 0, "VUV": 0, "XAF": 0, "XOF": 0, "XPF": 0,
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3, "CLF": 3
    ]

    static func fractionDigits(for currencyCode: String) -> Int {
        exceptions[currencyCode.uppercased()] ?? 2
    }
}

enum MoneyFormatter {
    /// An amount in its own currency's digits, such as ¥1,200 or KWD 1.250.
    static func string(_ amount: Double, currencyCode: String, showCents: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.uppercased()
        let digits = showCents ? CurrencyDigits.fractionDigits(for: currencyCode) : 0
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode.uppercased()) \(amount)"
    }
}

enum CurrencyPreferences {
    static let recentCurrenciesKey = "recentCurrencies"
    static let recentLimit = 5

    static func recentCurrencies(in defaults: UserDefaults?) -> [String] {
        defaults?.stringArray(forKey: recentCurrenciesKey) ?? []
    }

    static func recording(_ currencyCode: String, in recent: [String]) -> [String] {
        let code = currencyCode.uppercased()
        return Array(([code] + recent.filter { $0 != code }).prefix(recentLimit))
    }

    static func record(_ currencyCode: String, in defaults: UserDefaults?) {
        defaults?.set(recording(currencyCode, in: recentCurrencies(in: defaults)), forKey: recentCurrenciesKey)
    }

    /// The only place a new transaction's currency is chosen: the last one used, otherwise the main currency.
    /// A future account's default currency belongs here too.
    static func defaultCurrency(mainCurrency: String, recent: [String]) -> String {
        guard let last = recent.first else {
            return mainCurrency.uppercased()
        }

        return last
    }

    /// The main currency first, then recently used ones, then the rest in their usual order.
    static func pickerOrder(codes: [String], recent: [String], mainCurrency: String) -> [String] {
        var pinned: [String] = []

        for code in [mainCurrency.uppercased()] + recent where !pinned.contains(code) {
            pinned.append(code)
        }

        return pinned + codes.filter { !pinned.contains($0) }
    }

    static func isSameCurrency(_ currencyCode: String?, as other: String?, mainCurrency: String) -> Bool {
        (currencyCode ?? mainCurrency).uppercased() == (other ?? mainCurrency).uppercased()
    }
}

/// The number pad's arithmetic for a currency's number of fraction digits. With 2 digits each step is the
/// same Double operation the pad always did.
enum AmountEntry {
    static let maximumFractionDigits = 3

    private static func scale(_ digits: Int) -> Double {
        [1, 10, 100, 1000][max(0, min(maximumFractionDigits, digits))]
    }

    /// Typing shifts digits in from the right, as on a till.
    static func shiftingIn(_ digit: Int, to price: Double, fractionDigits: Int) -> Double {
        price * 10 + Double(digit) / scale(fractionDigits)
    }

    static func shiftingOut(of price: Double, fractionDigits: Int) -> Double {
        guard fractionDigits > 0 else {
            return Double(Int(price / 10))
        }

        return Double(Int(price * scale(fractionDigits - 1))) / scale(fractionDigits)
    }

    static func appendingWhole(_ digit: Int, to price: Double) -> Double {
        price * 10 + Double(digit)
    }

    /// Nil once all of the currency's fraction digits are typed.
    static func appendingDecimal(_ digit: Int, to price: Double, assigned: Int, fractionDigits: Int) -> Double? {
        guard assigned < fractionDigits else {
            return nil
        }

        return price + Double(digit) / scale(assigned + 1)
    }

    static func removingWhole(from price: Double) -> Double {
        Double(Int(price / 10))
    }

    /// Removes the last of `assigned` typed fraction digits.
    static func removingDecimal(from price: Double, assigned: Int) -> Double {
        Double(Int(price * scale(assigned - 1))) / scale(assigned - 1)
    }

    static func display(_ price: Double, entryType: Int, isEditingDecimal: Bool, assigned: Int, fractionDigits: Int) -> String {
        if entryType == 1 {
            return String(format: "%.\(fractionDigits)f", price)
        }

        if isEditingDecimal {
            return assigned == 0 ? String(format: "%.0f", price) + "." : String(format: "%.\(assigned)f", price)
        }

        return String(format: "%.0f", price)
    }

    /// An amount cut down to a currency's fraction digits, for when the currency changes mid-entry.
    static func truncated(_ price: Double, fractionDigits: Int) -> Double {
        let scaled = price * scale(fractionDigits)
        return Double(Int((scaled + 1e-9 * max(1, abs(scaled))).rounded(.down))) / scale(fractionDigits)
    }
}
