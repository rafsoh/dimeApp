//
//  GetInsightsIntent.swift
//  dime
//
//  Created by Rafael Soh on 5/8/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct GetInsightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Insights"

    static var description =
        IntentDescription("Extracts your total expenditure or income for a particular time period")

    @Parameter(title: "Type", description: "Type of Data", requestValueDialog: IntentDialog("Which of the following would you like to extract?"))
    var type: ShortcutsInsightsType

    @Parameter(title: "Time Frame", description: "Time Frame of Data", requestValueDialog: IntentDialog("Over what time frame would you like to consider?"))
    var timeframe: ShortcutsInsightsTimeFrame

    @Parameter(title: "Category Filters", description: "Additional Category Filters", requestValueDialog: IntentDialog("Which additional category filters do you want to impose?"))
    var incomeCategories: [IncomeCategoryEntity]?

    @Parameter(title: "Category Filters", description: "Additional Category Filters", requestValueDialog: IntentDialog("Which additional category filters do you want to impose?"))
    var expenseCategories: [ExpenseCategoryEntity]?

    @Parameter(title: "Accounts", description: "Only count transactions in these accounts. Leave it empty to count every account.")
    var accounts: [AccountEntity]?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        let dataController = DataController.shared
        // Without a store every total would read as zero.
        try dataController.requireLoadedStore()
//        let dataController = DataController()

        let categories: [Category]
        let optionalIncome: Bool?
        let typeInt: Int

        switch type {
        case .net:
            categories = []
            optionalIncome = nil
            typeInt = 1
        case .income:
            if let unwrappedCategories = incomeCategories {
                categories = unwrappedCategories.compactMap { category in
                    try? dataController.findCategory(withId: category.id)
                }
            } else {
                categories = []
            }

            optionalIncome = true
            typeInt = 2
        case .spent:
            if let unwrappedCategories = expenseCategories {
                categories = unwrappedCategories.compactMap { category in
                    try? dataController.findCategory(withId: category.id)
                }
            } else {
                categories = []
            }
            optionalIncome = false
            typeInt = 3
        }

        // Accounts deleted since the shortcut was set up are left out. When none are left, it asks again rather
        // than counting every account in their place.
        var accountPredicate: NSPredicate?

        if let accounts, !accounts.isEmpty {
            let existing = Set(dataController.accountChoices().map(\.key))
            let keys = Set(accounts.map(\.id)).intersection(existing)

            guard !keys.isEmpty else {
                throw $accounts.needsValueError("Which account? The one this shortcut used was deleted.")
            }

            accountPredicate = AccountScope(keys: keys).predicate(in: dataController.container.viewContext)
        }

        let total = dataController.shortcutInsightsTotal(type: typeInt, timeframe: timeframe.rawValue, optionalIncome: optionalIncome, categories: categories, accounts: accountPredicate)
        let result = total.value
        let dialog: IntentDialog = total.report.note.map { IntentDialog("Here you go! \($0)") } ?? "Here you go!"

        return .result(value: result, dialog: dialog) {
            ShortcutInsightsView(amount: result, type: type, timeframe: timeframe)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\GetInsightsIntent.$type) {
            Case(ShortcutsInsightsType.net) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$accounts
                }
            }
            Case(ShortcutsInsightsType.income) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$incomeCategories
                    \.$accounts
                }
            }
            Case(ShortcutsInsightsType.spent) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$expenseCategories
                    \.$accounts
                }
            }
            DefaultCase {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$accounts
                }
            }
        }
    }
}

enum ShortcutsInsightsTimeFrame: Int {
    case day = 1
    case week = 2
    case month = 3
    case year = 4
    case all = 5
}

@available(iOS 16, *)
extension ShortcutsInsightsTimeFrame: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Time Frame")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsTimeFrame: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "today"),
        .week: DisplayRepresentation(title: "this week"),
        .month: DisplayRepresentation(title: "this month"),
        .year: DisplayRepresentation(title: "this year"),
        .all: DisplayRepresentation(title: "all time")
    ]
}

enum ShortcutsInsightsType: String {
    case net, income, spent
}

@available(iOS 16, *)
extension ShortcutsInsightsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Insights Type")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsType: DisplayRepresentation] = [
        .net: DisplayRepresentation(title: "net total"),
        .income: DisplayRepresentation(title: "total income"),
        .spent: DisplayRepresentation(title: "total expenditure")
    ]
}

struct ShortcutInsightsView: View {
    let amount: Double
    let type: ShortcutsInsightsType
    let timeframe: ShortcutsInsightsTimeFrame

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"

    var leftText: String {
        switch type {
        case .net:
            return "Net total"
        case .income:
            return "Earned"
        case .spent:
            return "Spent"
        }
    }

    var rightText: String {
        switch timeframe {
        case .day:
            return "today"
        case .week:
            return "this week"
        case .month:
            return "this month"
        case .year:
            return "this year"
        case .all:
            return "all time"
        }
    }

    var amountString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(leftText + " " + rightText)
                .font(.app(size: 17, weight: .medium))
                .foregroundColor(Color.SubtitleText)

            Text(amountString)
                .font(.app(size: 32, weight: .medium))
                .lineLimit(1)
        }
        .padding(20)
    }
}
