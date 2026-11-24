//
//  OpenNewExpenseIntent.swift
//  dime
//
//  Opens Dime straight to the new expense sheet. Used by the New Expense control
//  (Control Center, Lock Screen and the Action Button).
//
//  This file is compiled into both the app and the widget extension: a control that
//  opens its app must have its intent in both targets, and with `openAppWhenRun` the
//  system runs `perform()` inside the app, after bringing it to the foreground.
//

import AppIntents
import Foundation

/// Hook the app installs at launch to show the new expense sheet. The widget extension
/// never sets it, so the intent stays free of app-only APIs such as `UIApplication`.
enum NewExpenseLauncher {
    static let url = URL(string: "dimeapp://newExpense")!

    @MainActor static var open: (() -> Void)?
}

@available(iOS 18.0, *)
struct OpenNewExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "New Expense"

    static var description = IntentDescription("A convenient button to log new purchases.")

    static var openAppWhenRun: Bool = true

    // Shortcuts already offers the full "New Transaction" action; this one is only for the control.
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NewExpenseLauncher.open?()
        return .result()
    }
}
