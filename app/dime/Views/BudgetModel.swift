//
//  BudgetModel.swift
//  dime
//

import CoreData
import Foundation
import SwiftUI

// MARK: - Period and maths

struct BudgetPeriod: Equatable {
    /// 1 day, 2 week, 3 month, 4 year, as stored on `Budget.type`.
    let type: Int
    let start: Date

    private var step: (component: Calendar.Component, value: Int) {
        switch type {
        case 1:
            return (.day, 1)
        case 2:
            return (.day, 7)
        case 4:
            return (.year, 1)
        default:
            return (.month, 1)
        }
    }

    var end: Date {
        Calendar.current.date(byAdding: step.component, value: step.value, to: start) ?? start
    }

    var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: end) ?? start
    }

    func shifted(by count: Int) -> BudgetPeriod {
        BudgetPeriod(type: type, start: Calendar.current.date(byAdding: step.component, value: step.value * count, to: start) ?? start)
    }

    var isCurrent: Bool {
        end > Date.now
    }

    /// The period containing now, rolled forward like `DataController.updateBudgetDates()` without saving.
    var current: BudgetPeriod {
        var period = self
        while !period.isCurrent, period.end > period.start {
            period = period.shifted(by: 1)
        }
        return period
    }

    var duration: TimeInterval {
        max(1, end.timeIntervalSince(start))
    }

    func fraction(of date: Date) -> Double {
        min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }

    var elapsed: Double {
        isCurrent ? fraction(of: Date.now) : 1
    }

    var daysLeft: Int {
        let today = Calendar.current.startOfDay(for: Date.now)
        return max(1, Calendar.current.dateComponents([.day], from: today, to: end).day ?? 1)
    }

    var hoursLeft: Int {
        max(1, Int((end.timeIntervalSince(Date.now) / 3600).rounded(.up)))
    }

    /// Chart buckets: hours for a day, days for a week or month, months for a year.
    var bucketEnds: [Date] {
        let unit: Calendar.Component = type == 1 ? .hour : (type == 4 ? .month : .day)
        var ends = [Date]()
        var cursor = start
        while cursor < end, ends.count < 400 {
            cursor = Calendar.current.date(byAdding: unit, value: 1, to: cursor) ?? end
            ends.append(min(cursor, end))
        }
        return ends
    }

    func format(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    var rangeTitle: String {
        switch type {
        case 1:
            return format(start, "d MMM yyyy")
        case 4:
            return format(start, "d MMM yy") + " – " + format(lastDay, "d MMM yy")
        default:
            return format(start, "d MMM") + " – " + format(lastDay, "d MMM")
        }
    }

    /// How a finished period is named, e.g. "October" or "9 Nov – 15 Nov".
    var name: String {
        let calendar = Calendar.current
        let sameYear = calendar.isDate(start, equalTo: Date.now, toGranularity: .year)
        switch type {
        case 1:
            return format(start, "d MMM")
        case 3 where calendar.component(.day, from: start) == 1:
            return format(start, sameYear ? "MMMM" : "MMMM yyyy")
        case 4 where calendar.component(.day, from: start) == 1 && calendar.component(.month, from: start) == 1:
            return format(start, "yyyy")
        default:
            return rangeTitle
        }
    }

    var word: String {
        switch type {
        case 1:
            return String(localized: "today")
        case 2:
            return String(localized: "this week")
        case 4:
            return String(localized: "this year")
        default:
            return String(localized: "this month")
        }
    }

    /// When the next period starts: "tomorrow", a weekday within a week, else a date.
    var resetText: String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(end) {
            return String(localized: "tomorrow")
        }
        if end.timeIntervalSince(Date.now) < 7 * 86400 {
            return format(end, "EEEE")
        }
        return format(end, "d\u{00A0}MMM")
    }

    var toGo: String {
        if type == 1 {
            return hoursLeft == 1 ? String(localized: "1 hour to go") : String(localized: "\(hoursLeft) hours to go")
        }
        return daysLeft == 1 ? String(localized: "1 day to go") : String(localized: "\(daysLeft) days to go")
    }
}

enum BudgetStatus {
    case onTrack
    case abovePace
    case nearLimit
    case over
    case ended
    case fresh
}

struct BudgetSnapshot {
    /// What can be spent this period: the budget plus anything rolled over.
    let amount: Double
    let spent: Double
    let period: BudgetPeriod
    /// What rolled in from earlier periods, or nil when the budget doesn't roll over into this period.
    let carryIn: Double?

    init(amount: Double, spent: Double, period: BudgetPeriod, carryIn: Double? = nil) {
        self.amount = amount + (carryIn ?? 0)
        self.spent = spent
        self.period = period
        self.carryIn = carryIn
    }

    /// The budget's own amount, without rollover.
    var base: Double {
        amount - (carryIn ?? 0)
    }

    var isOver: Bool {
        spent > amount
    }

    var difference: Double {
        abs(amount - spent)
    }

    /// An overspend carried in can leave nothing (or less than nothing) to spend, which reads as a full bar.
    var share: Double {
        amount > 0 ? min(spent / amount, 1) : (spent > 0 || amount < 0 ? 1 : 0)
    }

