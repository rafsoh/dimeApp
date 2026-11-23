//
//  LockBudgetWidget.swift
//  ExpenditureWidgetExtension
//
//  Created by Rafael Soh on 9/9/22.
//

import SwiftUI
import WidgetKit

struct LockBudgetWidget: Widget {
    let kind: String = "LockBudgetWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 16, *) {
            return [
                .accessoryCircular,
                .accessoryRectangular,
                .accessoryInline
            ]
        } else {
            return [WidgetFamily]()
        }
    }

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: BudgetWidgetConfigurationIntent.self, provider: BudgetWidgetProvider()) { entry in
            LockBudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies(supportedFamilies)
    }
}

struct LockBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: BudgetWidgetProvider.Entry

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            if let budget = entry.budget, entry.isConfigured {
                Text("\(budget.emoji ?? "") \(BudgetFormatter.current.money(budget.snapshot.difference)) \(budget.amountWord)")
                    .widgetURL(budget.url)
            } else {
                Text("Select budget in widget options")
            }

        case .accessoryCircular:
            if let budget = entry.budget, entry.isConfigured {
                BudgetAccessoryCircleView(budget: budget)
            } else {
                BudgetAccessoryMessage(message: "SELECT BUDGET", circular: true)
            }

        case .accessoryRectangular:
            if let budget = entry.budget, entry.isConfigured {
                BudgetAccessoryRectangleView(budget: budget)
            } else {
                BudgetAccessoryMessage(message: "SELECT BUDGET IN WIDGET OPTIONS")
            }

        default:
            EmptyView()
        }
    }
}
