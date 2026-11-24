//
//  InsightsWidget.swift
//  dime
//
//  Created by Rafael Soh on 14/8/22.
//

import Foundation
import SwiftUI
import WidgetKit

struct InsightsWidget: Widget {
    let kind: String = "InsightsWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: InsightsWidgetConfigurationIntent.self, provider: InsightsProvider()) { entry in
            InsightsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Insights")
        .description("Analyse your expenditure breakdowns over various time periods.")
        .supportedFamilies([.systemMedium])
    }
}

struct InsightsProvider: IntentTimelineProvider {
    typealias Intent = InsightsWidgetConfigurationIntent

    public typealias Entry = InsightsWidgetEntry

    func placeholder(in _: Context) -> InsightsWidgetEntry {
        let results = loadData(type: .week, income: true)

        return InsightsWidgetEntry(date: Date(), amount: results.amount, duration: .week, maximum: results.maximum, dates: results.dates, dictionary: results.dateDictionary, numberOfDays: results.numberOfDays, average: results.average, categories: results.categories, income: true, conversion: results.report)
    }

    func getSnapshot(for configuration: InsightsWidgetConfigurationIntent, in _: Context, completion: @escaping (InsightsWidgetEntry) -> Void) {
        let loaded = loadData(type: configuration.duration, income: configuration.income == .income)

        let entry = InsightsWidgetEntry(date: Date(), amount: loaded.amount, duration: configuration.duration, maximum: loaded.maximum, dates: loaded.dates, dictionary: loaded.dateDictionary, numberOfDays: loaded.numberOfDays, average: loaded.average, categories: loaded.categories, income: configuration.income == .income, conversion: loaded.report)
        completion(entry)
    }

    func getTimeline(for configuration: InsightsWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let loaded = loadData(type: configuration.duration, income: configuration.income == .income)

        let entry = InsightsWidgetEntry(date: Date(), amount: loaded.amount, duration: configuration.duration, maximum: loaded.maximum, dates: loaded.dates, dictionary: loaded.dateDictionary, numberOfDays: loaded.numberOfDays, average: loaded.average, categories: loaded.categories, income: configuration.income == .income, conversion: loaded.report)

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }

