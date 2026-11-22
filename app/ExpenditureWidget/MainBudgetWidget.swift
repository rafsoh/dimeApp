//
//  MainBudgetWidget.swift
//  dime
//
//  Created by Rafael Soh on 12/1/23.
//

import SwiftUI
import WidgetKit

struct MainBudgetWidget: Widget {
    let kind: String = "MainBudgetWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [
                .accessoryCircular,
                .accessoryRectangular,
                .systemSmall
            ]
        } else {
            return [.systemSmall]
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MainBudgetWidgetProvider()) { entry in
            MainBudgetWidgetEntryView(entry: entry)
        }
        .supportedFamilies(supportedFamilies)
        .configurationDisplayName("Overall Budget")
        .description("Monitor how you are sticking to your overall budgets.")
    }
}

struct MainBudgetWidgetProvider: TimelineProvider {
    typealias Entry = MainBudgetWidgetEntry

    func placeholder(in _: Context) -> MainBudgetWidgetEntry {
        MainBudgetWidgetEntry(date: Date(), budget: BudgetWidgetData.overall())
    }

    func getSnapshot(in _: Context, completion: @escaping (MainBudgetWidgetEntry) -> Void) {
        completion(MainBudgetWidgetEntry(date: Date(), budget: BudgetWidgetData.overall()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<MainBudgetWidgetEntry>) -> Void) {
        let entry = MainBudgetWidgetEntry(date: Date(), budget: BudgetWidgetData.overall())
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

struct MainBudgetWidgetEntry: TimelineEntry {
    let date: Date
    let budget: BudgetWidgetData?
}

struct MainBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: MainBudgetWidgetProvider.Entry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            if let budget = entry.budget {
                BudgetAccessoryCircleView(budget: budget)
            } else {
                BudgetAccessoryMessage(message: "ADD\nBUDGET", circular: true)
            }

        case .accessoryRectangular:
            if let budget = entry.budget {
                BudgetAccessoryRectangleView(budget: budget)
            } else {
                BudgetAccessoryMessage(message: "ADD OVERALL BUDGET")
            }

        case .systemSmall:
            if let budget = entry.budget {
                BudgetTileWidgetView(budget: budget)
            } else {
                WidgetBudgetMessage("Create your overall budget in the app")
            }

        default:
            EmptyView()
        }
    }
}
