//
//  ShortcutsProvider.swift
//  dime
//
//  Created by Rafael Soh on 5/8/23.
//

import AppIntents
import Foundation

@available(iOS 16.4, *)
struct DimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTransactionIntent(),
            phrases: ["Log a new transaction in \(.applicationName)"],
            systemImageName: "books.vertical.fill"
        )
        AppShortcut(
            intent: GetInsightsIntent(),
            phrases: ["Get insights in \(.applicationName)"],
            systemImageName: "plusminus.circle.fill"
        )
        AppShortcut(
            intent: BudgetIntent(),
            phrases: ["Extract leftover amount for your budgets in \(.applicationName)"],
            systemImageName: "circle.grid.2x2.fill"
        )
        AppShortcut(
            intent: AddToGoalIntent(),
            phrases: ["Add money to a goal in \(.applicationName)", "Save towards a goal in \(.applicationName)"],
            systemImageName: "target"
        )
        AppShortcut(
            intent: PayDebtIntent(),
            phrases: ["Pay towards a debt in \(.applicationName)"],
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: GetSavingsIntent(),
            phrases: ["Check a goal or debt in \(.applicationName)"],
            systemImageName: "chart.bar.fill"
        )
    }
}
