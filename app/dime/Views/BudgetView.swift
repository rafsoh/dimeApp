//
//  BudgetView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import CoreData
import Foundation
import SwiftUI

// MARK: - Tab

struct BudgetView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.dateCreated)
    ]) private var budgets: FetchedResults<Budget>
    @FetchRequest(sortDescriptors: []) private var mainBudget: FetchedResults<MainBudget>

    @Environment(\.managedObjectContext) var moc
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var toastPresenter: OverallToastPresenter

    @AppStorage("budgetViewStyle", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var budgetRows: Bool = false

    @State private var newBudget = false
    @State private var toEdit: Budget?
    @State private var toDelete: Budget?
    @State private var toEditMain: MainBudget?
    @State private var toDeleteMain: MainBudget?
    @State private var detail: BudgetDetailRoute?
    @State private var refreshID = UUID()

    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)

    var columns: [GridItem] {
        let count = budgetRows || dynamicTypeSize >= .xxLarge ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    var body: some View {
        Group {
            if budgets.isEmpty && mainBudget.isEmpty {
                EmptyStateView(systemImage: "chart.bar", title: "No budgets yet")
                    .tabBarClearance()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let overall = mainBudget.first {
                            Button {
                                detail = .overall(overall)
                            } label: {
                                BudgetOverallCard(budget: overall)
                            }
                            .buttonStyle(InsightsCardButtonStyle())
                            .contextMenu {
                                editDeleteMenu {
                                    toEditMain = overall
                                } onDelete: {
                                    toDeleteMain = overall
                                }
                            }
                        }

                        if !budgets.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(budgets, id: \.objectID) { budget in
                                    Button {
                                        detail = .category(budget)
                                    } label: {
                                        BudgetCategoryTile(budget: budget)
                                    }
                                    .buttonStyle(InsightsCardButtonStyle())
                                    .contextMenu {
                                        editDeleteMenu {
                                            toEdit = budget
                                        } onDelete: {
                                            toDelete = budget
                                        }
                                    }
                                }
                            }
                            .padding(.top, mainBudget.isEmpty ? 0 : 12)
                        }
                    }
                    .id(refreshID)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .tabBarClearance()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tabHeader {
            TabHeader("Budgets") {
                GlassIconButton(systemName: "plus", accessibilityLabel: "New Budget") {
                    newBudget = true
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color.PrimaryBackground)
        .onAppear {
            dataController.updateBudgetDates()
        }
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
        .sheet(isPresented: $newBudget) {
            BrandNewBudgetView(overallBudgetCreated: !mainBudget.isEmpty)
        }
        .sheet(item: $toEdit) { budget in
            BrandNewBudgetView(overallBudgetCreated: !mainBudget.isEmpty, toEditBudget: budget)
        }
        .sheet(item: $toEditMain) { budget in
            BrandNewBudgetView(overallBudgetCreated: true, toEditMainBudget: budget)
        }
        .sheet(item: $toDelete) { budget in
            DeleteBudgetAlert(title: "Delete the '\(budget.wrappedName)' budget?") {
                delete(budget)
            }
        }
        .sheet(item: $toDeleteMain) { budget in
            DeleteBudgetAlert(title: "Delete your overall budget?") {
                delete(budget)
            }
        }
        .sheet(item: $detail) { route in
            BudgetDetailSheet(route: route)
                .environmentObject(dataController)
                .environmentObject(toastPresenter)
        }
        #if DEBUG
        .onAppear {
            // `-budgetSheet overall|<category name>` opens that budget's sheet, for screenshots.
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-budgetSheet"), index + 1 < arguments.count else { return }
            let value = arguments[index + 1]
            if value == "overall", let overall = mainBudget.first {
                detail = .overall(overall)
            } else if let budget = budgets.first(where: { $0.wrappedName == value }) {
                detail = .category(budget)
            }
        }
        #endif
    }

    func editDeleteMenu(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        Group {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func delete(_ object: NSManagedObject) {
        withAnimation {
            moc.delete(object)
            dataController.save()
        }
    }
}

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
    let amount: Double
    let spent: Double
    let period: BudgetPeriod

    var isOver: Bool {
        spent > amount
    }

    var difference: Double {
        abs(amount - spent)
    }

    var share: Double {
        amount > 0 ? min(spent / amount, 1) : (spent > 0 ? 1 : 0)
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

struct BudgetAmountText: View {
    let amount: Double
    let font: Font
    var formatter = BudgetFormatter.current

    var body: some View {
        (Text(formatter.currencySymbol)
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
    var budgeted = [NSManagedObjectID: (category: Category, amount: Double)]()
    var rest = 0.0
    for transaction in transactions {
        if let category = transaction.category, category.budget != nil {
            budgeted[category.objectID, default: (category, 0)].amount += transaction.wrappedAmount
        } else {
            rest += transaction.wrappedAmount
        }
    }
    let own = budgeted.values.sorted { $0.amount > $1.amount }.map {
        BudgetMeterSegment(id: $0.category.objectID.uriRepresentation().absoluteString, share: $0.amount / denominator, colour: Color(hex: $0.category.wrappedColour))
    }
    return own + [BudgetMeterSegment(id: "rest", share: rest / denominator, colour: Color.PrimaryText.opacity(0.42))]
}

// MARK: - Tab cells

struct BudgetOverallCard: View {
    @ObservedObject var budget: MainBudget
    @FetchRequest private var transactions: FetchedResults<Transaction>

    let period: BudgetPeriod
    let formatter = BudgetFormatter.current

    init(budget: MainBudget) {
        self.budget = budget
        period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        _transactions = FetchRequest(sortDescriptors: [], predicate: budgetPredicate(from: period.start, to: period.end, category: nil))
    }

    var body: some View {
        if budget.isGone {
            EmptyView()
        } else {
            let snapshot = BudgetSnapshot(amount: budget.amount, spent: transactions.reduce(0) { $0 + $1.wrappedAmount }, period: period)

            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        InsightsCardTitle("Overall")
                        Spacer(minLength: 8)
                        Text(snapshot.overallTrailing)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                        if snapshot.isOver {
                            BudgetOverIcon()
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        BudgetAmountText(amount: snapshot.difference, font: .system(.largeTitle, design: .rounded).weight(.semibold), formatter: formatter)
                            .layoutPriority(1)

                        Text(snapshot.overallAmountWord(formatter))
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 6)

                    BudgetMeter(segments: budgetStripSegments(Array(transactions), denominator: max(snapshot.amount, snapshot.spent)), tick: snapshot.showsTick ? period.elapsed : nil, height: 14)
                        .padding(.top, 14)

                    snapshot.overallLine(formatter)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .padding(.top, 12)
                }
                .padding(16)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the overall budget")
        }
    }
}

struct BudgetCategoryTile: View {
    @ObservedObject var budget: Budget
    @FetchRequest private var transactions: FetchedResults<Transaction>

    let period: BudgetPeriod
    let formatter = BudgetFormatter.current

    init(budget: Budget) {
        self.budget = budget
        period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        _transactions = FetchRequest(sortDescriptors: [], predicate: budgetPredicate(from: period.start, to: period.end, category: budget.category))
    }

    var body: some View {
        if budget.isGone {
            EmptyView()
        } else {
            let snapshot = BudgetSnapshot(amount: budget.amount, spent: transactions.reduce(0) { $0 + $1.wrappedAmount }, period: period)

            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(budget.wrappedEmoji)
                            .font(.system(.body, design: .rounded))
                        Text(budget.wrappedName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)

                        if snapshot.isOver {
                            Spacer(minLength: 4)
                            BudgetOverIcon()
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        BudgetAmountText(amount: snapshot.difference, font: .system(.title, design: .rounded).weight(.semibold), formatter: formatter)
                            .layoutPriority(1)

                        Text(snapshot.resultWord)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                    }
                    .padding(.top, 10)

                    snapshot.tileStatus()
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    BudgetMeter(share: snapshot.share, colour: Color(hex: budget.wrappedColour), tick: snapshot.showsTick ? period.elapsed : nil, height: 14)
                        .padding(.top, 12)
                }
                .padding(EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Detail sheet

enum BudgetDetailRoute: Identifiable {
    case overall(MainBudget)
    case category(Budget)

    var id: NSManagedObjectID {
        switch self {
        case let .overall(budget):
            return budget.objectID
        case let .category(budget):
            return budget.objectID
        }
    }

    var object: NSManagedObject {
        switch self {
        case let .overall(budget):
            return budget
        case let .category(budget):
            return budget
        }
    }

    var category: Category? {
        switch self {
        case .overall:
            return nil
        case let .category(budget):
            return budget.category
        }
    }

    var amount: Double {
        switch self {
        case let .overall(budget):
            return budget.amount
        case let .category(budget):
            return budget.amount
        }
    }

    var currentPeriod: BudgetPeriod {
        switch self {
        case let .overall(budget):
            return BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        case let .category(budget):
            return BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        }
    }
}

struct BudgetDetailSheet: View {
    let route: BudgetDetailRoute

    @FetchRequest private var earliest: FetchedResults<Transaction>
    @FetchRequest(sortDescriptors: []) private var mainBudget: FetchedResults<MainBudget>

    @Environment(\.managedObjectContext) var moc
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController
    @StateObject private var sheetManager = OverallTransactionManager()

    /// How many periods back from the current one the sheet shows.
    @State private var offset = 0
    @State private var refreshID = UUID()
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var confirmedDelete = false
    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)

    init(route: BudgetDetailRoute) {
        self.route = route
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.day, ascending: true)]
        request.fetchLimit = 1
        if let category = route.category {
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category)
        }
        _earliest = FetchRequest(fetchRequest: request)
    }

    var period: BudgetPeriod {
        route.currentPeriod.shifted(by: -offset)
    }

    var canGoPrevious: Bool {
        let first = earliest.first?.day ?? Date.now
        return period.start > first
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    var content: some View {
        ScrollView(showsIndicators: false) {
            if !route.object.isGone {
                BudgetDetailContent(route: route, period: period)
                    .id("\(period.start.timeIntervalSince1970)-\(refreshID)")
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
        .tabHeader {
            header
        }
        .bottomBar {
            if !route.object.isGone {
                GlassStepperCapsule(
                    title: period.rangeTitle,
                    previousLabel: stepLabels.previous,
                    nextLabel: stepLabels.next,
                    canGoPrevious: canGoPrevious,
                    canGoNext: offset > 0
                ) {
                    guard canGoPrevious else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        offset += 1
                    }
                } onNext: {
                    guard offset > 0 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        offset -= 1
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .background {
            DeleteTransactionAlert()
        }
        .sheet(item: $sheetManager.toEdit, onDismiss: {
            sheetManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .sheet(isPresented: $showEdit) {
            switch route {
            case let .overall(budget):
                BrandNewBudgetView(overallBudgetCreated: true, toEditMainBudget: budget)
            case let .category(budget):
                BrandNewBudgetView(overallBudgetCreated: !mainBudget.isEmpty, toEditBudget: budget)
            }
        }
        .sheet(isPresented: $showDelete, onDismiss: deleteIfConfirmed) {
            DeleteBudgetAlert(title: deleteTitle) {
                confirmedDelete = true
            }
        }
        .environmentObject(sheetManager)
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }

            Spacer()

            Menu {
                Button {
                    showEdit = true
                } label: {
                    Label("Edit Budget", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Delete Budget", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .glassBackground(in: Circle(), tint: .glassTint)
            .accessibilityLabel("More")
        }
        .frame(height: 44)
        .overlay {
            title
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .padding(.horizontal, route.category != nil ? 108 : 56)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    var title: Text {
        switch route {
        case .overall:
            return Text("Overall budget")
        case let .category(budget):
            return Text("\(budget.wrappedEmoji) \(budget.wrappedName)")
        }
    }

    var deleteTitle: LocalizedStringKey {
        switch route {
        case .overall:
            return "Delete your overall budget?"
        case let .category(budget):
            return "Delete the '\(budget.wrappedName)' budget?"
        }
    }

    var stepLabels: (previous: LocalizedStringKey, next: LocalizedStringKey) {
        switch period.type {
        case 1:
            return ("Previous day", "Next day")
        case 2:
            return ("Previous week", "Next week")
        case 4:
            return ("Previous year", "Next year")
        default:
            return ("Previous month", "Next month")
        }
    }

    func deleteIfConfirmed() {
        guard confirmedDelete else { return }
        let object = route.object
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                moc.delete(object)
                dataController.save()
            }
        }
    }
}

struct BudgetDetailContent: View {
    let route: BudgetDetailRoute
    let period: BudgetPeriod
    let formatter = BudgetFormatter.current

    @FetchRequest private var periodTransactions: FetchedResults<Transaction>
    @SectionedFetchRequest<Date?, Transaction> private var list: SectionedFetchResults<Date?, Transaction>

    init(route: BudgetDetailRoute, period: BudgetPeriod) {
        self.route = route
        self.period = period
        _periodTransactions = FetchRequest(sortDescriptors: [SortDescriptor(\.date)], predicate: budgetPredicate(from: period.start, to: period.end, category: route.category))
        _list = SectionedFetchRequest(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: budgetPredicate(from: period.start, to: period.end, category: route.category))
    }

    var body: some View {
        let transactions = Array(periodTransactions)
        let snapshot = BudgetSnapshot(amount: route.amount, spent: transactions.reduce(0) { $0 + $1.wrappedAmount }, period: period)

        VStack(alignment: .leading, spacing: 32) {
            hero(snapshot, transactions: transactions)
                .padding(.horizontal, 24)

            if route.category == nil && !transactions.isEmpty {
                breakdown(transactions)
                    .padding(.horizontal, 8)
            }

            if period.type != 1 && snapshot.spent > 0 {
                spendingChart(snapshot, transactions: transactions)
                    .padding(.horizontal, 24)
            }

            if list.isEmpty {
                EmptyStateView(systemImage: "tray", title: "No transactions")
            } else {
                ListView(transactions: _list)
                    .padding(.horizontal, 14)
            }
        }
    }

    func hero(_ snapshot: BudgetSnapshot, transactions: [Transaction]) -> some View {
        ArcRing(segments: ringSegments(snapshot, transactions: transactions), showsTrack: true, tick: snapshot.showsTick ? period.elapsed : nil) {
            BudgetAmountText(amount: snapshot.difference, font: .system(.title, design: .rounded).weight(.semibold), formatter: formatter)

            HStack(spacing: 4) {
                if snapshot.isOver {
                    BudgetOverIcon()
                }
                Text(snapshot.overallAmountWord(formatter))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The category budget's own colour, or the overall budget's budgeted categories then everything else.
    func ringSegments(_ snapshot: BudgetSnapshot, transactions: [Transaction]) -> [ArcRingSegment] {
        let shares: [BudgetMeterSegment]
        if let budget = categoryBudget {
            shares = [BudgetMeterSegment(id: "fill", share: snapshot.share, colour: Color(hex: budget.wrappedColour))]
        } else {
            shares = budgetStripSegments(transactions, denominator: max(snapshot.amount, snapshot.spent))
        }

        var cursor = 0.0
        return shares.filter { $0.share >= 0.005 }.map { segment in
            let start = cursor
            cursor = min(1, cursor + segment.share)
            return ArcRingSegment(id: segment.id, start: start, end: cursor, colour: segment.colour, label: "")
        }
    }

    var categoryBudget: Budget? {
        if case let .category(budget) = route {
            return budget
        }
        return nil
    }

    /// Spending per day (per month for a yearly budget), drawn like the category sheet in Insights,
    /// with the daily allowance and forecast underneath.
    func spendingChart(_ snapshot: BudgetSnapshot, transactions: [Transaction]) -> some View {
        let ends = period.bucketEnds
        let starts = [period.start] + ends.dropLast()
        var values = [Date: Double]()
        var index = 0
        for (start, end) in zip(starts, ends) {
            var total = 0.0
            while index < transactions.count && transactions[index].wrappedDate < end {
                total += transactions[index].wrappedAmount
                index += 1
            }
            values[start] = total
        }

        let elapsed = max(1, starts.filter { $0 <= Date.now }.count)
        let insightsFormatter = InsightsFormatter(currencySymbol: formatter.currencySymbol, showCents: formatter.showCents)
        let buckets = InsightsBucket.make(dates: starts, values: values, type: period.type - 1)
        let colour = categoryBudget?.category?.tokenColour ?? Color.PrimaryText
        let forecast = period.isCurrent && snapshot.projected > snapshot.spent ? snapshot.projected : nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let chartLabel = snapshot.chartLabel(formatter) {
                    Text(chartLabel)
                }

                Spacer(minLength: 0)

                if let forecast {
                    Text(String(localized: "~\(formatter.approx(forecast)) forecasted"))
                }
            }
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            InsightsBarChart(buckets: buckets, average: snapshot.spent / Double(period.isCurrent ? elapsed : starts.count), colour: colour, formatter: insightsFormatter)
        }
    }

    func breakdown(_ transactions: [Transaction]) -> some View {
        let insightsFormatter = InsightsFormatter(currencySymbol: formatter.currencySymbol, showCents: formatter.showCents)

        return VStack(spacing: 0) {
            ForEach(InsightsCategoryTotal.make(from: transactions)) { total in
                InsightsCategoryRow(total: total, formatter: insightsFormatter)
            }
        }
    }
}

// MARK: - Delete

struct DeleteBudgetAlert: View {
    let title: LocalizedStringKey
    let onConfirm: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ConfirmationSheet(title: title, message: "This action cannot be undone.") {
            ConfirmationDestructiveButton {
                dismiss()
                onConfirm()
            }

            ConfirmationCancelButton {
                dismiss()
            }
        }
    }
}