    var projected: Double {
        guard period.isCurrent, spent > 0, period.elapsed > 0.02 else { return spent }
        return spent / period.elapsed
    }

    var perDay: Double {
        max(0, amount - spent) / Double(period.daysLeft)
    }

    var status: BudgetStatus {
        if !period.isCurrent { return .ended }
        if isOver { return .over }
        if spent <= 0 { return .fresh }
        if share >= 0.8 && (period.type == 1 || share > period.elapsed) { return .nearLimit }
        if share > period.elapsed && projected > amount { return .abovePace }
        return .onTrack
    }

    var showsTick: Bool {
        guard period.type != 1 else { return false }
        switch status {
        case .onTrack, .abovePace, .nearLimit, .fresh:
            return true
        case .over, .ended:
            return false
        }
    }

}

/// Amounts under 100 keep their cents (when the user shows cents); budgets and rates drop a trailing ".00".
struct BudgetFormatter {
    let currencySymbol: String
    let showCents: Bool

    static var current: BudgetFormatter {
        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let code = defaults?.string(forKey: "currency") ?? Locale.current.currencyCode ?? "USD"
        let showCents = defaults?.object(forKey: "showCents") as? Bool ?? true
        return BudgetFormatter(currencySymbol: Locale.current.localizedCurrencySymbol(forCurrencyCode: code) ?? "$", showCents: showCents)
    }

    func number(_ value: Double, trimWhole: Bool = false) -> String {
        let value = abs(value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let cents = showCents && value < 100 && !(trimWhole && value == value.rounded())
        formatter.minimumFractionDigits = cents ? 2 : 0
        formatter.maximumFractionDigits = cents ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func money(_ value: Double, trimWhole: Bool = false) -> String {
        currencySymbol + number(value, trimWhole: trimWhole)
    }

    func whole(_ value: Double) -> String {
        money(value, trimWhole: true)
    }

    /// Estimates read as whole amounts once they're above 10.
    func approx(_ value: Double) -> String {
        abs(value) < 10 ? money(value) : whole(abs(value).rounded())
    }
}

// MARK: - Copy

extension BudgetSnapshot {
    private func strong(_ string: String) -> Text {
        Text(string).fontWeight(.semibold).foregroundColor(Color.PrimaryText)
    }

    private func perDayPhrase(_ f: BudgetFormatter) -> String {
        let days = period.daysLeft
        return days == 1 ? String(localized: "\(f.whole(perDay)) left today") : String(localized: "\(f.whole(perDay)) a day for \(days) days")
    }

    /// "left", "over" or "under" after a category tile's amount.
    var resultWord: String {
        if status == .ended {
            return isOver ? String(localized: "over") : String(localized: "under")
        }
        return isOver ? String(localized: "over") : String(localized: "left")
    }

    func overallAmountWord(_ f: BudgetFormatter) -> String {
        switch status {
        case .onTrack, .abovePace, .nearLimit, .fresh:
            return String(localized: "left of \(f.whole(amount))")
        case .over, .ended:
            return resultWord
        }
    }

    var overallTrailing: String {
        status == .ended ? String(localized: "\(period.name) · ended") : period.toGo
    }

    func tileStatus() -> Text {
        switch status {
        case .onTrack, .abovePace:
            return Text(period.toGo)
        case .nearLimit:
            return strong(String(localized: "Close to limit"))
        case .over:
            return Text(String(localized: "Resets \(period.resetText)"))
        case .ended:
            return Text(period.name)
        case .fresh:
            return Text(String(localized: "Nothing spent yet"))
        }
    }

    func overallLine(_ f: BudgetFormatter) -> Text {
        switch status {
        case .onTrack, .abovePace, .fresh:
            return Text(period.type == 1 ? period.toGo : perDayPhrase(f))
        case .nearLimit:
            return period.type == 1 ? strong(String(localized: "Close to limit")) : strong(String(localized: "Close to limit")) + Text(" · " + String(localized: "\(f.whole(perDay)) a day"))
        case .over, .ended:
            return spentLine(f)
        }
    }

    private func spentLine(_ f: BudgetFormatter) -> Text {
        if status == .ended {
            return Text(String(localized: "Spent \(f.money(spent)) of \(f.whole(amount)) in \(period.name)"))
        }
        return Text(String(localized: "Spent \(f.money(spent)) of \(f.whole(amount)) · resets \(period.resetText)"))
    }

    /// The detail sheet's rollover line, e.g. "+$42 rolled over" or "Leftover rolls over Monday".
    func rolloverText(_ f: BudgetFormatter) -> String? {
        guard let carryIn else { return nil }
        if carryIn >= 0.005 {
            return String(localized: "+\(f.money(carryIn)) rolled over")
        }
        if carryIn <= -0.005 {
            return String(localized: "−\(f.money(carryIn)) overspend rolled over")
        }
        return period.isCurrent ? String(localized: "Leftover rolls over \(period.resetText)") : String(localized: "Nothing rolled over")
    }

    /// The pace chart's top leading label: what's left to spend per day, or when an overspent budget resets.
    func chartLabel(_ f: BudgetFormatter) -> String? {
        switch status {
        case .onTrack, .abovePace, .nearLimit, .fresh:
            return period.type == 1 ? period.toGo : perDayPhrase(f)
        case .over:
            return String(localized: "Resets \(period.resetText)")
        case .ended:
            return nil
        }
    }

}

// MARK: - Shared pieces

/// The red warning mark shown in place of a budget's emoji while it's over.
struct BudgetOverIcon: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.AlertRed)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .accessibilityLabel("Over budget")
    }
}

