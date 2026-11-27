//
//  NewTransactionIntent.swift
//  dime
//
//  Created by Rafael Soh on 23/7/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct NewTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "New Transaction"

    static var description =
        IntentDescription("Log new transactions in a blink")

    @Parameter(title: "Type", description: "Type of the transaction", requestValueDialog: IntentDialog("Would you like to log an income or expense?"))
    var income: TransactionType

    @Parameter(title: "Amount", description: "Value of the transaction", controlStyle: .field, inclusiveRange: (lowerBound: 0.01, upperBound: 100_000_000), requestValueDialog: IntentDialog("How much was transacted?"))
    var amount: Double

    @Parameter(title: "Income Category", description: "Category for an income. Choose No Category to log it without one.", requestValueDialog: IntentDialog("What category does it come under?"))
    var incomeCategory: IncomeCategoryEntity?

    @Parameter(title: "Expense Category", description: "Category for an expense. Choose No Category to log it without one.", requestValueDialog: IntentDialog("What category does it come under?"))
    var expenseCategory: ExpenseCategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Currency", description: "A three-letter code such as EUR. Leave it empty to use the currency Dime picks for new transactions.")
    var currencyCode: String?

    @Parameter(title: "Recurring Transaction", default: false)
    var recurringTransaction: Bool

    @Parameter(title: "Recurring Frequency", default: .weekly)
    var recurringType: RepeatType

//    struct CategoryOptionsProvider: DynamicOptionsProvider {
//
//        func results() async throws -> ItemCollection<CategoryEntity> {
//            let dataController = DataController()
//
//            let categories = dataController.getAllCategories().map { CategoryEntity(id: $0.id!, name: $0.wrappedName, emoji: $0.wrappedEmoji, income: $0.income)
//            }
//
//            let incomeCategories = categories.filter { $0.income }
//            let expenseCategories = categories.filter { !$0.income }
//
//            return ItemCollection {
//                ItemSection(
//                    "Income Categories",
//                    items: incomeCategories.map {
//                        IntentItem<CategoryEntity>.init($0)
//                    }
//                )
//                ItemSection(
//                    "Expense Categories",
//                    items: expenseCategories.map {
//                        IntentItem<CategoryEntity>.init($0)
//                    }
//                )
//
//            }
//        }
//    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if amount == 0 {
            throw $amount.needsValueError()
        }

        let dataController = DataController.shared

        // Without a store the save below would fail after the dialog had already said it was logged.
        try dataController.requireLoadedStore()

        let repeatType: Int
        var currency: String?

        if let currencyCode, !currencyCode.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let code = Currency.knownCode(currencyCode) else {
                throw $currencyCode.needsValueError("Which currency? Use a three-letter code such as EUR.")
            }

            currency = code
        }

        if !recurringTransaction {
            repeatType = 0
        } else {
            switch recurringType {
            case .daily:
                repeatType = 1
            case .weekly:
                repeatType = 2
            case .monthly:
                repeatType = 3
            }
        }

        let isIncome = income == .income
        let category: Category?

        // Left empty, the category is asked for; No Category logs the transaction without one. Since iOS 18
        // this prompt only appears for parameters in the summary, so every summary below lists both.
        // A category deleted since the shortcut was set up is asked for again, rather than failing.
        if isIncome {
            guard let id = incomeCategory?.id, id == CategoryEntityOptions.noCategoryID || (try? dataController.findCategory(withId: id)) != nil else {
                throw $incomeCategory.needsValueError()
            }

            category = id == CategoryEntityOptions.noCategoryID ? nil : try dataController.findCategory(withId: id)
        } else {
            guard let id = expenseCategory?.id, id == CategoryEntityOptions.noCategoryID || (try? dataController.findCategory(withId: id)) != nil else {
                throw $expenseCategory.needsValueError()
            }

            category = id == CategoryEntityOptions.noCategoryID ? nil : try dataController.findCategory(withId: id)
        }

        let transaction = dataController.newTransaction(note: note ?? "", category: category, income: isIncome, amount: amount, currencyCode: currency, date: Date.now, repeatType: repeatType, repeatCoefficient: 1, delay: false)

        // Feature Lab: without a category, Apple Intelligence picks one first, so the result shows it. If it
        // can't (busy, or Dime in the background), the transaction stays queued for when Dime next opens.
        await AutoCategorizer.shared.waitForCategory(of: transaction, upTo: 10)

        return .result(dialog: isIncome ? "Income successfully logged." : "Expense successfully logged.") {
            ShortcutTransactionView(transaction: transaction)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\NewTransactionIntent.$income) {
            Case(TransactionType.expense) {
                When(\NewTransactionIntent.$recurringTransaction, .equalTo, true, {
                    Summary("Log an \(\.$income) of \(\.$amount) under \(\.$expenseCategory)") {
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                        \.$recurringType
                    }
                }, otherwise: {
                    Summary("Log an \(\.$income) of \(\.$amount) under \(\.$expenseCategory)") {
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                    }
                })
            }
            Case(TransactionType.income) {
                When(\NewTransactionIntent.$recurringTransaction, .equalTo, true, {
                    Summary("Log an \(\.$income) of \(\.$amount) under \(\.$incomeCategory)") {
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                        \.$recurringType
                    }
                }, otherwise: {
                    Summary("Log an \(\.$income) of \(\.$amount) under \(\.$incomeCategory)") {
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                    }
                })
            }
            // Used when the type is asked each time. Both categories must be listed: since iOS 18 a parameter
            // missing from the summary can't be asked for, and the shortcut ended without logging anything.
            DefaultCase {
                When(\NewTransactionIntent.$recurringTransaction, .equalTo, true, {
                    Summary("Log an \(\.$income) of \(\.$amount)") {
                        \.$expenseCategory
                        \.$incomeCategory
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                        \.$recurringType
                    }
                }, otherwise: {
                    Summary("Log an \(\.$income) of \(\.$amount)") {
                        \.$expenseCategory
                        \.$incomeCategory
                        \.$note
                        \.$currencyCode
                        \.$recurringTransaction
                    }
                })
            }
        }
    }
}

