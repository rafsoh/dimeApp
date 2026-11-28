//
//  ExpenditureWidget.swift
//  ExpenditureWidget
//
//  Created by Rafael Soh on 25/7/22.
//

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

        if #available(iOSApplicationExtension 17.0, *) {
            QuickAddWidget()
            SavingsWidget()
        }

        if #available(iOSApplicationExtension 18.0, *) {
            NewExpenseControl()
        }
    }
}
