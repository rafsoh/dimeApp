//
//  BudgetWidget.swift
//  dime
//
//  Created by Rafael Soh on 17/8/22.
//

import CoreData
import SwiftUI
import WidgetKit

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: BudgetWidgetConfigurationIntent.self, provider: BudgetWidgetProvider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies([.systemSmall])
    }
}

struct BudgetWidgetProvider: IntentTimelineProvider {
    typealias Intent = BudgetWidgetConfigurationIntent

    public typealias Entry = BudgetWidgetEntry

    func placeholder(in _: Context) -> BudgetWidgetEntry {
        BudgetWidgetEntry(date: Date(), budget: .sample, configuration: BudgetWidgetConfigurationIntent())
    }

    func getSnapshot(for configuration: BudgetWidgetConfigurationIntent, in context: Context, completion: @escaping (BudgetWidgetEntry) -> Void) {
        if context.isPreview && configuration.budget == nil {
            completion(BudgetWidgetEntry(date: Date(), budget: .sample, configuration: configuration, isSample: true))
        } else {
            completion(entry(for: configuration))
        }
    }

    func getTimeline(for configuration: BudgetWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [entry(for: configuration)], policy: .atEnd))
    }

    private func entry(for configuration: BudgetWidgetConfigurationIntent) -> BudgetWidgetEntry {
        BudgetWidgetEntry(date: Date(), budget: BudgetWidgetData.category(identifier: configuration.budget?.identifier), configuration: configuration)
    }
}

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let budget: BudgetWidgetData?
    let configuration: BudgetWidgetConfigurationIntent
    var isSample = false

    var isConfigured: Bool {
        isSample || configuration.budget != nil
    }
}

/// A budget's current period, loaded the same way the Budgets tab loads it.
struct BudgetWidgetData {
    let name: String
    /// Nil for the overall budget.
    let emoji: String?
    let snapshot: BudgetSnapshot
    let segments: [BudgetMeterSegment]
    var conversion = ConversionReport()

    var isOverall: Bool {
        emoji == nil
    }

    var url: URL? {
        isOverall ? URL(string: "dimeapp://budget") : URL(string: "dimeapp://budget?budget=\(name)")
    }

    /// "left of $200" or "over $200", so every budget widget shows what the budget is.
    var amountWord: String {
        let amount = BudgetFormatter.current.whole(snapshot.amount)
        return snapshot.isOver ? String(localized: "over \(amount)") : String(localized: "left of \(amount)")
    }

    /// Widgets leave out how long the period has to go, so a budget that's on track has no status line.
    var statusLine: Text? {
        switch snapshot.status {
        case .onTrack, .abovePace:
            return nil
        case .nearLimit, .over, .ended, .fresh:
            return snapshot.tileStatus()
        }
    }

    static var sample: BudgetWidgetData {
        let period = BudgetPeriod(type: 2, start: Calendar.current.date(byAdding: .day, value: -3, to: Date.now) ?? Date.now)
        let snapshot = BudgetSnapshot(amount: 200, spent: 74, period: period)
        return BudgetWidgetData(name: String(localized: "Food"), emoji: "🍔", snapshot: snapshot,
                            segments: [BudgetMeterSegment(id: "fill", share: snapshot.share, colour: Color(hex: "#FFAF44"))])
    }

    static func category(identifier: String?) -> BudgetWidgetData? {
        let dataController = DataController.shared
        let context = dataController.container.viewContext

        guard let identifier,
              let url = URL(string: identifier),
              let objectID = dataController.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url),
              let budget = try? context.existingObject(with: objectID) as? Budget
        else { return nil }

        let period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate).current
        let spending = transactions(in: period, category: budget.category, accounts: budget.accountPredicate).total(using: dataController.currencyConverter)
        let carry = dataController.rolloverCarryIn(for: budget, category: budget.category, at: period.start)
        let snapshot = BudgetSnapshot(amount: budget.amount, spent: spending.value, period: period, carryIn: carry)

        return BudgetWidgetData(name: budget.wrappedName, emoji: budget.wrappedEmoji, snapshot: snapshot,
                            segments: [BudgetMeterSegment(id: "fill", share: snapshot.share, colour: Color(hex: budget.wrappedColour))],
                            conversion: spending.report)
    }

    static func overall() -> BudgetWidgetData? {
        let dataController = DataController.shared

        guard let budget = dataController.results(for: dataController.fetchRequestForMainBudget()).first else { return nil }

        let period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate).current
        let transactions = transactions(in: period, category: nil, accounts: budget.accountPredicate)
        let spending = transactions.total(using: dataController.currencyConverter)
        let carry = dataController.rolloverCarryIn(for: budget, category: nil, at: period.start)
        let snapshot = BudgetSnapshot(amount: budget.amount, spent: spending.value, period: period, carryIn: carry)

        return BudgetWidgetData(name: String(localized: "Overall"), emoji: nil, snapshot: snapshot,
                            segments: budgetStripSegments(transactions, denominator: max(snapshot.amount, snapshot.spent)),
                            conversion: spending.report)
    }

    private static func transactions(in period: BudgetPeriod, category: Category?, accounts: NSPredicate?) -> [Transaction] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = budgetPredicate(from: period.start, to: period.end, category: category, accounts: accounts)
        return DataController.shared.results(for: request)
    }
}

