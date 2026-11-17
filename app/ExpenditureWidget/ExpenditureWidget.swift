//
//  ExpenditureWidget.swift
//  ExpenditureWidget
//
//  Created by Rafael Soh on 25/7/22.
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct DimeWidgets: WidgetBundle {
    var body: some Widget {
        RecentExpenditureWidget()
        InsightsWidget()
        BudgetWidget()
        LockBudgetWidget()
        MainBudgetWidget()
        NewExpenseWidget()
        if #available(iOS 18.0, *) {
            NewExpenseControl()
        }
    }
}

/// "New Expense" for Control Center, the Lock Screen and the Action button (iOS 18+).
/// The system draws controls itself, so on iOS 26 it is Liquid Glass automatically.
@available(iOS 18.0, *)
struct NewExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.rafaelsoh.dime.NewExpenseControl") {
            ControlWidgetButton(action: OpenNewExpenseIntent()) {
                Label("New Expense", systemImage: "plus")
            }
        }
        .displayName("New Expense")
        .description("Open Dime straight to a new expense.")
    }
}

/// Opens the app on the new-expense screen via the existing `dimeapp://newExpense` link.
@available(iOS 18.0, *)
struct OpenNewExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "New Expense"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "dimeapp://newExpense")!))
    }
}