    func loadData(type: InsightsTimePeriod, income: Bool) -> (amount: Double, maximum: Double, average: Double, numberOfDays: Int, dates: [Date], dateDictionary: [Date: Double], categories: [HoldingCategory], report: ConversionReport) {
//        let dataController = DataController()
        let dataController = DataController.shared
        let itemRequest = dataController.fetchRequestForWidgetInsights(type: type, income: income)
        let categoryRequest = dataController.fetchRequestForCategories(income: income)

        let categories = dataController.results(for: categoryRequest)
        let transactions = dataController.results(for: itemRequest.fetchRequest)
        let converter = dataController.currencyConverter
        var report = ConversionReport()
        var iterativeDate = itemRequest.date

        switch type {
        case .unknown:
            return (0, 0, 0, 0, [Date](), [Date: Double](), [HoldingCategory](), report)
        case .week:
            var dates = [Date]()
            var nextDate = iterativeDate

            // calendar initialization
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
            calendar.minimumDaysInFirstWeek = 4

            var dictionary = [Date: Double]()
            var totalForWeek = 0.0
            var maximum = 0.0
            var numberOfDays = 0

            for _ in 1 ... 7 {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = transactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForWeek += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let numberOfDaysPast = Calendar.current.dateComponents([.day], from: itemRequest.date, to: Date.now)

            var holdingCat = [HoldingCategory]()

            for category in categories {
                let holding = transactions.filter {
                    $0.category == category
                }

                let total = holding.reduce(0.0) { $0 + converter.amountInBreakdown(of: $1.money) }

                if total == 0 {
                    continue
                }

                let newCategory = HoldingCategory(colour: category.wrappedColour, emoji: category.wrappedEmoji, name: category.wrappedName, percent: total / totalForWeek)

                holdingCat.append(newCategory)
            }

            holdingCat.sort(by: { lhs, rhs in
                lhs.percent > rhs.percent
            })

            return (totalForWeek, maximum, totalForWeek / Double((numberOfDaysPast.day! + 1)), numberOfDays, dates, dictionary, holdingCat, report)
        case .month:
            var dates = [Date]()
            var nextDate = iterativeDate

            let calendar = Calendar(identifier: .gregorian)
            let range = calendar.range(of: .day, in: .month, for: iterativeDate)!

            var dictionary = [Date: Double]()
            var totalForMonth = 0.0
            var maximum = 0.0
            var numberOfDays = 0

            for _ in 1 ... range.count {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = transactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForMonth += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let numDays = Calendar.current.dateComponents([.day], from: itemRequest.date, to: Date.now)

            var holdingCat = [HoldingCategory]()

            for category in categories {
                let holding = transactions.filter {
                    $0.category == category
                }

                let total = holding.reduce(0.0) { $0 + converter.amountInBreakdown(of: $1.money) }

                if total == 0 {
                    continue
                }

                let newCategory = HoldingCategory(colour: category.wrappedColour, emoji: category.wrappedEmoji, name: category.wrappedName, percent: total / totalForMonth)

                holdingCat.append(newCategory)
            }

            holdingCat.sort(by: { lhs, rhs in
                lhs.percent > rhs.percent
            })

            return (totalForMonth, maximum, totalForMonth / Double((numDays.day! + 1)), numberOfDays, dates, dictionary, holdingCat, report)
        case .year:
            // trackin dates
            var dates = [Date]()
            var nextDate = iterativeDate

            let calendar = Calendar(identifier: .gregorian)

            var dictionary = [Date: Double]()
            var totalForYear = 0.0
            var maximum = 0.0
            var numberOfDays = 0

            for _ in 1 ... 12 {
                nextDate = calendar.date(byAdding: .month, value: 1, to: iterativeDate)!

                let holding = transactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForYear += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let numDays = Calendar.current.dateComponents([.month], from: itemRequest.date, to: Date.now)

            var holdingCat = [HoldingCategory]()

            for category in categories {
                let holding = transactions.filter {
                    $0.category == category
                }

                let total = holding.reduce(0.0) { $0 + converter.amountInBreakdown(of: $1.money) }

                if total == 0 {
                    continue
                }

                let newCategory = HoldingCategory(colour: category.wrappedColour, emoji: category.wrappedEmoji, name: category.wrappedName, percent: total / totalForYear)

                holdingCat.append(newCategory)
            }

            holdingCat.sort(by: { lhs, rhs in
                lhs.percent > rhs.percent
            })

            return (totalForYear, maximum, totalForYear / Double((numDays.month! + 1)), numberOfDays, dates, dictionary, holdingCat, report)
        }
    }
}

struct InsightsWidgetEntry: TimelineEntry {
    let date: Date
    let amount: Double
    let duration: InsightsTimePeriod
    let maximum: Double
    let dates: [Date]
    let dictionary: [Date: Double]
    let numberOfDays: Int
    let average: Double
    let categories: [HoldingCategory]
    let income: Bool
    var conversion = ConversionReport()
}

/// The medium widget, laid out like the Spent and Categories cards on the Insights tab.
struct InsightsWidgetEntryView: View {
    let entry: InsightsProvider.Entry
    let formatter = InsightsFormatter.current

    var title: String {
        let verb = entry.income ? String(localized: "Earned") : String(localized: "Spent")
        switch entry.duration {
        case .unknown:
            return verb
        case .week:
            return "\(verb) \(String(localized: "this week"))"
        case .month:
            return "\(verb) \(String(localized: "this month"))"
        case .year:
            return "\(verb) \(String(localized: "this year"))"
        }
    }

    var buckets: [WidgetChartBucket] {
        let yearly = entry.duration == .year
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = yearly ? "MMMMM" : (entry.duration == .month ? "d" : "EEEEE")

        return entry.dates.enumerated().map { index, date in
            WidgetChartBucket(
                date: date,
                value: entry.dictionary[date] ?? 0,
                label: entry.duration != .month || index % 7 == 0 ? labelFormatter.string(from: date) : "",
                isCurrent: Calendar.current.isDate(date, equalTo: Date.now, toGranularity: yearly ? .month : .day)
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    InsightsCardTitle(verbatim: title)

                    InsightsAmountText(amount: entry.amount, sign: entry.conversion.approximatePrefix, formatter: formatter, font: .system(.title2, design: .rounded).weight(.semibold))
                        .padding(.top, 2)

                    WidgetBarChart(buckets: buckets, average: entry.average, colour: entry.income ? Color.IncomeGreen : Color.PrimaryText, formatter: formatter)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                InsightsWidgetCategories(categories: entry.categories, income: entry.income)
                    .frame(width: proxy.size.width * 0.42)
                    .frame(maxHeight: .infinity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .budgetWidgetBackground()
        .widgetURL(URL(string: "dimeapp://insights"))
    }
}

struct HoldingCategory: Hashable {
    let colour: String
    let emoji: String
    let name: String
    let percent: Double
}

struct WidgetChartBucket: Identifiable {
    let date: Date
    let value: Double
    let label: String
    let isCurrent: Bool

    var id: Date { date }

    var isFuture: Bool { date > Date.now }
}

/// A compact version of the Insights tab's bar chart: tracks behind every bar, today in full
/// strength while the period runs, and a dashed average with its label.
struct WidgetBarChart: View {
    let buckets: [WidgetChartBucket]
    let average: Double
    let colour: Color
    let formatter: InsightsFormatter

    private let averageLabelHeight: CGFloat = 15

    private var maxValue: Double {
        let maximum = max(buckets.map(\.value).max() ?? 0, average)
        return maximum > 0 ? maximum * 1.1 : 1
    }

    private var spacing: CGFloat {
        buckets.count > 20 ? 1.5 : (buckets.count > 8 ? 3 : 6)
    }

    private var radius: CGFloat {
        buckets.count > 20 ? 1.5 : (buckets.count > 8 ? 3 : 5)
    }

    private var trackOpacity: Double {
        buckets.count > 20 ? 0.055 : 0.07
    }

    private var emphasisesCurrent: Bool {
        buckets.contains(where: \.isCurrent)
    }

    // An average of one or two scattered days is noise, so it needs a quarter of the elapsed buckets.
    private var showsAverage: Bool {
        let withData = buckets.filter { $0.value > 0 }.count
        let elapsed = buckets.filter { !$0.isFuture }.count
        return average > 0 && withData > 1 && Double(withData) >= Double(elapsed) * 0.25
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let height = proxy.size.height

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(buckets) { bucket in
                        bar(bucket, height: height)
                    }
                }
                .overlay {
                    if showsAverage {
                        averageOverlay(height: height)
                    }
                }
            }

            HStack(spacing: spacing) {
                ForEach(buckets) { bucket in
                    Text(bucket.label)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundColor(bucket.isCurrent ? Color.PrimaryText : Color.SubtitleText)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    func bar(_ bucket: WidgetChartBucket, height: CGFloat) -> some View {
        let valueHeight = bucket.value > 0 ? max(3, height * bucket.value / maxValue) : 0
        let dimmed = emphasisesCurrent && !bucket.isCurrent

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.PrimaryText.opacity(bucket.isFuture ? trackOpacity / 2 : trackOpacity))

            if valueHeight > 0 {
                RoundedRectangle(cornerRadius: min(radius, valueHeight / 2), style: .continuous)
                    .fill(colour.opacity(dimmed ? 0.7 : 1))
                    .frame(height: valueHeight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // The label sits just above the line, or just below it when the line is too close to the top.
    func averageOverlay(height: CGFloat) -> some View {
        let averageY = height - height * average / maxValue
        let above = averageY - 2 - averageLabelHeight
        let labelY = above >= 0 ? above : min(averageY + 2, height - averageLabelHeight)

        return ZStack(alignment: .topTrailing) {
            Line()
                .stroke(Color.SubtitleText, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
                .frame(height: 1)
                .offset(y: averageY)

            (Text("avg ") + Text(formatter.compact(average)).fontWeight(.semibold))
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .frame(height: averageLabelHeight)
                .background(Color.PrimaryBackground.opacity(0.9), in: Capsule())
                .offset(y: labelY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// The share bar and top categories from the Insights tab's Categories card.
struct InsightsWidgetCategories: View {
    let categories: [HoldingCategory]
    let income: Bool

    private var top: [HoldingCategory] {
        Array(categories.prefix(3))
    }

    func colour(for category: HoldingCategory) -> String {
        income ? Color.colorArray[(categories.firstIndex(of: category) ?? 0) % Color.colorArray.count] : category.colour
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if categories.isEmpty {
                Text("No transactions")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                shareBar

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(top, id: \.self) { category in
                        HStack(spacing: 6) {
                            WidgetEmojiTile(emoji: category.emoji, colour: colour(for: category), size: 20)

                            Text(category.name)
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundColor(Color.PrimaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(Int((category.percent * 100).rounded()))%")
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if categories.count < 3 {
                WidgetNewExpenseButton()
            }
        }
    }

    var shareBar: some View {
        let shown = categories.filter { $0.percent >= 0.01 }
        let shownTotal = shown.reduce(0) { $0 + $1.percent }

        return GeometryReader { proxy in
            let available = proxy.size.width - 2 * CGFloat(max(0, shown.count - 1))

            HStack(spacing: 2) {
                ForEach(shown, id: \.self) { category in
                    Rectangle()
                        .fill(Color(hex: colour(for: category)))
                        .frame(width: max(4, available * category.percent / max(shownTotal, 0.0001)))
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