// income or expense

enum TransactionType: String {
    case income, expense
}

@available(iOS 16, *)
extension TransactionType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Type")
    }

    static var caseDisplayRepresentations: [TransactionType: DisplayRepresentation] = [
        .income: DisplayRepresentation(title: "income",
                                       image: .init(systemName: "plus.square.fill")),
        .expense: DisplayRepresentation(title: "expense",
                                        image: .init(systemName: "minus.square.fill"))
    ]
}

enum RepeatType: String {
    case daily, weekly, monthly
}

@available(iOS 16, *)
extension RepeatType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Frequency")
    }

    static var caseDisplayRepresentations: [RepeatType: DisplayRepresentation] = [
        .daily: DisplayRepresentation(title: "Daily"),
        .weekly: DisplayRepresentation(title: "Weekly"),
        .monthly: DisplayRepresentation(title: "Monthly")
    ]
}

struct ShortcutTransactionView: View {
    let transaction: Transaction

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"

    var transactionAmountString: String {
        if let code = transaction.currencyCode, code.uppercased() != currency.uppercased() {
            return MoneyFormatter.string(transaction.amount, currencyCode: code, showCents: showCents)
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: transaction.amount)) ?? "$0"
    }

    var body: some View {
        HStack(spacing: 12) {
            EmojiLogView(transaction: transaction, future: false)
                .frame(width: 35, height: 35, alignment: .center)
                .overlay(alignment: .bottomTrailing) {
                    if transaction.recurringType > 0 {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.DarkIcon)
                            .padding(3)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6))
                            .offset(x: 5, y: 5)
                    }
                }

            VStack(alignment: .leading) {
                Text(transaction.displayTitle)
                    .font(.app(size: 16, weight: .medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Text(transaction.wrappedDate, format: .dateTime.hour().minute())
                    .font(.app(size: 12, weight: .medium))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
            }
            Spacer()
            if transaction.income {
                Text("+\(transactionAmountString)")
                    .font(.app(size: 19, weight: .medium))
                    .foregroundColor(Color.IncomeGreen)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text("-\(transactionAmountString)")
                    .font(.app(size: 19, weight: .medium))
                    .foregroundColor(Color.PrimaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }
}
