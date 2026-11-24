//
//  NewExpenseControl.swift
//  ExpenditureWidgetExtension
//
//  A button users can place in Control Center, on the Lock Screen or on the
//  Action Button (iOS 18+) that opens the new expense sheet.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NewExpenseControl: ControlWidget {
    static let kind: String = "AddExpenseControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNewExpenseIntent()) {
                Label("New Expense", systemImage: "plus")
            }
        }
        .displayName("New Expense")
        .description("A convenient button to log new purchases.")
    }
}
