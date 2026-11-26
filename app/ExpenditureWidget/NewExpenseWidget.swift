//
//  NewExpenseWidget.swift
//  ExpenditureWidgetExtension
//
//  Created by Rafael Soh on 9/9/22.
//

import SwiftUI
import WidgetKit

struct NewExpenseWidget: Widget {
    let kind: String = "AddExpense"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 16, *) {
            return [
                .systemSmall,
                .accessoryCircular
            ]
        } else {
            return [.systemSmall]
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NewExpenseProvider()) { entry in
            NewExpenseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("New Expense")
        .description("A convenient button to log new purchases.")
        .supportedFamilies(supportedFamilies)
    }
}

struct NewExpenseProvider: TimelineProvider {
    typealias Entry = NewExpenseWidgetEntry

    func placeholder(in _: Context) -> NewExpenseWidgetEntry {
        NewExpenseWidgetEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (NewExpenseWidgetEntry) -> Void) {
        let entry = NewExpenseWidgetEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NewExpenseWidgetEntry>) -> Void) {
        let entry = NewExpenseWidgetEntry(date: Date())

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }
}

struct NewExpenseWidgetEntry: TimelineEntry {
    let date: Date
}

struct NewExpenseWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: NewExpenseProvider.Entry

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            NewExpenseTileView()
        default:
            if #available(iOS 16.0, *) {
                ZStack {
                    AccessoryWidgetBackground()

                    Image(systemName: "plus")
                        .font(.app(.title2, weight: .bold))
                        .accessibilityLabel("New Expense")
                }
                .widgetURL(URL(string: "dimeapp://newExpense"))
                .accessoryWidgetBackground()
            }
        }
    }
}

/// The small home screen widget: the app's dark add button, large enough to tap from anywhere on the tile.
struct NewExpenseTileView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "plus")
                .font(.app(.title2, weight: .bold))
                .foregroundColor(Color.LightIcon)
                .frame(width: 52, height: 52)
                .background(Color.DarkBackground, in: Circle())
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text("New Expense")
                .font(.app(.title3, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .budgetWidgetBackground()
        .widgetURL(URL(string: "dimeapp://newExpense"))
    }
}
