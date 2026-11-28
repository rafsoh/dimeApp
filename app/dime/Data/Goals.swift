//
//  Goals.swift
//  dime
//
//  Saving goals and debts. Both are accounts (see `AccountKind`): putting money towards a goal or paying off a
//  debt is a transfer, which spending and income already leave out. What's here works out their balances and
//  where they're heading, and creates, edits and closes them.
//

import CoreData
import Foundation

// MARK: - Balances

extension Account {
    /// What's in the account up to `date`: its starting balance plus what came in, minus what went out, in the main
    /// currency. Positive is money set aside; below zero is money owed.
    func balance(using converter: CurrencyConverter, asOf date: Date = .now) -> MoneyTotal {
        guard let context = managedObjectContext, !isDeleted else {
            return MoneyTotal()
        }

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", #keyPath(Transaction.account), self),
            NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), date as CVarArg)
        ])

        var total = ((try? context.fetch(request)) ?? []).total(using: converter, signed: true)
        total.value += startingBalance
        return total
    }

    /// What came in, less what went out, since the start of this month. A monthly goal's progress.
    func netThisMonth(using converter: CurrencyConverter, now: Date = .now) -> Double {
        guard let context = managedObjectContext, !isDeleted else {
            return 0
        }

        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", #keyPath(Transaction.account), self),
            NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), start as CVarArg),
            NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), now as CVarArg)
        ])

        return ((try? context.fetch(request)) ?? []).total(using: converter, signed: true).value
    }

    /// Where a goal stands today.
    func goalProgress(using converter: CurrencyConverter, now: Date = .now) -> GoalProgress {
        GoalProgress(
            saved: balance(using: converter, asOf: now).value,
            target: targetAmount,
            deadline: targetDate,
            repeatsMonthly: repeatsMonthly,
            savedThisMonth: repeatsMonthly ? netThisMonth(using: converter, now: now) : 0,
            now: now
        )
    }

    /// Where a debt stands today.
    func debtStatus(using converter: CurrencyConverter, now: Date = .now) -> DebtStatus {
        DebtStatus(owed: -balance(using: converter, asOf: now).value, borrowed: targetAmount, yearlyRate: interestRate, payment: paymentAmount)
    }
}

// MARK: - Goal maths

/// A goal's progress. Pure, so it can be tested without a store.
struct GoalProgress: Equatable {
    /// What's in the goal.
    let saved: Double
    /// What it's saving up to, or each month's amount for a monthly goal. 0 for none.
    let target: Double
    let deadline: Date?
    let repeatsMonthly: Bool
    /// What went in this month, for a monthly goal.
    let savedThisMonth: Double
    let now: Date

    var hasTarget: Bool {
        target > 0
    }

    /// What the ring and bar fill to, 0 to 1: this month's share for a monthly goal.
    var share: Double {
        guard hasTarget else { return 0 }
        let value = repeatsMonthly ? savedThisMonth : saved
        return min(max(value / target, 0), 1)
    }

    /// What's still to save: to the target, or this month for a monthly goal.
    var remaining: Double {
        guard hasTarget else { return 0 }
        return max(0, target - (repeatsMonthly ? savedThisMonth : saved))
    }

    /// Saved up to the target, or this month's amount set aside.
    var isReached: Bool {
        hasTarget && remaining < 0.005
    }

    /// Months left until the deadline, counting this one, so a deadline next month leaves 2. Nil without a
    /// deadline, for a monthly goal, or once the deadline has passed.
    var monthsLeft: Int? {
        guard let deadline, !repeatsMonthly, deadline > now else { return nil }

        let calendar = Calendar.current
        let from = calendar.dateComponents([.year, .month], from: now)
        let to = calendar.dateComponents([.year, .month], from: deadline)
        let months = ((to.year ?? 0) - (from.year ?? 0)) * 12 + (to.month ?? 0) - (from.month ?? 0)

        return max(1, months)
    }

