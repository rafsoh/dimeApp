//
//  RecentTransactionsWidget.swift
//  ExpenditureWidgetExtension
//
//  Created by Rafael Soh on 12/8/22.
//

import SwiftUI
import WidgetKit

struct RecentExpenditureWidget: Widget {
    let kind: String = "ExpenditureWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 17, *) {
            return [
                .accessoryRectangular,
                .accessoryInline,
                .systemSmall,
                .systemLarge
            ]
        } else if #available(iOSApplicationExtension 16, *) {
            return [
                .accessoryRectangular,
                .accessoryInline,
                .systemSmall
            ]
        } else {
            return [.systemSmall]
        }
    }

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: RecentWidgetConfigurationIntent.self, provider: Provider()) { entry in
            ExpenditureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recent Transactions")
        .description("View your latest expenses.")
        .supportedFamilies(supportedFamilies)
    }
}

struct Provider: IntentTimelineProvider {
    typealias Intent = RecentWidgetConfigurationIntent

    public typealias Entry = RecentWidgetEntry

    func placeholder(in _: Context) -> RecentWidgetEntry {
        RecentWidgetEntry(date: Date(), amount: loadAmount(type: .week, insightsType: .net), transactions: loadTransactions(type: .week, count: 9), duration: .week, type: .net, conversion: loadReport(type: .week, insightsType: .net))
    }

    func getSnapshot(for configuration: RecentWidgetConfigurationIntent, in _: Context, completion: @escaping (RecentWidgetEntry) -> Void) {
        let entry = RecentWidgetEntry(date: Date(), amount: loadAmount(type: configuration.duration, insightsType: configuration.insightsType), transactions: loadTransactions(type: configuration.duration, count: 9), duration: configuration.duration, type: configuration.insightsType, conversion: loadReport(type: configuration.duration, insightsType: configuration.insightsType))
        completion(entry)
    }

    func getTimeline(for configuration: RecentWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = RecentWidgetEntry(date: Date(), amount: loadAmount(type: configuration.duration, insightsType: configuration.insightsType), transactions: loadTransactions(type: configuration.duration, count: 9), duration: configuration.duration, type: configuration.insightsType, conversion: loadReport(type: configuration.duration, insightsType: configuration.insightsType))

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }

    func loadAmount(type: TimePeriod, insightsType: InsightsType) -> Double {
//        let dataController = DataController()
        let dataController = DataController.shared

        let timeframe: Int

        switch type {
        case .day:
            timeframe = 1
        case .week:
            timeframe = 2
        case .month:
            timeframe = 3
        case .year:
            timeframe = 4
        default:
            timeframe = 0
        }

        switch insightsType {
        case .net:
            let (amount, positive) = dataController.getLogViewTotalNet(type: timeframe)

            if positive {
                return amount
            } else {
                return -amount
            }

        case .income:
            return dataController.getLogViewTotalIncome(type: timeframe)
        case .expense:
            return dataController.getLogViewTotalSpent(type: timeframe)
        default:
            return 0
        }
    }

    func loadReport(type: TimePeriod, insightsType: InsightsType) -> ConversionReport {
        let dataController = DataController.shared
        let timeframe: Int

        switch type {
        case .day:
            timeframe = 1
        case .week:
            timeframe = 2
        case .month:
            timeframe = 3
        case .year:
            timeframe = 4
        case .unknown:
            timeframe = 0
        }

        switch insightsType {
        case .net:
            return dataController.logViewNetTotal(type: timeframe).report
        case .income:
            return dataController.logViewTotal(type: timeframe, income: true).report
        case .expense:
            return dataController.logViewTotal(type: timeframe, income: false).report
        case .unknown:
            return ConversionReport()
        }
    }

    func loadTransactions(type: TimePeriod, count: Int) -> [HoldingTransaction] {
//        let dataController = DataController()
        let dataController = DataController.shared
        let itemRequest = dataController.fetchRequestForRecentTransactionsWithCount(type: type, count: count)
        let holding = dataController.results(for: itemRequest)

        var sending = [HoldingTransaction]()

        holding.forEach { transaction in
            let t = HoldingTransaction(colour: transaction.wrappedColour, emoji: transaction.category?.wrappedEmoji ?? "", note: transaction.wrappedNote, amount: transaction.wrappedAmount, income: transaction.income, currencyCode: transaction.currencyCode, uncategorised: transaction.category == nil)

            sending.append(t)
        }

        return sending
    }
}

struct RecentWidgetEntry: TimelineEntry {
    let date: Date
    let amount: Double
    let transactions: [HoldingTransaction]
    let duration: TimePeriod
    let type: InsightsType
    var conversion = ConversionReport()
}

struct HoldingTransaction: Hashable {
    let colour: String
    let emoji: String
    let note: String
    let amount: Double
    let income: Bool
    var currencyCode: String?
    var uncategorised = false
}

