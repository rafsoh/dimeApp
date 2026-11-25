//
//  Helper.swift
//  dime
//
//  Created by Rafael Soh on 13/8/22.
//

import CoreData
import Foundation

/// How a transaction without a category is shown.
enum Uncategorised {
    static let colour = "#8E8E93"
    static var name: String { String(localized: "No Category") }

    static func symbol(income: Bool) -> String {
        income ? "arrow.down.left" : "arrow.up.right"
    }
}

extension Transaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedDate: Date {
        date ?? Date.now
    }

    var wrappedNote: String {
        note ?? ""
    }

    /// What to call the transaction on screen: its note, or when it has none, the accounts of a transfer
    /// ("Main → Savings") or "Expense" or "Income".
    var displayTitle: String {
        let trimmed = wrappedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if isTransfer {
            return transferTitle ?? String(localized: "Transfer")
        }
        return income ? String(localized: "Income") : String(localized: "Expense")
    }

    var money: MoneyEntry {
        MoneyEntry(id: id, amount: amount, currencyCode: currencyCode, date: wrappedDate, income: income)
    }

    var wrappedCategoryName: String {
        category?.wrappedName ?? Uncategorised.name
    }

    var wrappedColour: String {
        category?.wrappedColour ?? Uncategorised.colour
    }

    var nextTransactionDate: Date {
        recurrenceDate(after: day ?? Date.now) ?? date ?? Date.now
    }

    func recurrenceDate(after date: Date) -> Date? {
        // Records from older app versions can have a coefficient of 0, which would never advance.
        let interval = max(1, Int(recurringCoefficient))

        if recurringType == 1 {
            return Calendar.current.date(byAdding: .day, value: interval, to: date)
        } else if recurringType == 2 {
            return Calendar.current.date(byAdding: .day, value: interval * 7, to: date)
        } else if recurringType == 3 {
            return Calendar.current.date(byAdding: .month, value: interval, to: date)
        }

        return nil
    }
}

extension Sequence where Element == Transaction {
    func total(using converter: CurrencyConverter, signed: Bool = false) -> MoneyTotal {
        converter.total(of: lazy.map(\.money), signed: signed)
    }
}

extension TemplateTransaction {
    /// The most Quick Add templates there can be, as many as the widgets show.
    static let quickAddLimit = 4

    var wrappedAmount: Double {
        amount
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? Uncategorised.colour
    }

    /// What to call the template on screen: its note, then its category, then "Expense" or "Income".
    var displayTitle: String {
        let trimmed = wrappedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let category {
            return category.wrappedName
        }
        return income ? String(localized: "Income") : String(localized: "Expense")
    }
}

extension Category {
    var wrappedColour: String {
        colour ?? "#FFFFFF"
    }

    var wrappedEmoji: String {
        emoji ?? "😄️"
    }

    var wrappedName: String {
        name ?? ""
    }

    var wrappedDate: Date {
        dateCreated ?? Date.now
    }

    var fullName: String {
        wrappedEmoji + "  " + wrappedName
    }

    var allTransactions: [Transaction] {
        let set = transactions as? Set<Transaction> ?? []
        return set.sorted {
            $0.wrappedDate < $1.wrappedDate
        }
    }

    var transactionCount: Int {
        transactions?.count ?? 0
    }
}

public extension Budget {
    var wrappedColour: String {
        category?.wrappedColour ?? "#FFFFFF"
    }

    var wrappedName: String {
        category?.wrappedName ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var fullName: String {
        return wrappedEmoji + " " + wrappedName
    }

    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }
        return startDate ?? Date.now
    }
}

public extension MainBudget {
    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }

        return startDate ?? Date.now
    }
}

// MARK: - Rollover

/// The fields both budget entities share, so rollover works the same for the overall budget and category budgets.
protocol RolloverBudget: NSManagedObject {
    var amount: Double { get set }
    var type: Int16 { get set }
    var startDate: Date? { get set }
    var rolloverEnabled: Bool { get set }
    var rolloverAnchor: Date? { get set }
    var rolloverBalance: Double { get set }
    /// Which accounts the budget counts. Nil counts every account.
    var accountScope: String? { get set }
}

extension Budget: RolloverBudget {}
extension MainBudget: RolloverBudget {}

/// Carries what's left (or overspent) in each period into the next.
///
/// Nothing is stored per period. From `anchor` on, every period adds `amount` and every expense takes away from it,
/// so the carry into a period is `balance + periods since anchor × amount − spent since anchor`. Edits that change the
/// budget's shape lock the carry so far into `balance` and move `anchor` to the new current period, so earlier periods
/// keep the settings they had.
struct BudgetRollover: Equatable {
    /// 1 day, 2 week, 3 month, 4 year, as stored on `Budget.type`.
    let type: Int
    let amount: Double
    let anchor: Date
    let balance: Double

