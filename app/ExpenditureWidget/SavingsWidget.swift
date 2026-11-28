//
//  SavingsWidget.swift
//  ExpenditureWidgetExtension
//
//  One goal or debt, picked in the widget's options: laid out like a budget tile on the Home Screen, and as a
//  gauge on the Lock Screen.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct SavingsWidget: Widget {
    static let kind = "SavingsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SavingsWidgetIntent.self, provider: SavingsWidgetProvider()) { entry in
            SavingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Goal or Debt")
        .description("See how a goal or debt is going.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@available(iOSApplicationExtension 17.0, *)
struct SavingsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Goal or Debt"
    static var description = IntentDescription("Choose a goal or debt to show.")

    @Parameter(title: "Goal or Debt")
    var account: SavingsEntity?
}

/// What the widget shows, worked out when the timeline is made.
struct SavingsWidgetItem {
    let name: String
    let symbol: String
    let isDebt: Bool
    let amount: Double
    let word: String
    let status: String
    let share: Double
    let isDone: Bool

    var url: URL? {
        URL(string: isDebt ? "dimeapp://debts" : "dimeapp://goals")
    }

    var colour: Color {
        isDebt ? Color.PrimaryText : Color.IncomeGreen
    }

    static let placeholder = SavingsWidgetItem(name: String(localized: "Holiday"), symbol: "airplane", isDebt: false, amount: 1_840, word: String(localized: "saved"), status: String(localized: "of \(BudgetFormatter.current.whole(3_000))"), share: 0.61, isDone: false)
}

struct SavingsWidgetEntry: TimelineEntry {
    let date: Date
    let item: SavingsWidgetItem?
}

@available(iOSApplicationExtension 17.0, *)
struct SavingsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> SavingsWidgetEntry {
        SavingsWidgetEntry(date: .now, item: .placeholder)
    }

    func snapshot(for configuration: SavingsWidgetIntent, in context: Context) async -> SavingsWidgetEntry {
        let item = await item(for: configuration)
        return SavingsWidgetEntry(date: .now, item: item ?? (context.isPreview ? .placeholder : nil))
    }

    func timeline(for configuration: SavingsWidgetIntent, in _: Context) async -> Timeline<SavingsWidgetEntry> {
        let entry = SavingsWidgetEntry(date: .now, item: await item(for: configuration))
        // Saving in the app reloads it; this catches a new month for a monthly goal.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// The chosen goal or debt, or until one is chosen, the first goal, then the first debt.
    @MainActor
    private func item(for configuration: SavingsWidgetIntent) -> SavingsWidgetItem? {
        let dataController = DataController.shared

        let account: Account?
        if let chosen = configuration.account {
            account = dataController.savingsAccount(withID: chosen.id)
        } else {
            account = dataController.accounts(of: .goal).first ?? dataController.accounts(of: .debt).first
        }

        guard let account else { return nil }

        let summary = SavingsSummary(account: account, formatter: .current, converter: dataController.currencyConverter)
        return SavingsWidgetItem(name: account.wrappedName, symbol: account.wrappedSymbol, isDebt: account.isDebt, amount: summary.amount, word: summary.word, status: summary.status, share: summary.share, isDone: summary.isDone)
    }
}

@available(iOSApplicationExtension 17.0, *)
struct SavingsWidgetView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: SavingsWidgetEntry
    let formatter = BudgetFormatter.current

    var body: some View {
        if let item = entry.item {
            switch widgetFamily {
            case .accessoryInline:
                Text("\(item.name) · \(formatter.money(item.amount)) \(item.word)")
                    .widgetURL(item.url)
            case .accessoryCircular:
                Gauge(value: item.share) {
                    Image(systemName: item.symbol)
                } currentValueLabel: {
                    Image(systemName: item.symbol)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetURL(item.url)
                .accessoryWidgetBackground()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.app(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text("\(formatter.money(item.amount)) \(item.word)")
                        .font(.app(size: 14, weight: .regular))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Gauge(value: item.share) {
                        Text(item.name)
                    }
                    .gaugeStyle(.accessoryLinear)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(item.url)
                .accessoryWidgetBackground()
            default:
                tile(item)
            }
        } else {
            Text(widgetFamily == .systemSmall ? "Add a goal or debt on the Budget tab" : "No goals or debts")
                .font(.app(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.SubtitleText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .budgetWidgetBackground()
        }
    }

    /// Laid out like a budget tile.
    func tile(_ item: SavingsWidgetItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.SubtitleText)

                Text(item.name)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                if item.isDone {
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundColor(Color.IncomeGreen)
                }
            }

            Spacer(minLength: 0)

            BudgetAmountText(amount: item.amount, font: .app(.title, weight: .semibold), formatter: formatter)

            Text(item.word)
                .font(.app(.subheadline, weight: .medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)

            if !item.status.isEmpty {
                Text(item.status)
                    .font(.app(.caption, weight: .medium))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }

            BudgetMeter(share: item.share, colour: item.colour, tick: nil, height: 10)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .budgetWidgetBackground()
        .widgetURL(item.url)
    }
}
