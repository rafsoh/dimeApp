//
//  CurrencyPreferencesTests.swift
//  dimeTests
//

@testable import dime
import XCTest

final class CurrencyPreferencesTests: XCTestCase {
    func testFractionDigits() {
        XCTAssertEqual(CurrencyDigits.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(CurrencyDigits.fractionDigits(for: "krw"), 0)
        XCTAssertEqual(CurrencyDigits.fractionDigits(for: "KWD"), 3)
        XCTAssertEqual(CurrencyDigits.fractionDigits(for: "USD"), 2)
        XCTAssertEqual(CurrencyDigits.fractionDigits(for: "EUR"), 2)
    }

    func testDefaultCurrencyIsTheMainOneUnlessTheFeatureIsOn() {
        XCTAssertEqual(CurrencyPreferences.defaultCurrency(mainCurrency: "sgd", multipleCurrenciesEnabled: false, recent: ["EUR"]), "SGD")
        XCTAssertEqual(CurrencyPreferences.defaultCurrency(mainCurrency: "SGD", multipleCurrenciesEnabled: true, recent: []), "SGD")
        XCTAssertEqual(CurrencyPreferences.defaultCurrency(mainCurrency: "SGD", multipleCurrenciesEnabled: true, recent: ["EUR", "JPY"]), "EUR")
    }

    func testRecentCurrencies() {
        var recent: [String] = []

        for code in ["EUR", "jpy", "USD", "EUR", "GBP", "CHF", "AUD"] {
            recent = CurrencyPreferences.recording(code, in: recent)
        }

        XCTAssertEqual(recent, ["AUD", "CHF", "GBP", "EUR", "USD"])
        XCTAssertEqual(CurrencyPreferences.pickerOrder(codes: ["AUD", "CHF", "EUR", "GBP", "JPY", "SGD", "USD"], recent: ["EUR", "SGD"], mainCurrency: "sgd"), ["SGD", "EUR", "AUD", "CHF", "GBP", "JPY", "USD"])
        XCTAssertTrue(CurrencyPreferences.isSameCurrency(nil, as: "sgd", mainCurrency: "SGD"))
        XCTAssertFalse(CurrencyPreferences.isSameCurrency("EUR", as: nil, mainCurrency: "SGD"))
    }

    // The pad's arithmetic before currencies had their own digits, kept to compare against.
    private struct LegacyPad {
        var price = 0.0
        var isEditingDecimal = false
        var assigned = 0

        mutating func type(_ number: Int, entryType: Int) {
            if entryType == 1 {
                price *= 10
                price += Double(number) / 100
            } else if isEditingDecimal {
                if assigned == 0 {
                    price += Double(number) / 10
                    assigned = 1
                } else if assigned == 1 {
                    price += Double(number) / 100
                    assigned = 2
                }
            } else {
                price *= 10
                price += Double(number)
            }
        }

        mutating func delete(entryType: Int) {
            if entryType == 1 {
                price = Double(Int(price * 10)) / 100
            } else if !isEditingDecimal {
                price = Double(Int(price / 10))
            } else if assigned == 0 {
                isEditingDecimal = false
            } else if assigned == 1 {
                price = Double(Int(price))
                assigned = 0
            } else {
                price = Double(Int(price * 10)) / 10
                assigned = 1
            }
        }
    }

    private struct Pad {
        var price = 0.0
        var isEditingDecimal = false
        var assigned = 0
        let fractionDigits: Int

        mutating func type(_ number: Int, entryType: Int) {
            if entryType == 1 {
                price = AmountEntry.shiftingIn(number, to: price, fractionDigits: fractionDigits)
            } else if isEditingDecimal {
                if let next = AmountEntry.appendingDecimal(number, to: price, assigned: assigned, fractionDigits: fractionDigits) {
                    price = next
                    assigned += 1
                }
            } else {
                price = AmountEntry.appendingWhole(number, to: price)
            }
        }

        mutating func delete(entryType: Int) {
            if entryType == 1 {
                price = AmountEntry.shiftingOut(of: price, fractionDigits: fractionDigits)
            } else if !isEditingDecimal {
                price = AmountEntry.removingWhole(from: price)
            } else if assigned == 0 {
                isEditingDecimal = false
            } else {
                price = AmountEntry.removingDecimal(from: price, assigned: assigned)
                assigned -= 1
            }
        }
    }

    func testTwoDigitEntryIsUnchanged() {
        var seed: UInt64 = 11

        func next(_ range: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(range))
        }

        for entryType in [1, 2] {
            for _ in 0 ..< 500 {
                var legacy = LegacyPad()
                var pad = Pad(fractionDigits: 2)

                for _ in 0 ..< 14 {
                    switch next(10) {
                    case 0 ..< 6:
                        let digit = next(10)
                        legacy.type(digit, entryType: entryType)
                        pad.type(digit, entryType: entryType)
                    case 6 ..< 8:
                        legacy.delete(entryType: entryType)
                        pad.delete(entryType: entryType)
                    default:
                        legacy.isEditingDecimal = true
                        pad.isEditingDecimal = true
                    }

                    XCTAssertEqual(pad.price.bitPattern, legacy.price.bitPattern)
                    XCTAssertEqual(pad.assigned, legacy.assigned)
                    XCTAssertEqual(
                        AmountEntry.display(pad.price, entryType: entryType, isEditingDecimal: pad.isEditingDecimal, assigned: pad.assigned, fractionDigits: 2),
                        legacyDisplay(legacy, entryType: entryType)
                    )
                }
            }
        }
    }

