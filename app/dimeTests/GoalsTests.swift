//
//  GoalsTests.swift
//  dimeTests
//
//  Goals and debts are accounts. Putting money in or paying off is a transfer, so it never counts as spending or
//  income; spending from a goal counts as spending but not against a budget; a payment towards a debt with a
//  rate pays that month's interest first.
//

import CoreData
@testable import dime
import XCTest

final class GoalsTests: XCTestCase {
    private let dataController = DataController.shared
    private var inserted: [NSManagedObject] = []
    private var mainCurrency: String!

    private var context: NSManagedObjectContext {
        dataController.container.viewContext
    }

    private var converter: CurrencyConverter {
        dataController.currencyConverter
    }

    override func setUpWithError() throws {
        mainCurrency = CurrencyConverter.mainCurrency(in: UserDefaults(suiteName: CurrencyConverter.appGroup))
    }

    override func tearDownWithError() throws {
        for object in inserted where !object.isDeleted && object.managedObjectContext != nil {
            context.delete(object)
        }
        inserted = []
        try context.save()
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func goal(target: Double = 3_000, alreadySaved: Double = 0) -> Account {
        let account = dataController.addGoal(named: "Trip \(UUID().uuidString.prefix(6))", symbol: "airplane", target: target, repeatsMonthly: false, deadline: nil, alreadySaved: alreadySaved)
        inserted.append(account)
        return account
    }

    private func debt(owed: Double, rate: Double = 0, payment: Double = 0) -> Account {
        let account = dataController.addDebt(named: "Loan \(UUID().uuidString.prefix(6))", symbol: "car", owed: owed, yearlyRate: rate, payment: payment)
        inserted.append(account)
        return account
    }

    @discardableResult
    private func spend(_ amount: Double, in account: Account?) -> Transaction {
        let transaction = dataController.insertTransaction(note: "Test", category: nil, income: false, amount: amount, currencyCode: mainCurrency, account: account, date: Date.now.addingTimeInterval(-60))
        inserted.append(transaction)
        try? context.save()
        return transaction
    }

    @discardableResult
    private func transfer(_ amount: Double, from: AccountChoice, to: AccountChoice) -> (outgoing: Transaction, incoming: Transaction) {
        let legs = dataController.saveTransfer(from: from, to: to, amount: amount, currencyCode: mainCurrency, date: Date.now.addingTimeInterval(-60), note: "")
        inserted.append(legs.outgoing)
        inserted.append(legs.incoming)
        return legs
    }

    // MARK: - Goal maths

    func testPerMonthCountsTheMonthsUntilTheDeadline() {
        let progress = GoalProgress(saved: 500, target: 3_000, deadline: date(2027, 6, 1), repeatsMonthly: false, savedThisMonth: 0, now: date(2026, 11, 28))

        XCTAssertEqual(progress.monthsLeft, 7)
        XCTAssertEqual(try XCTUnwrap(progress.perMonth), 2_500 / 7, accuracy: 0.0001)
        XCTAssertEqual(progress.share, 500 / 3_000, accuracy: 0.0001)
        XCTAssertFalse(progress.isReached)
        XCTAssertFalse(progress.isOverdue)
    }

    func testADeadlineThisMonthLeavesOneMonth() {
        let progress = GoalProgress(saved: 0, target: 300, deadline: date(2026, 11, 30), repeatsMonthly: false, savedThisMonth: 0, now: date(2026, 11, 28))

        XCTAssertEqual(progress.monthsLeft, 1)
        XCTAssertEqual(progress.perMonth, 300)
    }

    func testAPassedDeadlineIsOverdueWithNoMonthlyAmount() {
        let progress = GoalProgress(saved: 100, target: 300, deadline: date(2026, 10, 1), repeatsMonthly: false, savedThisMonth: 0, now: date(2026, 11, 28))

        XCTAssertNil(progress.monthsLeft)
        XCTAssertNil(progress.perMonth)
        XCTAssertTrue(progress.isOverdue)
        XCTAssertEqual(progress.remaining, 200)
    }

    func testAReachedGoalStaysFullAndNeedsNothingMore() {
        let progress = GoalProgress(saved: 3_200, target: 3_000, deadline: date(2027, 6, 1), repeatsMonthly: false, savedThisMonth: 0, now: date(2026, 11, 28))

        XCTAssertTrue(progress.isReached)
        XCTAssertEqual(progress.share, 1)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertNil(progress.perMonth)
        XCTAssertFalse(progress.isOverdue)
    }

    func testAMonthlyGoalFillsWithThisMonthOnly() {
        let progress = GoalProgress(saved: 2_400, target: 300, deadline: nil, repeatsMonthly: true, savedThisMonth: 150, now: date(2026, 11, 28))

        XCTAssertEqual(progress.share, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.remaining, 150)
        XCTAssertFalse(progress.isReached)
        XCTAssertNil(progress.monthsLeft)
    }

    // MARK: - Debt maths

    func testWithoutInterestPaymentsDivideTheDebt() throws {
        let projection = try XCTUnwrap(DebtProjection.make(owed: 1_000, yearlyRate: 0, payment: 300))

        XCTAssertEqual(projection.months, 4)
        XCTAssertEqual(projection.interest, 0)
    }

    func testInterestLengthensTheDebt() throws {
        let projection = try XCTUnwrap(DebtProjection.make(owed: 6_900, yearlyRate: 6.9, payment: 310))
        let withoutInterest = try XCTUnwrap(DebtProjection.make(owed: 6_900, yearlyRate: 0, payment: 310))

        XCTAssertEqual(projection.months, 24)
        XCTAssertGreaterThan(projection.months, withoutInterest.months)
        XCTAssertEqual(projection.interest, 510, accuracy: 30)
    }

    func testAPaymentBelowTheInterestNeverEnds() {
        XCTAssertNil(DebtProjection.make(owed: 10_000, yearlyRate: 24, payment: 200))
        XCTAssertNil(DebtProjection.make(owed: 1_000, yearlyRate: 5, payment: 0))
    }

    func testNothingOwedIsAlreadyPaidOff() {
        XCTAssertEqual(DebtProjection.make(owed: 0, yearlyRate: 5, payment: 0), DebtProjection(months: 0, interest: 0))
    }

    func testMonthlyInterestIsToTheCent() {
        XCTAssertEqual(DebtProjection.monthlyInterest(owed: 6_900, yearlyRate: 6.9), 39.68)
        XCTAssertEqual(DebtProjection.monthlyInterest(owed: 6_900, yearlyRate: 0), 0)
    }

    func testPaidShareFollowsWhatWasBorrowed() {
        let status = DebtStatus(owed: 6_900, borrowed: 12_000, yearlyRate: 0, payment: 0)
        XCTAssertEqual(status.paidShare, 5_100 / 12_000, accuracy: 0.0001)
        XCTAssertFalse(status.isPaidOff)
        XCTAssertTrue(DebtStatus(owed: 0, borrowed: 12_000, yearlyRate: 0, payment: 0).isPaidOff)
    }

    // MARK: - Goals in the store

    func testAGoalsBalanceIsWhatWasSavedPlusWhatWentInLessWhatWasSpent() {
        let trip = goal(alreadySaved: 500)
        transfer(200, from: .main, to: .account(trip))
        spend(120, in: trip)

        XCTAssertEqual(trip.balance(using: converter).value, 580, accuracy: 0.0001)
        XCTAssertEqual(trip.goalProgress(using: converter).saved, 580, accuracy: 0.0001)
    }

    func testPuttingMoneyIntoAGoalIsNotSpending() {
        let before = dataController.getLogViewTotalSpent(type: 3)
        let trip = goal()
        transfer(250, from: .main, to: .account(trip))

        XCTAssertEqual(dataController.getLogViewTotalSpent(type: 3), before, accuracy: 0.0001)
    }

    func testSpendingFromAGoalLeavesBudgetsAlone() throws {
        let budget = MainBudget(context: context)
        budget.amount = 1_000
        budget.type = 3
        budget.startDate = Calendar.current.date(byAdding: .day, value: -2, to: Date.now)
        inserted.append(budget)
        try context.save()

        let before = dataController.budgetLeftover(overallBudget: budget).value
        let trip = goal()
        transfer(400, from: .main, to: .account(trip))
        let flights = spend(300, in: trip)

        XCTAssertEqual(dataController.budgetLeftover(overallBudget: budget).value, before, accuracy: 0.0001)
        XCTAssertFalse(budget.accountPredicate.evaluate(with: flights))

        let groceries = spend(40, in: nil)
        XCTAssertTrue(budget.accountPredicate.evaluate(with: groceries))
        XCTAssertEqual(dataController.budgetLeftover(overallBudget: budget).value, before - 40, accuracy: 0.0001)
    }

    func testDeletingAGoalReturnsWhatWentIn() {
        let trip = goal()
        let legs = transfer(200, from: .main, to: .account(trip))

        dataController.deleteAccount(trip)

        XCTAssertTrue(legs.outgoing.isGone)
        XCTAssertTrue(legs.incoming.isGone)
    }

    func testClosedGoalsLeaveTheList() {
        let trip = goal()
        XCTAssertTrue(dataController.accounts(of: .goal).contains(trip))

        dataController.setClosed(trip, true)
        XCTAssertFalse(dataController.accounts(of: .goal).contains(trip))
        XCTAssertTrue(dataController.accounts(of: .goal, includingClosed: true).contains(trip))

        dataController.setClosed(trip, false)
        XCTAssertTrue(dataController.accounts(of: .goal).contains(trip))
    }

    func testGoalsAndDebtsAreNotEverydayAccounts() throws {
        let trip = goal()
        let loan = debt(owed: 1_000)
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        request.predicate = AccountKind.everyday.predicate
        let everyday = try context.fetch(request)

        XCTAssertFalse(everyday.contains(trip))
        XCTAssertFalse(everyday.contains(loan))
        XCTAssertTrue(Account.budgetablePredicate.evaluate(with: loan))
        XCTAssertFalse(Account.budgetablePredicate.evaluate(with: trip))
    }

    // MARK: - Debts in the store

    func testADebtStartsAtWhatsOwedAndPaymentsBringItDown() {
        let loan = debt(owed: 1_000)
        XCTAssertEqual(loan.debtStatus(using: converter).owed, 1_000, accuracy: 0.0001)

        transfer(300, from: .main, to: .account(loan))
        let status = loan.debtStatus(using: converter)

        XCTAssertEqual(status.owed, 700, accuracy: 0.0001)
        XCTAssertEqual(status.paidShare, 0.3, accuracy: 0.0001)
    }

    func testAPaymentWithARatePaysTheMonthsInterestFirst() throws {
        let before = dataController.getLogViewTotalSpent(type: 3)
        let loan = debt(owed: 6_900, rate: 6.9, payment: 310)
        let legs = transfer(310, from: .main, to: .account(loan))

        let charge = try XCTUnwrap(dataController.logInterest(forPayment: legs.incoming))
        inserted.append(charge)

        XCTAssertEqual(charge.amount, 39.68, accuracy: 0.0001)
        XCTAssertEqual(charge.account, loan)
        XCTAssertEqual(charge.splitID, legs.incoming.transferID)
        XCTAssertEqual(loan.debtStatus(using: converter).owed, 6_900 - 310 + 39.68, accuracy: 0.0001)
        XCTAssertEqual(dataController.getLogViewTotalSpent(type: 3), before + 39.68, accuracy: 0.0001)

        // Logged once per payment.
        XCTAssertNil(dataController.logInterest(forPayment: legs.incoming))

        // Deleting the payment takes its interest with it.
        dataController.deleteTransaction(legs.outgoing)
        XCTAssertTrue(charge.isGone)
        XCTAssertEqual(loan.debtStatus(using: converter).owed, 6_900, accuracy: 0.0001)
    }

    func testAPaymentWithoutARateLogsNoInterest() {
        let loan = debt(owed: 500)
        let legs = transfer(100, from: .main, to: .account(loan))

        XCTAssertNil(dataController.logInterest(forPayment: legs.incoming))
    }

    func testEditingWhatsOwedKeepsThePayments() {
        let loan = debt(owed: 1_000)
        transfer(200, from: .main, to: .account(loan))

        dataController.updateDebt(loan, name: loan.wrappedName, symbol: "car", owed: 900, yearlyRate: 0, payment: 0)

        XCTAssertEqual(loan.debtStatus(using: converter).owed, 900, accuracy: 0.0001)
        XCTAssertEqual(loan.transactionCount, 1)
        XCTAssertEqual(loan.targetAmount, 1_000)
    }
}
