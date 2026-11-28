//
//  SavingsIntents.swift
//  dime
//
//  Shortcuts actions for goals and debts: put money into a goal, pay towards a debt, and read where one stands.
//  Money moves as a transfer from the last used everyday account, as it does from the goal's or debt's page.
//

import AppIntents
import Foundation

@available(iOS 16.4, *)
enum SavingsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    case notAGoal
    case notADebt
    case noAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound:
            return "That goal or debt no longer exists."
        case .notAGoal:
            return "Choose a goal, not a debt."
        case .notADebt:
            return "Choose a debt, not a goal."
        case .noAmount:
            return "Enter an amount above zero."
        }
    }
}

@available(iOS 16.4, *)
struct AddToGoalIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Money to a Goal"
    static var description = IntentDescription("Moves money from your last used account into a goal.")

    @Parameter(title: "Goal", requestValueDialog: IntentDialog("Which goal?"))
    var goal: SavingsEntity

    @Parameter(title: "Amount", requestValueDialog: IntentDialog("How much?"))
    var amount: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) to \(\.$goal)")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ProvidesDialog {
        let dataController = DataController.shared
        try dataController.requireLoadedStore()

        guard let account = dataController.savingsAccount(withID: goal.id) else { throw SavingsIntentError.notFound }
        guard account.isGoal else { throw SavingsIntentError.notAGoal }
        guard amount > 0 else { throw SavingsIntentError.noAmount }

        let from = AccountPreferences.lastUsed(among: dataController.accounts(of: .everyday))
        dataController.saveTransfer(from: from, to: .account(account), amount: amount, currencyCode: dataController.currencyConverter.mainCurrency, date: .now, note: "")

        let saved = account.balance(using: dataController.currencyConverter).value
        let formatter = BudgetFormatter.current
        return .result(value: saved, dialog: "Added. \(account.wrappedName) has \(formatter.money(saved)) in it.")
    }
}

@available(iOS 16.4, *)
struct PayDebtIntent: AppIntent {
    static var title: LocalizedStringResource = "Pay Towards a Debt"
    static var description = IntentDescription("Logs a payment from your last used account towards a debt. With a rate, that month's interest is logged too.")

    @Parameter(title: "Debt", requestValueDialog: IntentDialog("Which debt?"))
    var debt: SavingsEntity

    @Parameter(title: "Amount", requestValueDialog: IntentDialog("How much?"))
    var amount: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Pay \(\.$amount) towards \(\.$debt)")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ProvidesDialog {
        let dataController = DataController.shared
        try dataController.requireLoadedStore()

        guard let account = dataController.savingsAccount(withID: debt.id) else { throw SavingsIntentError.notFound }
        guard account.isDebt else { throw SavingsIntentError.notADebt }
        guard amount > 0 else { throw SavingsIntentError.noAmount }

        let from = AccountPreferences.lastUsed(among: dataController.accounts(of: .everyday))
        let legs = dataController.saveTransfer(from: from, to: .account(account), amount: amount, currencyCode: dataController.currencyConverter.mainCurrency, date: .now, note: "")
        dataController.logInterest(forPayment: legs.incoming)

        let owed = max(account.debtStatus(using: dataController.currencyConverter).owed, 0)
        let formatter = BudgetFormatter.current
        return .result(value: owed, dialog: "Paid. \(formatter.money(owed)) left on \(account.wrappedName).")
    }
}

@available(iOS 16.4, *)
struct GetSavingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get a Goal or Debt"
    static var description = IntentDescription("Gives what's saved in a goal, or what's left on a debt.")

    @Parameter(title: "Goal or Debt", requestValueDialog: IntentDialog("Which goal or debt?"))
    var account: SavingsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ProvidesDialog {
        let dataController = DataController.shared
        try dataController.requireLoadedStore()

        guard let saved = dataController.savingsAccount(withID: account.id) else { throw SavingsIntentError.notFound }

        let summary = SavingsSummary(account: saved, formatter: .current, converter: dataController.currencyConverter)
        let formatter = BudgetFormatter.current
        let detail = summary.status.isEmpty ? "" : " (\(summary.status))"
        return .result(value: summary.amount, dialog: "\(saved.wrappedName): \(formatter.money(summary.amount)) \(summary.word)\(detail).")
    }
}
