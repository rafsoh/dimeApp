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

    func testDefaultCurrencyIsTheLastUsedOneOrTheMainOne() {
        XCTAssertEqual(CurrencyPreferences.defaultCurrency(mainCurrency: "sgd", recent: []), "SGD")
        XCTAssertEqual(CurrencyPreferences.defaultCurrency(mainCurrency: "SGD", recent: ["EUR", "JPY"]), "EUR")
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

final class CalculatorExpressionTests: XCTestCase {
    /// Types keys the way the pad would: digits, ".", + - * / and < for delete.
    private func typed(_ keys: String, fractionDigits: Int = 2) -> CalculatorExpression {
        var sum = CalculatorExpression()

        for key in keys {
            switch key {
            case "0"..."9":
                sum.append(digit: Int(String(key))!, fractionDigits: fractionDigits)
            case ".":
                sum.appendDecimalPoint(fractionDigits: fractionDigits)
            case "+":
                sum.apply(.add)
            case "-":
                sum.apply(.subtract)
            case "*":
                sum.apply(.multiply)
            case "/":
                sum.apply(.divide)
            case "<":
                sum.deleteLast()
            default:
                XCTFail("No key for \(key)")
            }
        }

        return sum
    }

    func testSplittingABill() {
        let sum = typed("86.40/3")
        XCTAssertEqual(sum.text(), "86.40 ÷ 3")
        XCTAssertEqual(sum.total(fractionDigits: 2), .success(28.8))
    }

    func testTimesAndDivideGoFirst() {
        XCTAssertEqual(typed("2+3*4").total(fractionDigits: 2), .success(14))
        XCTAssertEqual(typed("10-4/2").total(fractionDigits: 2), .success(8))
        XCTAssertEqual(typed("4.50+12.90+3.20").total(fractionDigits: 2), .success(20.6))
    }

    func testRoundsOnceAtTheEnd() {
        XCTAssertEqual(typed("10/3").total(fractionDigits: 2), .success(3.33))
        XCTAssertEqual(typed("0.1+0.2").total(fractionDigits: 2), .success(0.3))
        XCTAssertEqual(typed("10/3*3").total(fractionDigits: 2), .success(10))
        XCTAssertEqual(typed("1000/3", fractionDigits: 0).total(fractionDigits: 0), .success(333))
    }

    func testAnOperatorWaitingForItsNumberIsIgnored() {
        let sum = typed("12.50+")
        XCTAssertEqual(sum.pendingOperator, .add)
        XCTAssertEqual(sum.total(fractionDigits: 2), .success(12.5))
    }

    func testASecondOperatorReplacesTheFirst() {
        let sum = typed("5+*2")
        XCTAssertEqual(sum.text(), "5 × 2")
        XCTAssertEqual(sum.total(fractionDigits: 2), .success(10))
    }

    func testAnOperatorNeedsANumberFirst() {
        var sum = CalculatorExpression()
        XCTAssertFalse(sum.apply(.add))
        XCTAssertTrue(sum.isEmpty)
    }

    func testAmountsTakeTheCurrencysDecimalsAndFactorsTakeMore() {
        XCTAssertEqual(typed("1.234").text(), "1.23")
        XCTAssertEqual(typed("64*1.15").total(fractionDigits: 2), .success(73.6))
        XCTAssertEqual(typed("100*1.08255").text(), "100 × 1.0825")
        XCTAssertEqual(typed("1.234", fractionDigits: 3).text(), "1.234")
    }

    func testZeroDecimalCurrencies() {
        XCTAssertEqual(typed("12.5", fractionDigits: 0).text(), "125")
        XCTAssertEqual(typed("1000*1.1", fractionDigits: 0).total(fractionDigits: 0), .success(1100))
    }

    func testTypingNumbers() {
        XCTAssertEqual(typed("05").text(), "5")
        XCTAssertEqual(typed(".5").text(), "0.5")
        XCTAssertEqual(typed("12..5").text(), "12.5")
        XCTAssertEqual(typed("12.+3").text(), "12 + 3")
        XCTAssertEqual(typed("1234567890").text(), "123456789")
    }

    func testDeleteRemovesOperatorsToo() {
        XCTAssertEqual(typed("12+3<").text(), "12 +")
        XCTAssertEqual(typed("12+3<<").text(), "12")
        XCTAssertTrue(typed("12+3<<<<").isEmpty)
        XCTAssertTrue(typed("<").isEmpty)
    }

    func testWhatCantBeWorkedOut() {
        XCTAssertEqual(typed("5/0").total(fractionDigits: 2), .failure(.divisionByZero))
        XCTAssertEqual(typed("5-8").total(fractionDigits: 2), .failure(.negative))
        XCTAssertEqual(typed("5-5").total(fractionDigits: 2), .success(0))
        XCTAssertEqual(typed("99999999*2").total(fractionDigits: 2), .failure(.tooLarge))
    }

    func testEqualsPutsTheTotalInPlaceOfTheSum() {
        var sum = typed("86.40/3")
        XCTAssertEqual(sum.collapse(fractionDigits: 2), .success(28.8))
        XCTAssertEqual(sum.text(), "28.80")
        XCTAssertFalse(sum.hasOperator)

        sum.apply(.add)
        sum.append(digit: 1, fractionDigits: 2)
        XCTAssertEqual(sum.total(fractionDigits: 2), .success(29.8))

        var broken = typed("5/0")
        XCTAssertEqual(broken.collapse(fractionDigits: 2), .failure(.divisionByZero))
        XCTAssertEqual(broken.text(), "5 ÷ 0")

        var empty = typed("5-5")
        empty.collapse(fractionDigits: 2)
        XCTAssertTrue(empty.isEmpty)
    }

    func testEqualsLeavesWholeTotalsWithoutDecimals() {
        var whole = typed("5*3")
        whole.collapse(fractionDigits: 2)
        XCTAssertEqual(whole.text(), "15")

        var tip = typed("64*1.25")
        tip.collapse(fractionDigits: 2)
        XCTAssertEqual(tip.text(), "80")

        var cents = typed("10/4")
        cents.collapse(fractionDigits: 2)
        XCTAssertEqual(cents.text(), "2.50")

        var dinar = typed("1/8", fractionDigits: 3)
        dinar.collapse(fractionDigits: 3)
        XCTAssertEqual(dinar.text(), "0.125")
    }

    func testStartingFromAnAmount() {
        XCTAssertEqual(CalculatorExpression(number: "12.").text(), "12.")
        XCTAssertEqual(CalculatorExpression(number: "12.50").text(), "12.50")
        XCTAssertTrue(CalculatorExpression(number: "0").isEmpty)
        XCTAssertEqual(CalculatorExpression(amount: 5.8, fractionDigits: 2).text(), "5.80")
        XCTAssertEqual(CalculatorExpression(amount: 12, fractionDigits: 2).text(), "12")
        XCTAssertTrue(CalculatorExpression(amount: 0, fractionDigits: 2).isEmpty)
        XCTAssertEqual(typed("8.6/3").text(decimalSeparator: ","), "8,6 ÷ 3")
    }
}