/// Marks a budget that rolls over, beside its name on the budgets tab.
struct BudgetRolloverIcon: View {
    var body: some View {
        Image(systemName: "arrow.uturn.forward")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundColor(Color.SubtitleText)
            .accessibilityLabel("Rolls over")
    }
}

/// What rolled in, inside the detail sheet's ring: green for a surplus, red for an overspend.
struct BudgetRolloverChip: View {
    let snapshot: BudgetSnapshot
    let formatter: BudgetFormatter

    var body: some View {
        if let text = snapshot.rolloverText(formatter), let carry = snapshot.carryIn {
            let tint: Color = carry >= 0.005 ? Color.IncomeGreen : (carry <= -0.005 ? Color.AlertRed : Color.SubtitleText)

            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                Text(text)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }
}

struct BudgetAmountText: View {
    let amount: Double
    let font: Font
    var formatter = BudgetFormatter.current
    var prefix = ""

    var body: some View {
        (Text(prefix + formatter.currencySymbol)
            .foregroundColor(Color.SubtitleText)
            + Text(formatter.number(amount))
            .foregroundColor(Color.PrimaryText))
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// The pace marker: a small triangle hanging from the top edge of the bar.
private struct BudgetPaceTick: View {
    let barHeight: CGFloat

    var body: some View {
        let width = max(10, barHeight)

        RoundedTriangle(cornerRadius: 1.3)
            .fill(Color.PrimaryText)
            .frame(width: width, height: width * 0.46)
    }
}

struct BudgetMeterSegment: Identifiable {
    let id: String
    let share: Double
    let colour: Color
}

/// A capsule bar filled by one or more segments, with an optional pace tick at `tick` (0...1).
struct BudgetMeter: View {
    let segments: [BudgetMeterSegment]
    let tick: Double?
    let height: CGFloat

    private static let gap: CGFloat = 2

    init(share: Double, colour: Color, tick: Double?, height: CGFloat) {
        segments = [BudgetMeterSegment(id: "fill", share: share, colour: colour)]
        self.tick = tick
        self.height = height
    }

    init(segments: [BudgetMeterSegment], tick: Double?, height: CGFloat) {
        self.segments = segments
        self.tick = tick
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let visible = segments.filter { $0.share * width >= 1 }

            ZStack(alignment: .leading) {
                HStack(spacing: visible.count > 1 ? Self.gap : 0) {
                    ForEach(visible) { segment in
                        Rectangle()
                            .fill(segment.colour)
                            .frame(width: max(0, width * min(segment.share, 1) - (visible.count > 1 ? Self.gap : 0)))
                    }
                    Rectangle()
                        .fill(Color.PrimaryText.opacity(0.12))
                        .frame(maxWidth: .infinity)
                }
                .frame(width: width, alignment: .leading)
                .clipShape(Capsule())

                if let tick {
                    let inset = height / 2
                    let notch = max(10, height) * 0.46
                    BudgetPaceTick(barHeight: height)
                        .position(x: min(max(width * tick, inset), width - inset), y: notch / 2 - 3)
                }
            }
            .compositingGroup()
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension NSManagedObject {
    var isGone: Bool {
        isDeleted || managedObjectContext == nil
    }
}

func budgetPredicate(from start: Date, to end: Date, category: Category?) -> NSPredicate {
    var predicates = [
        NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), start as CVarArg),
        NSPredicate(format: "%K < %@", #keyPath(Transaction.date), end as CVarArg),
        NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg),
        NSPredicate(format: "income = %d", false)
    ]
    if let category {
        predicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
    }
    return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
}

/// Budgeted categories in their own colour, largest first, then everything else as one grey segment.
func budgetStripSegments(_ transactions: [Transaction], denominator: Double) -> [BudgetMeterSegment] {
    guard denominator > 0 else { return [] }
    let converter = CurrencyConverter.current()
    var budgeted = [NSManagedObjectID: (category: Category, amount: Double)]()
    var rest = 0.0
    for transaction in transactions {
        let amount = converter.amountInBreakdown(of: transaction.money)
        if let category = transaction.category, category.budget != nil {
            budgeted[category.objectID, default: (category, 0)].amount += amount
        } else {
            rest += amount
        }
    }
    let own = budgeted.values.sorted { $0.amount > $1.amount }.map {
        BudgetMeterSegment(id: $0.category.objectID.uriRepresentation().absoluteString, share: $0.amount / denominator, colour: Color(hex: $0.category.wrappedColour))
    }
    return own + [BudgetMeterSegment(id: "rest", share: rest / denominator, colour: Color.PrimaryText.opacity(0.42))]
}
