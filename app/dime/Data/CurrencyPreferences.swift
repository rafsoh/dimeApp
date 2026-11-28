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
        let digits = showCents ? CurrencyDigits.fractionDigits(for: currencyCode) : 0
        let formatter = CachedFormatter.currency(currencyCode.uppercased(), fractionDigits: digits)
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode.uppercased()) \(amount)"
    }
}

/// Formatters are slow to create. Transaction lists made several for every row, and building a long list
/// held the main thread for seconds. These are kept per configuration and dropped when the locale or time
/// zone changes. Formatting with a shared formatter is thread-safe as long as nobody changes it afterwards.
enum CachedFormatter {
    private static let lock = NSLock()
    private static var cache: [String: Formatter] = [:]
    private static var isObservingChanges = false

    /// A date formatter with a fixed format, such as "d MMM".
    static func date(format: String) -> DateFormatter {
        formatter(for: "date.format.\(format)") {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            return formatter
        }
    }

    /// A date formatter built from a localized template, such as "jmm".
    static func date(template: String) -> DateFormatter {
        formatter(for: "date.template.\(template)") {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
    }

    /// A currency formatter showing at most `maximumFractionDigits` digits, as list rows and totals use.
    static func currency(_ currencyCode: String, maximumFractionDigits: Int) -> NumberFormatter {
        formatter(for: "currency.\(currencyCode).max.\(maximumFractionDigits)") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.maximumFractionDigits = maximumFractionDigits
            return formatter
        }
    }

    /// A currency formatter showing exactly `fractionDigits` digits.
    static func currency(_ currencyCode: String, fractionDigits: Int) -> NumberFormatter {
        formatter(for: "currency.\(currencyCode).exact.\(fractionDigits)") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.minimumFractionDigits = fractionDigits
            formatter.maximumFractionDigits = fractionDigits
            return formatter
        }
    }

    private static func formatter<T: Formatter>(for key: String, make: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }

        if !isObservingChanges {
            isObservingChanges = true

            for name in [NSLocale.currentLocaleDidChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                    lock.lock()
                    cache.removeAll()
                    lock.unlock()
                }
            }
        }

        if let cached = cache[key] as? T {
            return cached
        }

        let made = make()
        cache[key] = made
        return made
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

/// A sum typed with the calculator's operator row, such as 86.40 ÷ 3. Numbers are kept as typed, with "." as the
/// decimal point, so the amount shows exactly what was entered. × and ÷ go before + and −, and the total is rounded
/// once, at the end, to the currency's fraction digits.
struct CalculatorExpression: Equatable {
    enum Operator: Equatable, CaseIterable {
        case divide, multiply, subtract, add

        /// The SF Symbol drawn for it, on its key and in the amount.
        var symbolName: String {
            switch self {
            case .divide: return "divide"
            case .multiply: return "multiply"
            case .subtract: return "minus"
            case .add: return "plus"
            }
        }

        /// The character it's written as in plain text, which VoiceOver reads out.
        var character: String {
            switch self {
            case .divide: return "÷"
            case .multiply: return "×"
            case .subtract: return "−"
            case .add: return "+"
            }
        }

        /// × and ÷ take factors, like 3 people or a 1.0825 tax rate, rather than amounts, so they allow more decimals.
        var takesFactor: Bool {
            self == .divide || self == .multiply
        }
    }

    enum Token: Equatable {
        case number(String)
        case op(Operator)
    }

    enum Failure: Error, Equatable {
        case divisionByZero
        case negative
        case tooLarge
    }

    /// The number pad's own limit.
    static let maximumAmount: Decimal = 100_000_000
    static let maximumWholeDigits = 9
    static let maximumFactorDigits = 4

    private(set) var tokens: [Token] = []

    init() {}

    /// Starts from what the pad shows, such as "12.50" or "12.", so nothing typed is lost when the operators open.
    init(number: String) {
        guard number.contains(".") || (Decimal(string: number, locale: Self.posix) ?? 0) != 0 else {
            return
        }

        tokens = [.number(number)]
    }

