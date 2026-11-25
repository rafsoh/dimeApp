//
//  BudgetInsightsIntent.swift
//  dime
//
//  Created by Rafael Soh on 6/8/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct BudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Budget Insights"

    static var description =
        IntentDescription("Extract leftover amount for a particular budget")

    @Parameter(title: "Budget Type", requestValueDialog: IntentDialog("What budget type would you like to extract insights from?"))
    var type: ShortcutsBudgetsType

    @Parameter(title: "Category Budget", requestValueDialog: IntentDialog("Select a categorical budget."))
    var budget: BudgetEntity?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        if type == .category && budget == nil {
            throw $budget.needsValueError()
        }

//        let dataController = DataController()

        let dataController = DataController.shared

        var amount: Double = 0
        var report = ConversionReport()
        var budgetType: Int16 = 0

        switch type {
        case .overall:
            if let mainBudget = dataController.results(for: dataController.fetchRequestForMainBudget()).first {
                let leftover = dataController.budgetLeftover(overallBudget: mainBudget)
                amount = leftover.value
                report = leftover.report

                budgetType = mainBudget.type
            }
        case .category:
            if let unwrappedBudget = budget {
                let categoryBudget = try dataController.findBudget(withId: unwrappedBudget.id)

                let leftover = dataController.budgetLeftover(budget: categoryBudget)
                amount = leftover.value
                report = leftover.report

                budgetType = categoryBudget.type
            }
        }

        let dialog: IntentDialog = report.note.map { IntentDialog("Here you go! \($0)") } ?? "Here you go!"

        return .result(value: amount, dialog: dialog) {
            ShortcutBudgetView(amount: amount, type: Int(budgetType))
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\BudgetIntent.$type) {
            Case(ShortcutsBudgetsType.category) {
                Summary("Calculate leftover amount for the \(\.$budget) \(\.$type)")
            }
            Case(ShortcutsBudgetsType.overall) {
                Summary("Calculate leftover amount for the \(\.$type)")
            }
            // Used when the type is asked each time. The budget must be listed: since iOS 18 a parameter missing
            // from the summary can't be asked for, so choosing Category ended the shortcut.
            DefaultCase {
                Summary("Calculate leftover amount for the \(\.$type)") {
                    \.$budget
                }
            }
        }
    }
}

enum ShortcutsBudgetsType: String {
    case overall, category
}

@available(iOS 16, *)
extension ShortcutsBudgetsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Budget Type")
    }

    static var caseDisplayRepresentations: [ShortcutsBudgetsType: DisplayRepresentation] = [
        .overall: DisplayRepresentation(title: "overall budget"),
        .category: DisplayRepresentation(title: "categorical budget")
    ]
}

struct ShortcutBudgetView: View {
    let amount: Double
    let type: Int

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!

    var budgetType: String {
        switch type {
        case 1:
            return String(localized: "today")
        case 2:
            return String(localized: "this week")
        case 3:
            return String(localized: "this month")
        case 4:
            return String(localized: "this year")
        default:
            return "this week"
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

        return numberFormatter.string(from: NSNumber(value: abs(amount))) ?? "$0"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(amountString)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .lineLimit(1)

            if amount > 0 {
                Text("left \(budgetType)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
            } else {
                Text("over \(budgetType)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
            }
        }
        .padding(20)
    }
}