    private func legacyDisplay(_ pad: LegacyPad, entryType: Int) -> String {
        if entryType == 1 {
            return String(format: "%.2f", pad.price)
        }

        if pad.isEditingDecimal {
            switch pad.assigned {
            case 0: return String(format: "%.0f", pad.price) + "."
            case 1: return String(format: "%.1f", pad.price)
            default: return String(format: "%.2f", pad.price)
            }
        }

        return String(format: "%.0f", pad.price)
    }

    func testEntryFollowsTheCurrencysDigits() {
        var yen = Pad(fractionDigits: 0)
        [1, 2, 3, 4].forEach { yen.type($0, entryType: 1) }
        XCTAssertEqual(yen.price, 1_234)
        XCTAssertEqual(AmountEntry.display(yen.price, entryType: 1, isEditingDecimal: false, assigned: 0, fractionDigits: 0), "1234")
        yen.delete(entryType: 1)
        XCTAssertEqual(yen.price, 123)

        var dinar = Pad(fractionDigits: 3)
        [1, 2, 3, 4].forEach { dinar.type($0, entryType: 1) }
        XCTAssertEqual(dinar.price, 1.234, accuracy: 1e-12)
        XCTAssertEqual(AmountEntry.display(dinar.price, entryType: 1, isEditingDecimal: false, assigned: 0, fractionDigits: 3), "1.234")
        dinar.delete(entryType: 1)
        XCTAssertEqual(dinar.price, 0.123, accuracy: 1e-12)

        var decimalDinar = Pad(fractionDigits: 3)
        decimalDinar.type(5, entryType: 2)
        decimalDinar.isEditingDecimal = true
        [1, 2, 3, 4].forEach { decimalDinar.type($0, entryType: 2) }
        XCTAssertEqual(decimalDinar.assigned, 3)
        XCTAssertEqual(AmountEntry.display(decimalDinar.price, entryType: 2, isEditingDecimal: true, assigned: 3, fractionDigits: 3), "5.123")

        var decimalYen = Pad(fractionDigits: 0)
        decimalYen.type(5, entryType: 2)
        decimalYen.isEditingDecimal = true
        decimalYen.type(1, entryType: 2)
        XCTAssertEqual(decimalYen.price, 5)
        XCTAssertEqual(decimalYen.assigned, 0)
    }

    func testTruncatingToFewerDigits() {
        XCTAssertEqual(AmountEntry.truncated(12.34, fractionDigits: 0), 12)
        XCTAssertEqual(AmountEntry.truncated(12.345, fractionDigits: 2), 12.34, accuracy: 1e-12)
        XCTAssertEqual(AmountEntry.truncated(0.29, fractionDigits: 2), 0.29, accuracy: 1e-12)
        XCTAssertEqual(AmountEntry.truncated(1.005, fractionDigits: 3), 1.005, accuracy: 1e-12)
    }
}