    /// Starts from an amount set some other way, such as a suggestion or the transaction being edited.
    init(amount: Double, fractionDigits: Int) {
        guard amount > 0 else {
            return
        }

        let format = amount.rounded() == amount ? "%.0f" : "%.\(max(0, fractionDigits))f"
        tokens = [.number(String(format: format, amount))]
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    var isEmpty: Bool {
        tokens.isEmpty
    }

    var hasOperator: Bool {
        tokens.contains { token in
            if case .op = token {
                return true
            }
            return false
        }
    }

    /// The operator just typed, still waiting for its number.
    var pendingOperator: Operator? {
        if case .op(let op)? = tokens.last {
            return op
        }
        return nil
    }

    /// The sum as text, such as "86.40 ÷ 3".
    func text(decimalSeparator: String = ".") -> String {
        tokens.map { token -> String in
            switch token {
            case .number(let number):
                return number.replacingOccurrences(of: ".", with: decimalSeparator)
            case .op(let op):
                return op.character
            }
        }
        .joined(separator: " ")
    }

    /// How many decimals the number being typed can have: the currency's for an amount, more for a factor.
    private func allowedDecimals(fractionDigits: Int) -> Int {
        var before: Operator?

        if case .op(let op)? = tokens.last {
            before = op
        } else if tokens.count >= 2, case .op(let op) = tokens[tokens.count - 2] {
            before = op
        }

        return before?.takesFactor == true ? Self.maximumFactorDigits : max(0, fractionDigits)
    }

    /// False when the digit doesn't fit, so the pad can refuse it.
    @discardableResult
    mutating func append(digit: Int, fractionDigits: Int) -> Bool {
        guard (0...9).contains(digit) else {
            return false
        }

        guard case .number(let number)? = tokens.last else {
            tokens.append(.number(String(digit)))
            return true
        }

        if let point = number.firstIndex(of: ".") {
            let decimals = number.distance(from: point, to: number.endIndex) - 1
            guard decimals < allowedDecimals(fractionDigits: fractionDigits) else {
                return false
            }
            tokens[tokens.count - 1] = .number(number + String(digit))
        } else if number == "0" {
            tokens[tokens.count - 1] = .number(String(digit))
        } else {
            guard number.count < Self.maximumWholeDigits else {
                return false
            }
            tokens[tokens.count - 1] = .number(number + String(digit))
        }

        return true
    }

    /// False when the number being typed already has one, or can't have decimals at all.
    @discardableResult
    mutating func appendDecimalPoint(fractionDigits: Int) -> Bool {
        guard allowedDecimals(fractionDigits: fractionDigits) > 0 else {
            return false
        }

        guard case .number(let number)? = tokens.last else {
            tokens.append(.number("0."))
            return true
        }

        guard !number.contains(".") else {
            return false
        }

        tokens[tokens.count - 1] = .number(number + ".")
        return true
    }

    /// Adds an operator, or swaps the one just typed for it. False on an empty sum, which has nothing to work on.
    @discardableResult
    mutating func apply(_ op: Operator) -> Bool {
        switch tokens.last {
        case nil:
            return false
        case .op?:
            tokens[tokens.count - 1] = .op(op)
        case .number(let number)?:
            if number.hasSuffix(".") {
                tokens[tokens.count - 1] = .number(String(number.dropLast()))
            }
            tokens.append(.op(op))
        }

        return true
    }

    /// Removes the last character typed, operators included.
    mutating func deleteLast() {
        guard let last = tokens.last else {
            return
        }

        if case .number(let number) = last, number.count > 1 {
            tokens[tokens.count - 1] = .number(String(number.dropLast()))
        } else {
            tokens.removeLast()
        }
    }

    mutating func clear() {
        tokens.removeAll()
    }

    /// The sum worked out and rounded to the currency's digits. An operator still waiting for its number is ignored.
    func total(fractionDigits: Int) -> Result<Double, Failure> {
        var tokens = self.tokens
        if case .op? = tokens.last {
            tokens.removeLast()
        }

        guard !tokens.isEmpty else {
            return .success(0)
        }

        // × and ÷ first, leaving terms that are then added and subtracted.
        var terms: [Decimal] = []
        var signs: [Operator] = []
        var pending: Operator?

        for token in tokens {
            switch token {
            case .op(let op):
                pending = op
            case .number(let text):
                let value = Decimal(string: text, locale: Self.posix) ?? 0

                switch pending {
                case .some(.multiply):
                    terms[terms.count - 1] *= value
                case .some(.divide):
                    guard !value.isZero else {
                        return .failure(.divisionByZero)
                    }
                    terms[terms.count - 1] /= value
                case .some(let sign):
                    signs.append(sign)
                    terms.append(value)
                case .none:
                    terms.append(value)
                }
            }
        }

        var result = terms[0]
        for (index, sign) in signs.enumerated() {
            result = sign == .add ? result + terms[index + 1] : result - terms[index + 1]
        }

        guard !result.isNaN else {
            return .failure(.tooLarge)
        }

        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, max(0, fractionDigits), .plain)

        if rounded.isZero {
            return .success(0)
        }
        guard rounded > 0 else {
            return .failure(.negative)
        }
        guard rounded < Self.maximumAmount else {
            return .failure(.tooLarge)
        }

        // Through text, because Decimal's doubleValue can land a hair off (28.8 as 28.799999999999997).
        return .success(Double(rounded.description) ?? NSDecimalNumber(decimal: rounded).doubleValue)
    }

    /// The = key: puts the total in place of the sum, to the currency's digits.
    @discardableResult
    mutating func collapse(fractionDigits: Int) -> Result<Double, Failure> {
        let result = total(fractionDigits: fractionDigits)

        if hasOperator, case .success(let value) = result {
            tokens = value == 0 ? [] : [.number(String(format: "%.\(max(0, fractionDigits))f", value))]
        }

        return result
    }
}
