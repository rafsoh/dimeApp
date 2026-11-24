//
//  CurrencyConverterTests.swift
//  dimeTests
//

@testable import dime
import XCTest

final class CurrencyConverterTests: XCTestCase {
    private struct Rates: ExchangeRateProviding {
        var unitsPerDollar: [String: Double]

        func unitsPerDollar(of currencyCode: String, on _: Date) -> Double? {
            unitsPerDollar[currencyCode]
        }
    }

    private struct Random {
        var state: UInt64

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private let date = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func entry(_ amount: Double, _ currencyCode: String?, income: Bool = false, id: UUID? = UUID()) -> MoneyEntry {
        MoneyEntry(id: id, amount: amount, currencyCode: currencyCode, date: date, income: income)
    }

    func testAmountsInTheMainCurrencyAreUntouched() {
        let converter = CurrencyConverter(mainCurrency: "SGD", rates: Rates(unitsPerDollar: ["SGD": 1.35]))
        var report = ConversionReport()

        for amount in [0.1 + 0.2, 1e-7, 99_999_999.99, -4.5, 0] {
            XCTAssertEqual(converter.amount(of: entry(amount, nil), report: &report).bitPattern, amount.bitPattern)
            XCTAssertEqual(converter.amount(of: entry(amount, "SGD"), report: &report).bitPattern, amount.bitPattern)
            XCTAssertEqual(converter.amount(of: entry(amount, "sgd"), report: &report).bitPattern, amount.bitPattern)
        }

        XCTAssertEqual(report, ConversionReport())
    }

    // Before any foreign currency is used, every total must be exactly the Double that adding up the
    // amounts directly gave, in the same order.
    func testTotalsMatchAddingUpDirectly() {
        var random = Random(state: 7)

        for round in 0 ..< 200 {
            let entries = (0 ..< Int(random.next() * 400)).map { _ -> MoneyEntry in
                let amount = (random.next() * 10_000).rounded() / [1, 10, 100, 1000][Int(random.next() * 4)]
                return entry(amount, random.next() < 0.5 ? nil : "EUR", income: random.next() < 0.3)
            }
            let converter = CurrencyConverter(mainCurrency: "EUR", rates: round.isMultiple(of: 2) ? nil : Rates(unitsPerDollar: ["EUR": 0.9]))

            var plain = 0.0
            var signed = 0.0

            for entry in entries {
                plain += entry.amount

                if entry.income {
                    signed += entry.amount
                } else {
                    signed -= entry.amount
                }
            }

            XCTAssertEqual(converter.total(of: entries).value.bitPattern, plain.bitPattern)
            XCTAssertEqual(converter.total(of: entries, signed: true).value.bitPattern, signed.bitPattern)
            XCTAssertEqual(entries.reduce(0) { $0 + $1.amount }.bitPattern, plain.bitPattern)
            XCTAssertFalse(converter.total(of: entries).report.isApproximate)
            XCTAssertTrue(converter.total(of: entries).report.isComplete)
        }
    }

    func testForeignAmountsWithoutARateAreExcludedAndCounted() {
        let converter = CurrencyConverter(mainCurrency: "USD")
        let missing = UUID()
        let entries = [entry(10, nil), entry(5, "USD"), entry(1_000, "JPY", id: missing), entry(3, "EUR", id: nil)]

        let total = converter.total(of: entries)

        XCTAssertEqual(total.value, 15)
        XCTAssertEqual(total.report.excludedCount, 2)
        XCTAssertEqual(total.report.excludedIDs, [missing])
        XCTAssertEqual(total.report.excludedCurrencies, ["JPY", "EUR"])
        XCTAssertFalse(total.report.isComplete)
        XCTAssertFalse(total.report.isApproximate)
    }

    func testCrossRatesGoThroughTheDollar() throws {
        let converter = CurrencyConverter(mainCurrency: "GBP", rates: Rates(unitsPerDollar: ["EUR": 0.9, "GBP": 0.75, "JPY": 150]))

        XCTAssertEqual(try XCTUnwrap(converter.rate(from: "EUR", to: "GBP", on: date)), 0.75 / 0.9, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(converter.rate(from: "USD", to: "GBP", on: date)), 0.75, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(converter.convert(1_500, from: "JPY", on: date)), 7.5, accuracy: 1e-9)

        var report = ConversionReport()
        XCTAssertEqual(converter.amount(of: entry(90, "EUR"), report: &report), 75, accuracy: 1e-9)
        XCTAssertEqual(report.convertedCount, 1)
        XCTAssertTrue(report.isApproximate)
    }

    func testUnusableRatesAreNeverTreatedAsOneToOne() {
        let converter = CurrencyConverter(mainCurrency: "USD", rates: Rates(unitsPerDollar: ["AAA": 0, "BBB": -2, "CCC": .nan, "DDD": .infinity]))

        for code in ["AAA", "BBB", "CCC", "DDD", "EEE"] {
            XCTAssertNil(converter.convert(10, from: code, on: date), code)
        }

        XCTAssertEqual(converter.total(of: ["AAA", "BBB", "CCC", "DDD", "EEE"].map { entry(10, $0) }).report.excludedCount, 5)
    }

    func testMainCurrencyWithoutARateExcludesOtherCurrencies() {
        let converter = CurrencyConverter(mainCurrency: "XAU", rates: Rates(unitsPerDollar: ["EUR": 0.9]))
        let total = converter.total(of: [entry(10, "EUR"), entry(2, nil)])

        XCTAssertEqual(total.value, 2)
        XCTAssertEqual(total.report.excludedCount, 1)
    }

    func testBreakdownAmountsMatchTotals() {
        let converter = CurrencyConverter(mainCurrency: "USD", rates: Rates(unitsPerDollar: ["EUR": 0.8]))

        XCTAssertEqual(converter.amountInBreakdown(of: entry(8, "EUR")), 10, accuracy: 1e-12)
        XCTAssertEqual(converter.amountInBreakdown(of: entry(8, "JPY")), 0)
        XCTAssertEqual(converter.amountInBreakdown(of: entry(8, nil)), 8)
    }

    func testReportsMerge() {
        let converter = CurrencyConverter(mainCurrency: "USD", rates: Rates(unitsPerDollar: ["EUR": 0.8]))
        var report = converter.total(of: [entry(1, "EUR"), entry(1, "JPY")]).report
        report.merge(converter.total(of: [entry(1, "EUR"), entry(1, "KRW")]).report)

        XCTAssertEqual(report.convertedCount, 2)
        XCTAssertEqual(report.excludedCount, 2)
        XCTAssertEqual(report.excludedCurrencies, ["JPY", "KRW"])
    }
}