struct BudgetWidgetEntryView: View {
    let entry: BudgetWidgetProvider.Entry

    var body: some View {
        if !entry.isConfigured {
            WidgetBudgetMessage("Select budget in widget options")
        } else if let budget = entry.budget {
            BudgetTileWidgetView(budget: budget)
        } else {
            WidgetBudgetMessage("Budget no longer exists - please select new budget from widget options.")
        }
    }
}

/// The small home screen widget, laid out like a tile on the Budgets tab.
struct BudgetTileWidgetView: View {
    let budget: BudgetWidgetData
    let formatter = BudgetFormatter.current

    var body: some View {
        let snapshot = budget.snapshot

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if let emoji = budget.emoji {
                    Text(emoji)
                        .font(.app(.subheadline))
                }
                Text(budget.name)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                if snapshot.isOver {
                    Spacer(minLength: 4)
                    BudgetOverIcon()
                }
            }

            Spacer(minLength: 0)

            BudgetAmountText(amount: snapshot.difference, font: .app(.title, weight: .semibold), formatter: formatter, prefix: budget.conversion.approximatePrefix)

            Text(budget.amountWord)
                .font(.app(.subheadline, weight: .medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let statusLine = budget.statusLine {
                statusLine
                    .font(.app(.caption, weight: .medium))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }

            BudgetMeter(segments: budget.segments, tick: snapshot.showsTick ? snapshot.period.elapsed : nil, height: 10)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .budgetWidgetBackground()
        .widgetURL(budget.url)
    }
}

struct WidgetBudgetMessage: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.app(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundColor(Color.SubtitleText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .budgetWidgetBackground()
    }
}

/// The lock screen rectangle: name, what's left with the tile's status, and a linear gauge.
struct BudgetAccessoryRectangleView: View {
    let budget: BudgetWidgetData
    let formatter = BudgetFormatter.current

    var body: some View {
        let snapshot = budget.snapshot

        VStack(alignment: .leading, spacing: 2) {
            Text([budget.emoji, budget.name].compactMap { $0 }.joined(separator: " "))
                .font(.app(size: 15, weight: .semibold))
                .lineLimit(1)

            Text("\(budget.conversion.approximatePrefix)\(formatter.money(snapshot.difference)) \(budget.amountWord)")
                .font(.app(size: 14, weight: .regular))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if #available(iOS 16.0, *) {
                Gauge(value: snapshot.share) {
                    Text("Percent Spent")
                }
                .gaugeStyle(.accessoryLinear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessoryWidgetBackground()
        .widgetURL(budget.url)
    }
}

struct BudgetAccessoryCircleView: View {
    let budget: BudgetWidgetData

    var body: some View {
        if #available(iOS 16.0, *) {
            Gauge(value: budget.snapshot.share) {
                if let emoji = budget.emoji {
                    Text(emoji)
                } else {
                    Image(systemName: "dollarsign.circle.fill")
                }
            } currentValueLabel: {
                Text("\(Int((budget.snapshot.share * 100).rounded()))%")
            }
            .gaugeStyle(.accessoryCircular)
            .accessoryWidgetBackground()
            .widgetURL(budget.url)
        }
    }
}

struct BudgetAccessoryMessage: View {
    let message: LocalizedStringKey
    var circular = false

    var body: some View {
        ZStack {
            if circular, #available(iOS 16.0, *) {
                AccessoryWidgetBackground()
            }

            Text(message)
                .font(.app(size: circular ? 8 : 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .accessoryWidgetBackground()
    }
}

/// A category's emoji on a tint of its colour, like the rows in the log.
struct WidgetEmojiTile: View {
    let emoji: String
    let colour: String
    let size: CGFloat
    /// An SF Symbol shown in place of the emoji, for transactions without a category.
    var symbol: String?
    /// The tinted square behind the emoji. Quick Add tiles are already tinted, so they leave it out.
    var showsBackground = true

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.app(size: size * 0.42, weight: .bold))
                    .foregroundColor(Color(hex: colour))
            } else {
                Text(emoji)
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .background(Color(hex: colour).opacity(showsBackground ? 0.25 : 0), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The dark capsule with a plus that the app uses for adding a transaction.
struct WidgetNewExpenseButton: View {
    var body: some View {
        Link(destination: URL(string: "dimeapp://newExpense")!) {
            Label("widget-log-button", systemImage: "plus")
                .font(.app(.subheadline, weight: .semibold))
                .foregroundColor(Color.LightIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Color.DarkBackground, in: Capsule())
        }
    }
}

extension View {
    @ViewBuilder func budgetWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color.PrimaryBackground }
        } else {
            padding(15).background(Color.PrimaryBackground)
        }
    }

    @ViewBuilder func accessoryWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}
