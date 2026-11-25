//
//  Helper.swift
//  dime
//
//  Created by Rafael Soh on 13/8/22.
//

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

    /// What to call the transaction on screen: its note, or "Expense" or "Income" when it has none.
    var displayTitle: String {
        let trimmed = wrappedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
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