    /// What to put in each month to reach the target by the deadline.
    var perMonth: Double? {
        guard let monthsLeft, !isReached else { return nil }
        return remaining / Double(monthsLeft)
    }

    /// The deadline went by before the target was reached.
    var isOverdue: Bool {
        guard let deadline, !repeatsMonthly, !isReached else { return false }
        return deadline <= now
    }
}

// MARK: - Debt maths

/// A debt today and, from its rate and payment, when it ends. Pure, so it can be tested without a store.
struct DebtStatus: Equatable {
    /// What's still owed. Below zero when more was paid than owed.
    let owed: Double
    /// What was owed when it was added, for how much is paid off. 0 when unknown.
    let borrowed: Double
    /// The yearly interest rate, in percent.
    let yearlyRate: Double
    /// The usual monthly payment, or 0.
    let payment: Double

    var isPaidOff: Bool {
        owed < 0.005
    }

    /// How much of what was borrowed is paid off, 0 to 1.
    var paidShare: Double {
        guard borrowed > 0 else { return isPaidOff ? 1 : 0 }
        return min(max((borrowed - owed) / borrowed, 0), 1)
    }

    var projection: DebtProjection? {
        DebtProjection.make(owed: owed, yearlyRate: yearlyRate, payment: payment)
    }
}

struct DebtProjection: Equatable {
    /// Monthly payments until it's paid off, the last one perhaps smaller.
    let months: Int
    /// The interest those payments include.
    let interest: Double

    /// Paying `payment` every month, starting with the next. Nil without a payment, or when the payment doesn't
    /// cover the interest and the debt would never end.
    static func make(owed: Double, yearlyRate: Double, payment: Double) -> DebtProjection? {
        guard owed >= 0.005 else {
            return DebtProjection(months: 0, interest: 0)
        }
        guard payment > 0 else {
            return nil
        }

        let monthlyRate = max(0, yearlyRate) / 100 / 12
        var balance = owed
        var interest = 0.0
        var months = 0

        while balance >= 0.005 {
            let charge = balance * monthlyRate
            guard payment > charge else { return nil }

            interest += charge
            balance += charge - payment
            months += 1

            // A hundred years; anything longer isn't a plan.
            if months > 1200 {
                return nil
            }
        }

        return DebtProjection(months: months, interest: interest)
    }

    /// The month of the last payment.
    func payoffDate(from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: now) ?? now
    }

    /// A month's interest on what's owed, to the cent.
    static func monthlyInterest(owed: Double, yearlyRate: Double) -> Double {
        guard owed > 0, yearlyRate > 0 else { return 0 }
        return (owed * yearlyRate / 100 / 12 * 100).rounded() / 100
    }
}

// MARK: - Creating and editing

extension DataController {
    /// Goals or debts in their order. Closed ones come last when `includingClosed`.
    func accounts(of kind: AccountKind, includingClosed: Bool = false) -> [Account] {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        request.predicate = includingClosed ? kind.predicate : NSCompoundPredicate(andPredicateWithSubpredicates: [kind.predicate, Account.openPredicate]) as NSPredicate

        return results(for: request).sorted {
            ($0.isClosed ? 1 : 0, $0.order, $0.key) < ($1.isClosed ? 1 : 0, $1.order, $1.key)
        }
    }

    /// Adds a goal. `target` is what it saves up to, or each month's amount when `repeatsMonthly`.
    @discardableResult
    func addGoal(named name: String, symbol: String, target: Double, repeatsMonthly: Bool, deadline: Date?, alreadySaved: Double) -> Account {
        let account = addAccount(named: name, symbol: symbol)
        account.accountKind = .goal
        account.targetAmount = max(0, target)
        account.repeatsMonthly = repeatsMonthly
        account.targetDate = repeatsMonthly ? nil : deadline
        account.startingBalance = max(0, alreadySaved)
        save()
        return account
    }