struct ExpenditureWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: Provider.Entry
    let formatter = InsightsFormatter.current

    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showExpenseOrIncomeSign: Bool = true

    var periodText: String {
        switch entry.duration {
        case .unknown:
            return ""
        case .day:
            return String(localized: "today")
        case .week:
            return String(localized: "this week")
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return String(localized: "in \(formatter.string(from: Date.now))")
        case .year:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return String(localized: "in \(formatter.string(from: Date.now))")
        }
    }

    var typeText: String {
        switch entry.type {
        case .unknown:
            return ""
        case .net:
            return String(localized: "net")
        case .income:
            return String(localized: "earned")
        case .expense:
            return String(localized: "spent")
        }
    }

    /// "Spent this week", in the app's card title style.
    var title: String {
        let text = "\(typeText) \(periodText)"
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Only net totals carry a sign, like the Net figure on the Insights tab.
    var totalSign: String {
        guard entry.type == .net, entry.amount != 0 else { return "" }
        return entry.amount > 0 ? "+" : "−"
    }

    func amountText(_ transaction: HoldingTransaction) -> String {
        let sign = showExpenseOrIncomeSign ? (transaction.income ? "+" : "-") : ""

        if let code = transaction.currencyCode, !CurrencyConverter.current().isMainCurrency(code) {
            return sign + MoneyFormatter.string(transaction.amount, currencyCode: code, showCents: formatter.showCents)
        }

        return sign + formatter.string(transaction.amount)
    }

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            Text("\(entry.conversion.approximatePrefix)\(totalSign)\(formatter.string(abs(entry.amount))) \(typeText) \(periodText)")

        case .accessoryRectangular:
            accessoryRectangle

        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                header(amountFont: .system(.title2, design: .rounded).weight(.semibold))

                if entry.transactions.isEmpty {
                    emptyMessage
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.transactions.prefix(3).enumerated()), id: \.offset) { _, transaction in
                            row(transaction, tileSize: 20, font: .system(.footnote, design: .rounded).weight(.medium))
                        }
                    }
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                if entry.transactions.count < 2 {
                    WidgetNewExpenseButton()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .budgetWidgetBackground()
            .widgetURL(entry.transactions.count < 2 ? URL(string: "dimeapp://newExpense") : nil)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 0) {
                header(amountFont: .system(.largeTitle, design: .rounded).weight(.semibold))

                if entry.transactions.isEmpty {
                    emptyMessage
                } else {
                    InsightsCardTitle("Recent expenses")
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.transactions.prefix(8).enumerated()), id: \.offset) { _, transaction in
                            row(transaction, tileSize: 26, font: .system(.subheadline, design: .rounded).weight(.medium))
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                if entry.transactions.count < 5 {
                    WidgetNewExpenseButton()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .budgetWidgetBackground()

        default:
            EmptyView()
        }
    }

    func header(amountFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            InsightsCardTitle(verbatim: title)

            InsightsAmountText(amount: abs(entry.amount), sign: entry.conversion.approximatePrefix + totalSign, formatter: formatter, font: amountFont)
        }
    }

    var emptyMessage: some View {
        Text("No recent expenses")
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A log row: the category's emoji tile, the note, and the amount in green for income.
    func row(_ transaction: HoldingTransaction, tileSize: CGFloat, font: Font) -> some View {
        HStack(spacing: 8) {
            WidgetEmojiTile(emoji: transaction.emoji, colour: transaction.colour, size: tileSize, symbol: transaction.uncategorised ? Uncategorised.symbol(income: transaction.income) : nil)

            Text(transaction.note)
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(amountText(transaction))
                .foregroundColor(transaction.income ? Color.IncomeGreen : Color.PrimaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(font)
    }

    var accessoryRectangle: some View {
        Group {
            if entry.transactions.isEmpty {
                Text("No recent expenses")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entry.transactions.prefix(3).enumerated()), id: \.offset) { _, transaction in
                            HStack(spacing: 3) {
                                Text(transaction.note)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(amountText(transaction))
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                            .font(.system(size: rectangularFontSize(width: proxy.size.width), design: .rounded))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
        }
        .accessoryWidgetBackground()
    }

    /// The largest size from 15 down to 12 at which every row's note and amount fit on one line.
    func rectangularFontSize(width: CGFloat) -> CGFloat {
        var fontSize: CGFloat = 15

        while fontSize > 12 {
            let widest = entry.transactions.prefix(3).map {
                $0.note.widthOfRoundedString(size: fontSize, weight: .semibold) + amountText($0).widthOfRoundedString(size: fontSize, weight: .regular) + 8
            }.max() ?? 0

            if width > widest {
                return fontSize
            }

            fontSize -= 1
        }

        return 12
    }
}