    init(type: Int, amount: Double, anchor: Date, balance: Double) {
        self.type = type
        self.amount = amount
        self.anchor = anchor
        self.balance = balance
    }

    init?(_ budget: RolloverBudget) {
        guard budget.rolloverEnabled, let anchor = budget.rolloverAnchor else { return nil }
        self.init(type: Int(budget.type), amount: budget.amount, anchor: anchor, balance: budget.rolloverBalance)
    }

    static func step(for type: Int) -> (component: Calendar.Component, value: Int) {
        switch type {
        case 1:
            return (.day, 1)
        case 2:
            return (.day, 7)
        case 4:
            return (.year, 1)
        default:
            return (.month, 1)
        }
    }

    private func start(after periods: Int) -> Date {
        let step = Self.step(for: type)
        return Calendar.current.date(byAdding: step.component, value: step.value * periods, to: anchor) ?? anchor
    }

    /// Whole periods between the anchor and a period starting at `start`, or nil when it starts before the anchor.
    func periods(until start: Date) -> Int? {
        guard start >= anchor else { return nil }
        let step = Self.step(for: type)
        let raw = Calendar.current.dateComponents([step.component], from: anchor, to: start).value(for: step.component) ?? 0
        var count = max(0, raw / step.value)
        while self.start(after: count + 1) <= start {
            count += 1
        }
        while count > 0, self.start(after: count) > start {
            count -= 1
        }
        return count
    }

    /// What carries into the period starting at `start`, given what was spent from the anchor up to it.
    func carryIn(at start: Date, spentSinceAnchor: Double) -> Double? {
        guard let periods = periods(until: start) else { return nil }
        return balance + Double(periods) * amount - spentSinceAnchor
    }

    /// Expenses from the anchor up to `start`; matches nothing when the period starts before the anchor.
    /// Transfers are never spending. `accounts` limits it to the budget's accounts.
    static func spendingPredicate(_ rollover: BudgetRollover?, before start: Date, category: Category?, accounts: NSPredicate? = nil) -> NSPredicate {
        guard let rollover, start > rollover.anchor else { return NSPredicate(value: false) }
        var predicates = [
            NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), rollover.anchor as CVarArg),
            NSPredicate(format: "%K < %@", #keyPath(Transaction.date), start as CVarArg),
            NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg),
            NSPredicate(format: "income = %d", false),
            TransferPredicate.excluded
        ]
        if let category {
            predicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
        }
        if let accounts {
            predicates.append(accounts)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

/// How saving an edited budget changes its rollover. Worked out before the edit is applied, so the alert can describe it.
enum RolloverChange: Equatable {
    /// Nothing about rollover changes.
    case unchanged
    /// A new budget, or an existing one turning rollover on: it starts with the current period.
    case start
    /// Rollover is turned off and the carry is cleared.
    case stop
    /// The time frame or category changed, so the carry is cleared and rollover starts again from the current period.
    case reset
    /// The amount or reset day changed: the carry so far is kept and the new settings apply from the current period.
    case lockIn

    static func make(wasEnabled: Bool, isEnabled: Bool, isNew: Bool, typeChanged: Bool, categoryChanged: Bool, amountChanged: Bool, startChanged: Bool) -> RolloverChange {
        switch (wasEnabled, isEnabled) {
        case (false, false):
            return .unchanged
        case (false, true):
            return .start
        case (true, false):
            return .stop
        case (true, true):
            if isNew {
                return .start
            }
            if typeChanged || categoryChanged {
                return .reset
            }
            if amountChanged || startChanged {
                return .lockIn
            }
            return .unchanged
        }
    }

    /// Applies the change to a budget whose amount, type and start date are already the new ones.
    /// `carry` is what carried into the current period under the old settings.
    func apply(to budget: RolloverBudget, currentStart: Date, carry: Double) {
        switch self {
        case .unchanged:
            break
        case .start, .reset:
            budget.rolloverEnabled = true
            budget.rolloverAnchor = currentStart
            budget.rolloverBalance = 0
        case .stop:
            budget.rolloverEnabled = false
            budget.rolloverAnchor = nil
            budget.rolloverBalance = 0
        case .lockIn:
            budget.rolloverEnabled = true
            budget.rolloverAnchor = currentStart
            budget.rolloverBalance = carry
        }
    }
}
