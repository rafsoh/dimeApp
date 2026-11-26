//
//  QuickAddWidget.swift
//  ExpenditureWidgetExtension
//
//  Buttons for the user's Quick Add templates. Tapping one logs a transaction right from the
//  Home Screen: the intent runs in this extension, so Dime doesn't open.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct QuickAddWidget: Widget {
    static let kind = "QuickAdd"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickAddProvider()) { entry in
            QuickAddWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Add")
        .description("Log your templates with one tap, without opening Dime.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Logs a Quick Add template as a new transaction. The transaction keeps no link to the template.
@available(iOSApplicationExtension 17.0, *)
struct LogQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Add Template"
    static var isDiscoverable = false

    /// The template's Core Data URI, which stays the same for as long as the template exists.
    @Parameter(title: "Template")
    var templateURI: String

    init() {}

    init(templateURI: String) {
        self.templateURI = templateURI
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let dataController = DataController.shared

        if let url = URL(string: templateURI), let template = dataController.quickAddTemplate(withURI: url) {
            // Recorded first: saving reloads the widget, and that reload should already show the tick.
            QuickAddFeedback.record(templateURI)
            dataController.logQuickAddTemplate(template)
        }

        return .result()
    }
}

/// Remembers which button was just tapped, so the widget can show a tick on it for a moment.
enum QuickAddFeedback {
    private static let key = "quickAddLastLogged"
    static let duration: TimeInterval = 2

    static func record(_ templateURI: String) {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(["uri": templateURI, "date": Date.now.timeIntervalSince1970], forKey: key)
    }

    static func recent(at date: Date = .now) -> (uri: String, until: Date)? {
        guard let stored = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.dictionary(forKey: key),
              let uri = stored["uri"] as? String,
              let time = stored["date"] as? TimeInterval
        else {
            return nil
        }

        let until = Date(timeIntervalSince1970: time + duration)
        return until > date ? (uri, until) : nil
    }
}

struct QuickAddItem: Hashable {
    let uri: String
    let title: String
    let emoji: String
    let colour: String
    let uncategorised: Bool
    let income: Bool
    let amountText: String
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
    let items: [QuickAddItem]
    var loggedURI: String?
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in _: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now, items: Self.sampleItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        let items = loadItems()
        completion(QuickAddEntry(date: .now, items: context.isPreview && items.isEmpty ? Self.sampleItems : items))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        let items = loadItems()
        var entries = [QuickAddEntry(date: .now, items: items)]

        // Saving the transaction reloads the widget; show a tick on the tapped button, then take it away.
        if let logged = QuickAddFeedback.recent() {
            entries = [
                QuickAddEntry(date: .now, items: items, loggedURI: logged.uri),
                QuickAddEntry(date: logged.until, items: items)
            ]
        }

        // Templates only change in the app or through this widget, and both reload it.
        completion(Timeline(entries: entries, policy: .never))
    }

    private func loadItems() -> [QuickAddItem] {
        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let mainCurrency = CurrencyConverter.current().mainCurrency
        let showCents = defaults?.object(forKey: "showCents") as? Bool ?? true

        return DataController.shared.quickAddTemplates().prefix(TemplateTransaction.quickAddLimit).map { template in
            let amount = MoneyFormatter.string(template.amount, currencyCode: template.currencyCode ?? mainCurrency, showCents: showCents)

            return QuickAddItem(
                uri: template.objectID.uriRepresentation().absoluteString,
                title: template.displayTitle,
                emoji: template.wrappedEmoji,
                colour: template.wrappedColour,
                uncategorised: template.category == nil,
                income: template.income,
                amountText: (template.income ? "+" : "") + amount
            )
        }
    }

    private static let sampleItems = [
        QuickAddItem(uri: "sample-coffee", title: String(localized: "Coffee"), emoji: "☕️", colour: "#C08552", uncategorised: false, income: false, amountText: "$4.50"),
        QuickAddItem(uri: "sample-lunch", title: String(localized: "Lunch"), emoji: "🥪", colour: "#E5A823", uncategorised: false, income: false, amountText: "$12"),
        QuickAddItem(uri: "sample-bus", title: String(localized: "Bus"), emoji: "🚌", colour: "#3E8EDE", uncategorised: false, income: false, amountText: "$2.90")
    ]
}

@available(iOSApplicationExtension 17.0, *)
struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickAddEntry

    private var spacing: CGFloat {
        family == .systemLarge ? 10 : 8
    }

    var body: some View {
        Group {
            if entry.items.isEmpty {
                emptyState
            } else {
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    GridRow {
                        slot(0)
                        slot(1)
                    }
                    GridRow {
                        slot(2)
                        slot(3)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .budgetWidgetBackground()
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < entry.items.count {
            let item = entry.items[index]

            Button(intent: LogQuickAddIntent(templateURI: item.uri)) {
                QuickAddTile(item: item, large: family == .systemLarge, logged: entry.loggedURI == item.uri)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
        } else {
            Link(destination: URL(string: "dimeapp://quickAdd")!) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.SubtitleText.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(Text("Add a template"))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.app(.title3, weight: .semibold))
                .foregroundColor(Color.SubtitleText)

            Spacer(minLength: 0)

            Text("Quick Add")
                .font(.app(.headline, weight: .semibold))
                .foregroundColor(Color.PrimaryText)

            Text("Add templates in Settings to log them from here.")
                .font(.app(.footnote, weight: .medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "dimeapp://quickAdd"))
    }
}

/// One template's button: its category tile, name and amount. Large widgets stack them in a taller tile.
private struct QuickAddTile: View {
    let item: QuickAddItem
    let large: Bool
    let logged: Bool

    private var tint: Color {
        logged ? Color.IncomeGreen : Color(hex: item.colour)
    }

    var body: some View {
        Group {
            if large {
                VStack(alignment: .leading, spacing: 2) {
                    icon(size: 36)

                    Spacer(minLength: 4)

                    Text(item.title)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(2)

                    amount
                }
                .padding(12)
            } else {
                HStack(spacing: 8) {
                    icon(size: 26)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(.app(.footnote, weight: .semibold))
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)

                        amount
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: large ? 20 : 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: large ? 20 : 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(logged ? Text("Logged \(item.title), \(item.amountText)") : Text("Log \(item.title), \(item.amountText)"))
    }

    private var amount: some View {
        Text(item.amountText)
            .font(.app(large ? .subheadline : .footnote, weight: .medium))
            .foregroundColor(item.income ? Color.IncomeGreen : Color.SubtitleText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        if logged {
            Image(systemName: "checkmark")
                .font(.app(size: size * 0.5, weight: .bold))
                .foregroundColor(Color.IncomeGreen)
                .frame(width: size, height: size)
        } else {
            WidgetEmojiTile(emoji: item.emoji, colour: item.colour, size: size, symbol: item.uncategorised ? Uncategorised.symbol(income: item.income) : nil, showsBackground: false)
        }
    }
}
