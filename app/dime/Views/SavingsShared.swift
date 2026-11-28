//
//  SavingsShared.swift
//  dime
//
//  What the app, its widgets and Shortcuts share about goals and debts: the words and numbers shown for one, and
//  the entity Shortcuts and widget options pick one with.
//

import AppIntents
import CoreData
import SwiftUI

/// The words and numbers a goal's or debt's tile and sheet show.
struct SavingsSummary {
    let amount: Double
    let word: String
    let status: String
    /// A sentence for under the sheet's ring.
    let detail: String
    let share: Double
    let colour: Color
    let isDone: Bool

    init(account: Account, formatter: BudgetFormatter, converter: CurrencyConverter = .current(), now: Date = .now) {
        if account.isDebt {
            let debt = account.debtStatus(using: converter, now: now)
            amount = max(debt.owed, 0)
            word = String(localized: "left")
            share = debt.paidShare
            colour = Color.PrimaryText
            isDone = debt.isPaidOff

            if debt.isPaidOff {
                status = String(localized: "Paid off")
                detail = String(localized: "Nothing left to pay.")
            } else if let projection = debt.projection {
                let date = projection.payoffDate(from: now).formatted(.dateTime.month(.abbreviated).year())
                status = String(localized: "Paid off by \(date)")
                if projection.interest >= 1 {
                    detail = String(localized: "Paying \(formatter.whole(account.paymentAmount)) a month, it's paid off by \(date), with about \(formatter.approx(projection.interest)) in interest.")
                } else {
                    detail = String(localized: "Paying \(formatter.whole(account.paymentAmount)) a month, it's paid off by \(date).")
                }
            } else if account.paymentAmount > 0 {
                status = String(localized: "Payment below interest")
                detail = String(localized: "\(formatter.whole(account.paymentAmount)) a month doesn't cover the interest, so this debt won't go down.")
            } else if debt.borrowed > 0 {
                status = String(localized: "of \(formatter.whole(debt.borrowed))")
                detail = String(localized: "\(formatter.whole(max(debt.borrowed - debt.owed, 0))) paid off of \(formatter.whole(debt.borrowed)).")
            } else {
                status = ""
                detail = ""
            }
        } else {
            let goal = account.goalProgress(using: converter, now: now)
            share = goal.share
            colour = Color.IncomeGreen
            isDone = goal.isReached

            if goal.repeatsMonthly {
                amount = max(goal.savedThisMonth, 0)
                word = String(localized: "this month")
                status = String(localized: "of \(formatter.whole(goal.target)) a month")
                detail = goal.isReached
                    ? String(localized: "This month's \(formatter.whole(goal.target)) is put aside. \(formatter.whole(goal.saved)) saved in all.")
                    : String(localized: "\(formatter.money(goal.remaining)) to go this month. \(formatter.whole(goal.saved)) saved in all.")
            } else {
                amount = max(goal.saved, 0)
                word = String(localized: "saved")

                let deadline = goal.deadline?.formatted(.dateTime.day().month(.abbreviated).year())

                if !goal.hasTarget {
                    status = String(localized: "No target")
                    detail = ""
                } else if goal.isReached {
                    status = String(localized: "of \(formatter.whole(goal.target)) · reached")
                    detail = String(localized: "You've saved all \(formatter.whole(goal.target)).")
                } else if let perMonth = goal.perMonth, let deadline {
                    status = String(localized: "of \(formatter.whole(goal.target)) by \(deadline)")
                    detail = String(localized: "Put aside about \(formatter.approx(perMonth)) a month to reach it by \(deadline).")
                } else if goal.isOverdue, let deadline {
                    status = String(localized: "of \(formatter.whole(goal.target)) · was due \(deadline)")
                    detail = String(localized: "\(formatter.money(goal.remaining)) to go.")
                } else {
                    status = String(localized: "of \(formatter.whole(goal.target))")
                    detail = String(localized: "\(formatter.money(goal.remaining)) to go.")
                }
            }
        }
    }
}

// MARK: - Shortcuts and widget options

@available(iOS 16, *)
struct SavingsEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Goal or Debt")
    typealias DefaultQueryType = SavingsQuery
    static var defaultQuery: SavingsQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Is a Debt")
    var isDebt: Bool

    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isDebt ? LocalizedStringResource("Debt") : LocalizedStringResource("Goal"),
            image: .init(systemName: symbol)
        )
    }

    init(id: UUID, name: String, isDebt: Bool, symbol: String) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.isDebt = isDebt
    }

    init?(account: Account) {
        guard let id = account.id, account.isGoal || account.isDebt else { return nil }
        self.init(id: id, name: account.wrappedName, isDebt: account.isDebt, symbol: account.wrappedSymbol)
    }
}

@available(iOS 16, *)
struct SavingsQuery: EntityStringQuery {
    @MainActor
    func entities(matching query: String) async throws -> [SavingsEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @MainActor
    func entities(for identifiers: [SavingsEntity.ID]) async throws -> [SavingsEntity] {
        identifiers.compactMap { id in
            DataController.shared.savingsAccount(withID: id).flatMap(SavingsEntity.init(account:))
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SavingsEntity] {
        let dataController = DataController.shared
        return (dataController.accounts(of: .goal) + dataController.accounts(of: .debt)).compactMap(SavingsEntity.init(account:))
    }
}

extension DataController {
    /// A goal or debt by its id, or nil when there's none, such as one deleted since a widget was set up.
    func savingsAccount(withID id: UUID) -> Account? {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(Account.id), id as CVarArg)
        request.fetchLimit = 1
        return results(for: request).first { $0.isGoal || $0.isDebt }
    }
}