    /// Changes a goal. `alreadySaved` is what was in it before Dime knew about it, its starting balance.
    func updateGoal(_ goal: Account, name: String, symbol: String, target: Double, repeatsMonthly: Bool, deadline: Date?, alreadySaved: Double) {
        guard !goal.isGone else { return }

        goal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.symbol = symbol
        goal.targetAmount = max(0, target)
        goal.repeatsMonthly = repeatsMonthly
        goal.targetDate = repeatsMonthly ? nil : deadline
        goal.startingBalance = max(0, alreadySaved)
        save()
    }

    /// Adds a debt with what's owed on it today.
    @discardableResult
    func addDebt(named name: String, symbol: String, owed: Double, yearlyRate: Double, payment: Double) -> Account {
        let account = addAccount(named: name, symbol: symbol)
        account.accountKind = .debt
        account.startingBalance = -max(0, owed)
        account.targetAmount = max(0, owed)
        account.interestRate = max(0, yearlyRate)
        account.paymentAmount = max(0, payment)
        save()
        return account
    }

    /// Changes a debt. `owed` is what's owed today: the starting balance moves by the difference, so the payments
    /// already made stay as they are.
    func updateDebt(_ debt: Account, name: String, symbol: String, owed: Double, yearlyRate: Double, payment: Double) {
        guard !debt.isGone else { return }

        let current = -debt.balance(using: currencyConverter).value
        let newOwed = max(0, owed)

        if abs(newOwed - current) >= 0.005 {
            debt.startingBalance -= newOwed - current
        }

        // What's owed can grow past what was borrowed, such as a card used again; it's paid off from the larger amount.
        debt.targetAmount = max(debt.targetAmount, newOwed)
        debt.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        debt.symbol = symbol
        debt.interestRate = max(0, yearlyRate)
        debt.paymentAmount = max(0, payment)
        save()
    }

    /// Puts a goal or debt away, or brings it back. Its transactions stay.
    func setClosed(_ account: Account, _ closed: Bool) {
        guard !account.isGone else { return }
        account.closedAt = closed ? Date.now : nil
        save()
    }

    // MARK: Interest on payments

    /// The interest expenses logged with a payment, linked to it by its transfer id.
    func interestCharges(forTransfer transferID: UUID) -> [Transaction] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", #keyPath(Transaction.splitID), transferID as CVarArg),
            TransferPredicate.excluded
        ])
        return results(for: request)
    }

    /// A payment into a debt with a rate pays the month's interest first. The interest is logged as an expense in
    /// the debt, linked to the payment, so the debt goes down by what's left and the interest counts as spending.
    @discardableResult
    func logInterest(forPayment incoming: Transaction) -> Transaction? {
        guard incoming.isTransfer, incoming.income, let transferID = incoming.transferID,
              let debt = incoming.account, debt.isDebt, debt.interestRate > 0,
              interestCharges(forTransfer: transferID).isEmpty
        else {
            return nil
        }

        // What was owed before this payment.
        let owed = -debt.balance(using: currencyConverter, asOf: incoming.wrappedDate).value + (currencyConverter.convert(incoming.amount, from: incoming.currencyCode, on: incoming.wrappedDate) ?? incoming.amount)
        let interest = min(DebtProjection.monthlyInterest(owed: owed, yearlyRate: debt.interestRate), incoming.amount)

        guard interest >= 0.01 else {
            return nil
        }

        let charge = insertTransaction(note: String(localized: "Interest"), category: nil, income: false, amount: interest, currencyCode: currencyConverter.mainCurrency, account: debt, date: incoming.wrappedDate)
        charge.splitID = transferID
        autoCategoryQueue.keepUncategorised(charge)
        save()
        return charge
    }

    /// Deletes the interest logged with a payment, when the payment is deleted or stops being one.
    func deleteInterestCharges(forTransfer transferID: UUID?) {
        guard let transferID else { return }

        for charge in interestCharges(forTransfer: transferID) where !charge.isGone {
            container.viewContext.delete(charge)
        }
    }
}
