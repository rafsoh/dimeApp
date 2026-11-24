//
//  CurrencyConverter.swift
//  dime
//

import Foundation

protocol ExchangeRateProviding {
    /// Units of `currencyCode` one US dollar bought on `date`, or nil when that isn't known.
    func unitsPerDollar(of currencyCode: String, on date: Date) -> Double?
}

struct MoneyEntry {
    var id: UUID?
    var amount: Double
    /// nil is a transaction stored before currencies were, which is in the main currency.
    var currencyCode: String?
    var date: Date
    var income: Bool
}

struct ConversionReport: Equatable {
    private(set) var convertedCount = 0
    private(set) var excludedCount = 0
    private(set) var excludedIDs: [UUID] = []
    private(set) var excludedCurrencies: Set<String> = []

    var isApproximate: Bool { convertedCount > 0 }
    var isComplete: Bool { excludedCount == 0 }

    mutating func recordConverted() {
        convertedCount += 1
    }

    mutating func recordExcluded(_ entry: MoneyEntry) {
        excludedCount += 1

        if let id = entry.id {
            excludedIDs.append(id)
        }

        if let code = entry.currencyCode {
            excludedCurrencies.insert(code.uppercased())
        }
    }

    mutating func merge(_ other: ConversionReport) {
        convertedCount += other.convertedCount
        excludedCount += other.excludedCount
        excludedIDs += other.excludedIDs
        excludedCurrencies.formUnion(other.excludedCurrencies)
    }
}

struct MoneyTotal: Equatable {
    var value = 0.0
    var report = ConversionReport()
}

// Converts to the viewer's main currency when amounts are read. Nothing converted is ever stored, and an
// amount without a known rate is excluded and counted rather than treated as 1:1.
struct CurrencyConverter {
    static let pivotCurrency = "USD"
    static let appGroup = "group.com.rafaelsoh.dime"

    let mainCurrency: String
    let rates: ExchangeRateProviding?

    init(mainCurrency: String, rates: ExchangeRateProviding? = nil) {
        self.mainCurrency = mainCurrency.uppercased()
        self.rates = rates
    }

    // Matches the default of every @AppStorage("currency").
    static func mainCurrency(in defaults: UserDefaults?) -> String {
        defaults?.string(forKey: "currency") ?? Locale.current.currencyCode ?? pivotCurrency
    }

    static func current() -> CurrencyConverter {
        CurrencyConverter(mainCurrency: mainCurrency(in: UserDefaults(suiteName: appGroup)))
    }

    func isMainCurrency(_ currencyCode: String?) -> Bool {
        guard let currencyCode else {
            return true
        }

        return currencyCode.uppercased() == mainCurrency
    }

    /// Units of `target` one unit of `source` bought on `date`.
    func rate(from source: String, to target: String, on date: Date) -> Double? {
        let source = source.uppercased()
        let target = target.uppercased()

        if source == target {
            return 1
        }

        guard let sourcePerDollar = unitsPerDollar(source, on: date), let targetPerDollar = unitsPerDollar(target, on: date) else {
            return nil
        }

        return targetPerDollar / sourcePerDollar
    }

    private func unitsPerDollar(_ currencyCode: String, on date: Date) -> Double? {
        if currencyCode == Self.pivotCurrency {
            return 1
        }

        guard let value = rates?.unitsPerDollar(of: currencyCode, on: date), value.isFinite, value > 0 else {
            return nil
        }

        return value
    }

    func convert(_ amount: Double, from currencyCode: String?, on date: Date) -> Double? {
        guard let currencyCode, !isMainCurrency(currencyCode) else {
            return amount
        }

        return rate(from: currencyCode, to: mainCurrency, on: date).map { amount * $0 }
    }

    /// The entry in the main currency, or 0 when it can't be converted. Either way the report counts it.
    func amount(of entry: MoneyEntry, report: inout ConversionReport) -> Double {
        if isMainCurrency(entry.currencyCode) {
            return entry.amount
        }

        guard let converted = convert(entry.amount, from: entry.currencyCode, on: entry.date) else {
            report.recordExcluded(entry)
            return 0
        }

        report.recordConverted()
        return converted
    }

    /// For splitting up a total whose own report counts the exclusions, such as a chart's bars or
    /// segments: an amount without a rate is 0 here.
    func amountInBreakdown(of entry: MoneyEntry) -> Double {
        var report = ConversionReport()
        return amount(of: entry, report: &report)
    }

    /// Adds in sequence order from zero, so amounts already in the main currency give the same Double as
    /// adding them up directly. `signed` subtracts expenses.
    func total<S: Sequence>(of entries: S, signed: Bool = false) -> MoneyTotal where S.Element == MoneyEntry {
        var total = MoneyTotal()

        for entry in entries {
            let value = amount(of: entry, report: &total.report)

            if signed && !entry.income {
                total.value -= value
            } else {
                total.value += value
            }
        }

        return total
    }
}
