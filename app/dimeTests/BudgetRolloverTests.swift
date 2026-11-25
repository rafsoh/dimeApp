//
//  BudgetRolloverTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class BudgetRolloverTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Periods and carry

    func testMonthlyPeriodsCountWholeMonthsFromTheAnchor() {
        let rollover = BudgetRollover(type: 3, amount: 300, anchor: date(2026, 1, 15), balance: 0)

        XCTAssertEqual(rollover.periods(until: date(2026, 1, 15)), 0)
        XCTAssertEqual(rollover.periods(until: date(2026, 2, 15)), 1)
        XCTAssertEqual(rollover.periods(until: date(2026, 4, 15)), 3)
        XCTAssertEqual(rollover.periods(until: date(2027, 1, 15)), 12)
        // A start between grid lines (after an edit that moved the reset day) counts only finished periods.
        XCTAssertEqual(rollover.periods(until: date(2026, 3, 1)), 1)
        XCTAssertNil(rollover.periods(until: date(2026, 1, 14)))
    }

    func testDailyWeeklyAndYearlyPeriods() {
        XCTAssertEqual(BudgetRollover(type: 1, amount: 20, anchor: date(2026, 2, 26), balance: 0).periods(until: date(2026, 3, 3)), 5)
        XCTAssertEqual(BudgetRollover(type: 2, amount: 70, anchor: date(2026, 1, 4), balance: 0).periods(until: date(2026, 2, 1)), 4)
        XCTAssertEqual(BudgetRollover(type: 4, amount: 5000, anchor: date(2024, 6, 1), balance: 0).periods(until: date(2026, 6, 1)), 2)
    }

    func testCarryAddsEachPeriodsAmountToTheBalanceLessSpending() {
        let rollover = BudgetRollover(type: 3, amount: 200, anchor: date(2026, 1, 1), balance: 25)

        XCTAssertEqual(rollover.carryIn(at: date(2026, 1, 1), spentSinceAnchor: 0), 25)
        XCTAssertEqual(rollover.carryIn(at: date(2026, 3, 1), spentSinceAnchor: 350), 75)
        // Overspending carries forward as a negative amount.
        XCTAssertEqual(rollover.carryIn(at: date(2026, 3, 1), spentSinceAnchor: 600), -175)
        XCTAssertNil(rollover.carryIn(at: date(2025, 12, 1), spentSinceAnchor: 0))
    }

    func testSnapshotSpendsTheBudgetPlusWhatRolledIn() {
        let period = BudgetPeriod(type: 3, start: date(2026, 3, 1))

        let surplus = BudgetSnapshot(amount: 200, spent: 220, period: period, carryIn: 50)
        XCTAssertEqual(surplus.amount, 250)
        XCTAssertEqual(surplus.base, 200)
        XCTAssertFalse(surplus.isOver)
        XCTAssertEqual(surplus.difference, 30)

        // An overspend larger than the budget leaves less than nothing, which is already over.
        let deficit = BudgetSnapshot(amount: 200, spent: 0, period: period, carryIn: -260)
        XCTAssertEqual(deficit.amount, -60)
        XCTAssertTrue(deficit.isOver)
        XCTAssertEqual(deficit.share, 1)
        XCTAssertEqual(deficit.difference, 60)

        let plain = BudgetSnapshot(amount: 200, spent: 50, period: period)
        XCTAssertNil(plain.carryIn)
        XCTAssertEqual(plain.amount, 200)
    }

    // MARK: - Edits

    func testChangesFromEdits() {
        func make(was: Bool, now: Bool, type: Bool = false, category: Bool = false, amount: Bool = false, start: Bool = false) -> RolloverChange {
            RolloverChange.make(wasEnabled: was, isEnabled: now, isNew: false, typeChanged: type, categoryChanged: category, amountChanged: amount, startChanged: start)
        }

        XCTAssertEqual(make(was: false, now: false, amount: true), .unchanged)
        XCTAssertEqual(make(was: false, now: true, type: true), .start)
        XCTAssertEqual(make(was: true, now: false, amount: true), .stop)
        XCTAssertEqual(make(was: true, now: true), .unchanged)
        XCTAssertEqual(make(was: true, now: true, amount: true), .lockIn)
        XCTAssertEqual(make(was: true, now: true, start: true), .lockIn)
        XCTAssertEqual(make(was: true, now: true, type: true, amount: true), .reset)
        XCTAssertEqual(make(was: true, now: true, category: true), .reset)
    }

    func testApplyingChangesMovesTheAnchorAndBalance() {
        let context = DataController.shared.container.viewContext
        let budget = MainBudget(context: context)
        defer { context.delete(budget) }
        let march = date(2026, 3, 1)

        RolloverChange.start.apply(to: budget, currentStart: march, carry: 99)
        XCTAssertTrue(budget.rolloverEnabled)
        XCTAssertEqual(budget.rolloverAnchor, march)
        XCTAssertEqual(budget.rolloverBalance, 0)

        RolloverChange.lockIn.apply(to: budget, currentStart: date(2026, 4, 1), carry: -18)
        XCTAssertEqual(budget.rolloverAnchor, date(2026, 4, 1))
        XCTAssertEqual(budget.rolloverBalance, -18)

        RolloverChange.reset.apply(to: budget, currentStart: date(2026, 4, 6), carry: 40)
        XCTAssertEqual(budget.rolloverAnchor, date(2026, 4, 6))
        XCTAssertEqual(budget.rolloverBalance, 0)

        RolloverChange.unchanged.apply(to: budget, currentStart: date(2027, 1, 1), carry: 1)
        XCTAssertEqual(budget.rolloverAnchor, date(2026, 4, 6))

        RolloverChange.stop.apply(to: budget, currentStart: march, carry: 0)
        XCTAssertFalse(budget.rolloverEnabled)
        XCTAssertNil(budget.rolloverAnchor)
    }

    // MARK: - Against the store

    func testCarryAndLeftoverFromStoredTransactions() throws {
        let dataController = DataController.shared
        let context = dataController.container.viewContext
        var inserted: [NSManagedObject] = []
        defer {
            inserted.forEach(context.delete)
            try? context.save()
        }

        let mainCurrency = CurrencyConverter.mainCurrency(in: UserDefaults(suiteName: CurrencyConverter.appGroup))
        let category = dime.Category(context: context)
        category.id = UUID()
        category.name = "Rollover"
        category.order = 98
        inserted.append(category)

        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now))!
        let anchor = calendar.date(byAdding: .month, value: -2, to: current)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: current)!

        func add(_ amount: Double, on date: Date, income: Bool = false) {
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = amount
            transaction.currencyCode = mainCurrency
            transaction.income = income
            transaction.date = date
            transaction.day = calendar.startOfDay(for: date)
            transaction.month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            transaction.category = category
            inserted.append(transaction)
        }

        add(100, on: anchor.addingTimeInterval(3600))
        add(250, on: lastMonth.addingTimeInterval(3600))
        add(999, on: lastMonth.addingTimeInterval(7200), income: true)
        add(40, on: min(current.addingTimeInterval(3600), Date.now.addingTimeInterval(-60)))

        let budget = Budget(context: context)
        budget.id = UUID()
        budget.amount = 200
        budget.type = 3
        budget.startDate = current
        budget.category = category
        inserted.append(budget)
        try context.save()

        XCTAssertNil(dataController.rolloverCarryIn(for: budget, category: category, at: current))
        XCTAssertEqual(dataController.budgetLeftover(budget: budget).value, 160, accuracy: 0.001)

        budget.rolloverEnabled = true
        budget.rolloverAnchor = anchor
        // Two finished months of 200, less 350 spent; the income doesn't count.
        XCTAssertEqual(try XCTUnwrap(dataController.rolloverCarryIn(for: budget, category: category, at: current)), 50, accuracy: 0.001)
        XCTAssertEqual(dataController.budgetLeftover(budget: budget).value, 210, accuracy: 0.001)
        // Looking back at last month, only the month before it had finished.
        XCTAssertEqual(try XCTUnwrap(dataController.rolloverCarryIn(for: budget, category: category, at: lastMonth)), 100, accuracy: 0.001)
        XCTAssertNil(dataController.rolloverCarryIn(for: budget, category: category, at: calendar.date(byAdding: .month, value: -1, to: anchor)!))
    }
}
