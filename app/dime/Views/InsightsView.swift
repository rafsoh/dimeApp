//
//  InsightsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import CoreData
import Foundation
import Popovers
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var toastPresenter: OverallToastPresenter
    @EnvironmentObject var transactionManager: OverallTransactionManager

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @State private var showTimeMenu = false
    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var chartType = 1
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstDayOfMonth: Int = 1
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @State private var periodStart: Date?
    @State private var route: InsightsRoute?
    @State private var refreshID = UUID()

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accounts: FetchedResults<Account>
    /// The account Insights shows; empty for every account.
    @AppStorage(InsightsAccountFilter.key, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var insightsAccount = ""
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainAccountName = ""
    @State private var showAccountPicker = false

    var accountChoices: [AccountChoice] {
        [.main] + accounts.map(AccountChoice.account)
    }

    /// The selected account, or nil for every account, including when the selected one was deleted.
    var selectedAccount: AccountChoice? {
        InsightsAccountFilter.choice(among: accountChoices)
    }

    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)

    var chartTypeString: String {
        if chartType == 1 {
            return "week"
        } else if chartType == 2 {
            return "month"
        } else if chartType == 3 {
            return "year"
        } else {
            return ""
        }
    }

    var formatter: InsightsFormatter {
        InsightsFormatter(currencySymbol: Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? "$", showCents: showCents)
    }

    var currentStart: Date {
        InsightsPeriod.currentStart(type: chartType, firstDayOfMonth: firstDayOfMonth)
    }

    var earliestStart: Date {
        guard let first = transactions.first?.day else { return currentStart }
        return min(currentStart, InsightsPeriod.start(containing: first, type: chartType, firstDayOfMonth: firstDayOfMonth))
    }

    var period: InsightsPeriod {
        InsightsPeriod(type: chartType, start: periodStart ?? currentStart)
    }

    var firstDay: Date? {
        transactions.first?.day
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                EmptyStateView(systemImage: "chart.bar", title: "No insights yet")
                    .tabBarClearance()
            } else {
                ScrollViewReader { scroller in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            if !accounts.isEmpty {
                                accountScopeChip
                            }

                            InsightsDashboard(period: period, dataController: dataController, incomeTracking: incomeTracking, firstDay: firstDay, formatter: formatter, breaksDownByAccount: !accounts.isEmpty && selectedAccount == nil, onSelectAccount: { choice in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    insightsAccount = choice.key
                                }
                            }) { selection in
                                route = selection
                            }
                            .id(refreshID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    #if DEBUG
                    .onAppear {
                        // `-insightsScroll accounts` brings the accounts card into view, for screenshots.
                        if ProcessInfo.processInfo.arguments.contains("-insightsScroll") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                scroller.scrollTo(InsightsDashboard.accountsCardID, anchor: .center)
                            }
                        }
                    }
                    #endif
                }
                .tabBarClearance()
                .floatingAboveTabBar {
                    GlassStepperCapsule(
                        previousLabel: period.previousLabel,
                        nextLabel: period.nextLabel
                    ) { offset in
                        let shifted = period.shifted(by: offset)
                        guard offset == 0 || (shifted.start >= earliestStart && shifted.start <= currentStart) else { return nil }
                        return shifted.title
                    } onStep: { offset in
                        step(by: offset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabHeader {
            TabHeader("Insights") {
                GlassCapsuleButton(LocalizedStringKey(chartTypeString), trailingSystemImage: "chevron.up.chevron.down") {
                    showTimeMenu = true
                }
                .popover(present: $showTimeMenu, attributes: {
                    $0.position = .absolute(
                        originAnchor: .bottomRight,
                        popoverAnchor: .topRight
                    )
                    $0.rubberBandingMode = .none
                    $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                    $0.presentation.animation = .easeInOut(duration: 0.2)
                    $0.dismissal.animation = .easeInOut(duration: 0.3)
                }) {
                    ChartTimePickerView(showMenu: $showTimeMenu)
                }
                .disabled(transactions.isEmpty)
                .opacity(transactions.isEmpty ? 0.4 : 1)
            }
        }
        .background(Color.PrimaryBackground)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
        .onChange(of: chartType) { _ in
            periodStart = nil
        }
        .onChange(of: firstDayOfMonth) { _ in
            periodStart = nil
        }
        .onChange(of: insightsAccount) { _ in
            refreshID = UUID()
        }
        .sheet(isPresented: $showAccountPicker) {
            AccountPickerSheet(title: "Account", selection: Binding(get: { selectedAccount }, set: { insightsAccount = $0?.key ?? "" }), allowsAll: true)
                .environmentObject(dataController)
        }
        #if DEBUG
        .onAppear {
            // `-insightsSheet category|categories|cashFlow|recurring` opens that sheet, for screenshots.
            let arguments = ProcessInfo.processInfo.arguments

            // `-insightsAccount <name>` shows one account, and `-insightsAccount all` every account.
            if let index = arguments.firstIndex(of: "-insightsAccount"), index + 1 < arguments.count {
                insightsAccount = accounts.first { $0.wrappedName == arguments[index + 1] }?.key ?? ""
            }

            guard let index = arguments.firstIndex(of: "-insightsSheet") else { return }
            let value = index + 1 < arguments.count ? arguments[index + 1] : "category"

            if value == "categories" {
                route = .allCategories
            } else if value == "cashFlow" {
                route = .cashFlow
            } else if value == "recurring" {
                route = .recurring
            } else {
                let expenses = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: false)
                if let top = InsightsCategoryTotal.make(from: expenses).first {
                    route = .category(top.slice)
                }
            }
        }
        #endif
        .sheet(item: $route) { selection in
            InsightsDetailSheet(route: selection, period: period, firstDay: firstDay, formatter: formatter)
                .environmentObject(dataController)
                .environmentObject(toastPresenter)
        }
    }

    /// Which account the dashboard shows. Hidden until there's an account besides Main.
    var accountScopeChip: some View {
        HStack {
            Button {
                showAccountPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.pass.fill")
                        .foregroundColor(Color.SubtitleText)

                    Text(selectedAccount?.name ?? String(localized: "All Accounts"))
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Color.SubtitleText)
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(in: Capsule(), tint: selectedAccount == nil ? .glassTint : Color.PrimaryText.opacity(0.16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Account") + Text(", ") + Text(selectedAccount?.name ?? String(localized: "All Accounts")))
            .accessibilityAddTraits(.isButton)

            if selectedAccount != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        insightsAccount = ""
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Color.SubtitleText)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassBackground(in: Circle(), tint: .glassTint)
                .accessibilityLabel("Show all accounts")
                .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    func step(by value: Int) {
        let next = period.shifted(by: value).start
        guard next >= earliestStart && next <= currentStart else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            periodStart = next
        }
    }
}

// MARK: - Account

/// The account Insights shows, kept between launches like its time frame. Nothing saved means every account.
enum InsightsAccountFilter {
    static let key = "insightsAccount"

    static var selection: String {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.string(forKey: key) ?? ""
    }

    /// The selected account, or nil for every account, including when the selected one was deleted.
    static func choice(among choices: [AccountChoice]) -> AccountChoice? {
        let key = selection
        guard !key.isEmpty else { return nil }
        return choices.first { $0.key == key }
    }

    /// Matches the selected account's transactions, or nil for every account.
    static func predicate(in dataController: DataController) -> NSPredicate? {
        let key = selection
        guard !key.isEmpty else { return nil }
        return AccountScope(keys: [key]).predicate(in: dataController.container.viewContext)
    }
}

// MARK: - Period

struct InsightsPeriod: Equatable {
    let type: Int
    let start: Date

    static var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func start(containing date: Date, type: Int, firstDayOfMonth: Int) -> Date {
        if type == 1 {
            let calendar = weekCalendar
            return calendar.date(from: calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)) ?? date
        } else if type == 2 {
            return calculateStartOfMonthPeriod(earliestDate: date, startOfMonthDay: firstDayOfMonth)
        } else {
            let calendar = Calendar(identifier: .gregorian)
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        }
    }

    static func currentStart(type: Int, firstDayOfMonth: Int) -> Date {
        if type == 2 {
            return getStartOfMonth(startDay: firstDayOfMonth)
        } else {
            return start(containing: Date.now, type: type, firstDayOfMonth: firstDayOfMonth)
        }
    }

    var component: Calendar.Component {
        if type == 1 {
            return .weekOfYear
        } else if type == 2 {
            return .month
        } else {
            return .year
        }
    }

    var end: Date {
        Calendar.current.date(byAdding: component, value: 1, to: start) ?? start
    }

    var queryEnd: Date {
        min(end, Date.now)
    }

    var isCurrent: Bool {
        start <= Date.now && Date.now < end
    }

    func shifted(by value: Int) -> InsightsPeriod {
        InsightsPeriod(type: type, start: Calendar.current.date(byAdding: component, value: value, to: start) ?? start)
    }

    var title: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if type == 1 {
            let last = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            formatter.dateFormat = "d MMM"

            if calendar.isDate(start, equalTo: last, toGranularity: .month) {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "d"
                return dayFormatter.string(from: start) + " – " + formatter.string(from: last)
            } else {
                return formatter.string(from: start) + " – " + formatter.string(from: last)
            }
        } else if type == 2 {
            if calendar.component(.day, from: start) == 1 {
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: start)
            } else {
                let last = calendar.date(byAdding: .day, value: -1, to: end) ?? start
                formatter.dateFormat = "d MMM"
                return formatter.string(from: start) + " – " + formatter.string(from: last)
            }
        } else {
            formatter.dateFormat = "yyyy"
            return formatter.string(from: start)
        }
    }

    var previousLabel: LocalizedStringKey {
        if type == 1 {
            return "Previous week"
        } else if type == 2 {
            return "Previous month"
        } else {
            return "Previous year"
        }
    }

    var nextLabel: LocalizedStringKey {
        if type == 1 {
            return "Next week"
        } else if type == 2 {
            return "Next month"
        } else {
            return "Next year"
        }
    }

    var comparisonLabel: LocalizedStringKey {
        if type == 1 {
            return "vs last week"
        } else if type == 2 {
            return "vs last month"
        } else {
            return "vs last year"
        }
    }

    // A month that starts late in the calendar month is named after the month most of it falls in.
    var shortLabel: String {
        let formatter = DateFormatter()

        if type == 1 {
            formatter.dateFormat = "d MMM"
            return formatter.string(from: start)
        } else if type == 2 {
            formatter.dateFormat = "MMM"
            return formatter.string(from: Calendar.current.date(byAdding: .day, value: 15, to: start) ?? start)
        } else {
            formatter.dateFormat = "yyyy"
            return formatter.string(from: start)
        }
    }

    var bucketDateFormat: String {
        type == 3 ? "MMMM yyyy" : "EEE d MMM"
    }

    func bucketEnd(for date: Date) -> Date {
        let next = Calendar.current.date(byAdding: type == 3 ? .month : .day, value: 1, to: date) ?? date
        return min(next, Date.now)
    }
}

// MARK: - Data

struct InsightsBucket: Identifiable {
    let date: Date
    let value: Double
    let label: String
    let accessibilityDate: String

    let isCurrent: Bool

    var id: Date { date }

    var isFuture: Bool { date > Date.now }

    static func make(dates: [Date], values: [Date: Double], type: Int) -> [InsightsBucket] {
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = type == 1 ? "EEEEE" : (type == 2 ? "d" : "MMMMM")

        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.dateFormat = type == 3 ? "MMMM" : "EEEE d MMMM"

        return dates.enumerated().map { index, date in
            let showsLabel = type != 2 || index % 7 == 0
            return InsightsBucket(
                date: date,
                value: values[date] ?? 0,
                label: showsLabel ? labelFormatter.string(from: date) : "",
                accessibilityDate: accessibilityFormatter.string(from: date),
                isCurrent: Calendar.current.isDate(date, equalTo: Date.now, toGranularity: type == 3 ? .month : .day)
            )
        }
    }
}

/// One category's transactions, or those without a category.
enum CategorySlice: Hashable {
    case categorised(Category)
    case uncategorised(income: Bool)

    init(_ transaction: Transaction) {
        if let category = transaction.category {
            self = .categorised(category)
        } else {
            self = .uncategorised(income: transaction.income)
        }
    }

    var category: Category? {
        if case let .categorised(category) = self { return category }
        return nil
    }

    var income: Bool {
        switch self {
        case let .categorised(category): return category.income
        case let .uncategorised(income): return income
        }
    }

    var id: String {
        switch self {
        case let .categorised(category): return category.objectID.uriRepresentation().absoluteString
        case let .uncategorised(income): return income ? "uncategorised-income" : "uncategorised"
        }
    }

    var name: String {
        category?.wrappedName ?? Uncategorised.name
    }

    var tokenColour: Color {
        category?.tokenColour ?? Color(hex: Uncategorised.colour)
    }

    var predicate: NSPredicate {
        if let category {
            return NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category)
        }
        // Transfers have no category either, but they're neither spending nor income.
        return NSPredicate(format: "%K == nil AND income = %d AND %K == nil", #keyPath(Transaction.category), income, #keyPath(Transaction.transferID))
    }
}

struct InsightsCategoryTotal: Identifiable {
    let slice: CategorySlice
    let amount: Double
    let share: Double

    var id: String { slice.id }

    static func make(from transactions: [Transaction], using converter: CurrencyConverter = .current()) -> [InsightsCategoryTotal] {
        var totals = [CategorySlice: Double]()

        for transaction in transactions {
            totals[CategorySlice(transaction), default: 0] += converter.amountInBreakdown(of: transaction.money)
        }

        let total = totals.values.reduce(0, +)

        return totals
            .map { InsightsCategoryTotal(slice: $0.key, amount: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { $0.amount > $1.amount }
    }
}

/// One account's share of a period's spending.
struct InsightsAccountTotal: Identifiable {
    let account: AccountChoice
    let amount: Double
    let share: Double

    var id: String { account.key }

    static func make(from transactions: [Transaction], using converter: CurrencyConverter = .current()) -> [InsightsAccountTotal] {
        var totals = [AccountChoice: Double]()

        for transaction in transactions {
            totals[transaction.accountChoice, default: 0] += converter.amountInBreakdown(of: transaction.money)
        }

        let total = totals.values.reduce(0, +)

        return totals
            .filter { $0.value > 0 }
            .map { InsightsAccountTotal(account: $0.key, amount: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { $0.amount == $1.amount ? $0.account.key < $1.account.key : $0.amount > $1.amount }
    }
}

// A period still in progress is measured against the same stretch of the previous one, not all of it.
func insightsCategoryChange(_ dataController: DataController, period: InsightsPeriod, slice: CategorySlice, amount: Double) -> Int? {
    let previous = period.shifted(by: -1)
    let cutoff = period.isCurrent ? previous.start.addingTimeInterval(Date.now.timeIntervalSince(period.start)) : period.start
    let base = insightsTransactions(dataController, from: previous.start, to: cutoff, income: slice.income, slice: slice).total(using: .current()).value

    guard base > 0, amount > 0 else { return nil }

    let percent = Int(((amount - base) / base * 100).rounded())
    return percent == 0 ? nil : percent
}

struct InsightsProjection {
    let amount: Double
    let change: Double?

    // Recurring charges are added as scheduled rather than extrapolated, so rent paid on the 1st doesn't inflate the pace.
    static func make(period: InsightsPeriod, expenses: [Transaction], previous: Double, firstDay: Date?, recurring: [InsightsRecurringCharge]) -> InsightsProjection? {
        guard period.isCurrent, expenses.count >= 3 else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let trackedStart = calendar.startOfDay(for: max(period.start, firstDay ?? period.start))
        let elapsed = (calendar.dateComponents([.day], from: trackedStart, to: today).day ?? 0) + 1

        guard elapsed > 2, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        let remaining = max(0, calendar.dateComponents([.day], from: tomorrow, to: period.end).day ?? 0)
        let converter = CurrencyConverter.current()
        let spent = expenses.total(using: converter).value
        let discretionary = expenses.filter { !$0.onceRecurring }.total(using: converter).value
        let scheduled = recurring.reduce(0) { $0 + $1.total(from: period.start, to: period.end) }
        let amount = spent + discretionary / Double(elapsed) * Double(remaining) + scheduled

        return InsightsProjection(amount: amount, change: previous > 0 ? (amount - previous) / previous : nil)
    }
}

struct InsightsCashFlowPoint: Identifiable {
    let start: Date
    let end: Date
    let label: String
    let title: String
    let inPeriod: Bool
    var income = 0.0
    var spent = 0.0

    var id: Date { start }

    var net: Double { income - spent }

    var hasData: Bool { income > 0 || spent > 0 }

    var isFuture: Bool { start > Date.now }

    var isCurrent: Bool { start <= Date.now && Date.now < end }
}

struct InsightsCashFlow {
    let period: InsightsPeriod
    let points: [InsightsCashFlowPoint]
    let usesPeriods: Bool
    let income: Double
    let spent: Double
    let report: ConversionReport

    // The chart always has `count` slots. Whole periods are compared once tracking covers nearly all of them;
    // before that it steps down to days, weeks or months, and slots without data show as empty tracks.
    static func make(_ dataController: DataController, period: InsightsPeriod, count: Int, firstDay: Date?) -> InsightsCashFlow {
        let tracked = Calendar.current.startOfDay(for: firstDay ?? period.start)
        let primary = periods(endingAt: period, count: count)
        let usesPeriods = primary.filter { $0.end > tracked }.count >= count - 1
        var points = usesPeriods ? primary : finer(than: period, count: count)

        let from = min(points.first?.start ?? period.start, period.start)
        let transactions = insightsTransactions(dataController, from: from, to: period.queryEnd, income: nil)
        let converter = CurrencyConverter.current()
        var report = ConversionReport()
        var income = 0.0
        var spent = 0.0

        for transaction in transactions {
            let date = transaction.wrappedDate
            let amount = converter.amount(of: transaction.money, report: &report)

            if let index = points.firstIndex(where: { date >= $0.start && date < $0.end }) {
                if transaction.income {
                    points[index].income += amount
                } else {
                    points[index].spent += amount
                }
            }

            if date >= period.start {
                if transaction.income {
                    income += amount
                } else {
                    spent += amount
                }
            }
        }

        return InsightsCashFlow(period: period, points: points, usesPeriods: usesPeriods, income: income, spent: spent, report: report)
    }

    static func periods(endingAt period: InsightsPeriod, count: Int) -> [InsightsCashFlowPoint] {
        (0 ..< count).reversed().map { offset in
            let item = period.shifted(by: -offset)
            return InsightsCashFlowPoint(start: item.start, end: offset == 0 ? period.queryEnd : item.end, label: item.shortLabel, title: item.title, inPeriod: offset == 0)
        }
    }

    // Weeks step down to their days, so the rest of the week stays visible; months and years end at today.
    static func finer(than period: InsightsPeriod, count: Int) -> [InsightsCashFlowPoint] {
        let calendar = period.type == 2 ? InsightsPeriod.weekCalendar : Calendar.current
        let component: Calendar.Component = period.type == 1 ? .day : (period.type == 2 ? .weekOfYear : .month)
        let slots = period.type == 1 ? count / 6 * 7 : count
        let reference = period.type == 1 || !period.isCurrent ? period.end.addingTimeInterval(-1) : Date.now

        guard let last = calendar.dateInterval(of: component, for: reference)?.start else { return [] }

        return (0 ..< slots).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: component, value: -offset, to: last),
                  let end = calendar.date(byAdding: component, value: 1, to: start) else { return nil }

            let (label, title) = names(start: start, end: end, component: component)
            return InsightsCashFlowPoint(start: start, end: min(end, max(start, period.queryEnd)), label: label, title: title, inPeriod: end > period.start && start < period.end)
        }
    }

    static func names(start: Date, end: Date, component: Calendar.Component) -> (String, String) {
        let formatter = DateFormatter()

        if component == .day {
            formatter.dateFormat = "EEE"
            let label = formatter.string(from: start)
            formatter.dateFormat = "EEE d MMM"
            return (label, formatter.string(from: start))
        } else if component == .weekOfYear {
            let last = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? start
            formatter.dateFormat = "d MMM"
            return (formatter.string(from: start), formatter.string(from: start) + " – " + formatter.string(from: last))
        } else {
            formatter.dateFormat = "MMM"
            let label = formatter.string(from: start)
            formatter.dateFormat = "MMMM yyyy"
            return (label, formatter.string(from: start))
        }
    }
}

struct InsightsRecurringCharge: Identifiable {
    let transaction: Transaction
    let next: Date

    var id: NSManagedObjectID { transaction.objectID }

    // In the main currency at the latest rate known for the next charge, or nil without one.
    var amount: Double? {
        CurrencyConverter.current().convert(transaction.amount, from: transaction.currencyCode, on: next)
    }

    // A month averages 365.25 / 12 days.
    var monthly: Double {
        let interval = Double(max(1, Int(transaction.recurringCoefficient)))
        let amount = self.amount ?? 0

        if transaction.recurringType == 1 {
            return amount * 30.4375 / interval
        } else if transaction.recurringType == 2 {
            return amount * 30.4375 / 7 / interval
        } else if transaction.recurringType == 3 {
            return amount / interval
        } else {
            return 0
        }
    }

    var cadence: String {
        let interval = max(1, Int(transaction.recurringCoefficient))

        if transaction.recurringType == 1 {
            return interval == 1 ? String(localized: "Daily") : String(localized: "Every \(interval) days")
        } else if transaction.recurringType == 2 {
            return interval == 1 ? String(localized: "Weekly") : String(localized: "Every \(interval) weeks")
        } else if interval == 12 {
            return String(localized: "Yearly")
        } else {
            return interval == 1 ? String(localized: "Monthly") : String(localized: "Every \(interval) months")
        }
    }

    var due: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date.now), to: calendar.startOfDay(for: next)).day ?? 0

        if days > 30 {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: next)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: max(0, days)))
    }

    var subtitle: String {
        due + " · " + cadence
    }

    // Charges not logged yet; logged ones are already in the period's transactions.
    func total(from start: Date, to end: Date) -> Double {
        let amount = self.amount ?? 0
        var total = 0.0
        var date: Date? = next

        while let current = date, current < end {
            if current >= start {
                total += amount
            }
            date = transaction.recurrenceDate(after: current)
        }

        return total
    }

    static func report(for charges: [InsightsRecurringCharge]) -> ConversionReport {
        let converter = CurrencyConverter.current()
        var report = ConversionReport()

        for charge in charges where !converter.isMainCurrency(charge.transaction.currencyCode) {
            if charge.amount == nil {
                report.recordExcluded(charge.transaction.money)
            } else {
                report.recordConverted()
            }
        }

        return report
    }

    // Sync can leave duplicate copies of a recurring transaction under the same id, so only the first counts.
    static func make(_ dataController: DataController) -> [InsightsRecurringCharge] {
        let now = Date.now
        var seen = Set<UUID>()

        let request = dataController.fetchRequestForRecurringTransactions()

        if let accounts = InsightsAccountFilter.predicate(in: dataController) {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [request.predicate, accounts].compactMap { $0 })
        }

        return dataController.results(for: request)
            .filter { transaction in
                guard !transaction.income, (1 ... 3).contains(transaction.recurringType) else { return false }
                guard let id = transaction.id else { return true }
                return seen.insert(id).inserted
            }
            .map { InsightsRecurringCharge(transaction: $0, next: $0.wrappedDate > now ? $0.wrappedDate : $0.nextTransactionDate) }
            .sorted { $0.next == $1.next ? ($0.amount ?? 0) > ($1.amount ?? 0) : $0.next < $1.next }
    }
}

// Compared in the main currency; amounts without a rate sort last.
func insightsLargestFirst(_ transactions: [Transaction]) -> [Transaction] {
    let converter = CurrencyConverter.current()
    let amounts = Dictionary(transactions.map { ($0.objectID, converter.convert($0.amount, from: $0.currencyCode, on: $0.wrappedDate) ?? -.infinity) }, uniquingKeysWith: { first, _ in first })

    return transactions.sorted { (amounts[$0.objectID] ?? -.infinity) > (amounts[$1.objectID] ?? -.infinity) }
}

/// Spending or income in a period, in the account Insights shows. Transfers are neither.
func insightsTransactions(_ dataController: DataController, from start: Date, to end: Date, income: Bool?, slice: CategorySlice? = nil) -> [Transaction] {
    let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()

    var predicates = [
        NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), start as CVarArg),
        NSPredicate(format: "%K < %@", #keyPath(Transaction.date), end as CVarArg),
        TransferPredicate.excluded
    ]

    if let accounts = InsightsAccountFilter.predicate(in: dataController) {
        predicates.append(accounts)
    }

    if let income {
        predicates.append(NSPredicate(format: "income = %d", income))
    }

    if let slice {
        predicates.append(slice.predicate)
    }

    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

    return dataController.results(for: request)
}

func insightsFirstTransactionDate(_ dataController: DataController, from start: Date, to end: Date) -> Date? {
    let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), start as CVarArg),
        NSPredicate(format: "%K < %@", #keyPath(Transaction.date), end as CVarArg),
        TransferPredicate.excluded
    ] + [InsightsAccountFilter.predicate(in: dataController)].compactMap { $0 })
    request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
    request.fetchLimit = 1

    return dataController.results(for: request).first?.date
}

// An average's divisor: days for weeks and months, months for years, skipping time before the first transaction.
func insightsAverageSpan(_ dataController: DataController, period: InsightsPeriod, firstDay: Date?) -> Int {
    let calendar = Calendar.current
    let last = calendar.startOfDay(for: min(period.end.addingTimeInterval(-1), Date.now))

    if period.type == 3 {
        let first = insightsFirstTransactionDate(dataController, from: period.start, to: period.queryEnd) ?? period.start
        let monthStart = { (date: Date) in calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date }
        let months = calendar.dateComponents([.month], from: monthStart(first), to: monthStart(last)).month ?? 0
        return max(1, months + 1)
    }

    let start = calendar.startOfDay(for: max(period.start, firstDay ?? period.start))
    return max(1, (calendar.dateComponents([.day], from: start, to: last).day ?? 0) + 1)
}

// MARK: - Dashboard

struct InsightsDashboard: View {
    let period: InsightsPeriod
    let incomeTracking: Bool
    let formatter: InsightsFormatter
    let onSelect: (InsightsRoute) -> Void
    let buckets: [InsightsBucket]
    let spent: Double
    let spentReport: ConversionReport
    let average: Double
    let income: Double
    let net: Double
    let change: Double?
    let projection: InsightsProjection?
    let categories: [InsightsCategoryTotal]
    let largest: [Transaction]
    let cashFlow: InsightsCashFlow?
    let recurring: [InsightsRecurringCharge]
    let accountTotals: [InsightsAccountTotal]
    let onSelectAccount: ((AccountChoice) -> Void)?

    // Without income anywhere in the chart's window, income and net would only restate spending.
    var showsCashFlow: Bool {
        guard let cashFlow else { return false }
        return incomeTracking && (income > 0 || spent > 0) && cashFlow.points.contains { $0.income > 0 }
    }

    // A period in progress compares its projected total; one still too young to project compares as is.
    var changePercent: Int? {
        guard let comparison = projection.map(\.change) ?? change else { return nil }

        let percent = Int((comparison * 100).rounded())
        return percent == 0 ? nil : percent
    }

    var body: some View {
        VStack(spacing: 12) {
            spentCard

            if showsCashFlow {
                cashFlowCard
                    .transition(.opacity)
            }

            if !categories.isEmpty {
                categoriesCard
                    .transition(.opacity)
            }

            // Only worth a card once spending is spread over more than one account.
            if accountTotals.count > 1 {
                accountsCard
                    .id(Self.accountsCardID)
                    .transition(.opacity)
            }

            if !largest.isEmpty {
                largestCard
                    .transition(.opacity)
            }

            if !recurring.isEmpty {
                recurringCard
                    .transition(.opacity)
            }
        }
    }

    var spentSummary: LocalizedStringKey? {
        projection.map { "~\(formatter.rounded($0.amount)) forecasted" } ?? (spent == 0 ? "No spending in this period" : nil)
    }

    // Pace and comparison share a footer row; either one alone sits beside the title instead.
    var spentCard: some View {
        let summary = spentSummary
        let hasFooter = summary != nil && changePercent != nil

        return InsightsCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        InsightsCardTitle("Spent")
                            .layoutPriority(1)

                        Spacer(minLength: 0)

                        if !hasFooter {
                            spentLabels(summary: summary)
                        }
                    }

                    InsightsAmountText(amount: spent, formatter: formatter, font: .system(.largeTitle, design: .rounded).weight(.semibold))

                    ConversionNote(report: spentReport)
                }

                InsightsBarChart(buckets: buckets, average: average, formatter: formatter) { bucket in
                    onSelect(.bucket(bucket.date))
                }
                .id(period.start)
                .padding(.top, 12)

                if hasFooter {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        spentLabels(summary: summary)
                    }
                    .padding(.top, 14)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    func spentLabels(summary: LocalizedStringKey?) -> some View {
        if let summary {
            Text(summary)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }

        if summary != nil && changePercent != nil {
            Spacer(minLength: 0)
        }

        if let changePercent {
            InsightsChangeLabel(percent: changePercent, comparison: period.comparisonLabel)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
    }

    var cashFlowCard: some View {
        Button {
            onSelect(.cashFlow)
        } label: {
            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cashFlowFigure(title: "Income", amount: income, sign: "")

                        cashFlowFigure(title: "Net", amount: abs(net), sign: net < 0 ? "−" : "+")
                    }

                    if let cashFlow {
                        InsightsCashFlowChart(points: cashFlow.points, selected: cashFlow.usesPeriods ? cashFlow.points.count - 1 : nil, formatter: formatter)
                            .padding(.top, 12)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(InsightsCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Income") + Text(" \(formatter.string(income)), ") + Text("Net") + Text(" \(net < 0 ? "−" : "+")\(formatter.string(abs(net)))"))
        .accessibilityAddTraits(.isButton)
    }

    func cashFlowFigure(title: LocalizedStringKey, amount: Double, sign: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InsightsCardTitle(title)

            InsightsAmountText(amount: amount, sign: sign, formatter: formatter, font: .system(.title2, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var categoriesCard: some View {
        InsightsTappableCard {
            onSelect(.allCategories)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    InsightsCardTitle("Top categories")

                    InsightsShareBar(categories: categories)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 13)

                ForEach(categories.prefix(3)) { total in
                    InsightsCategoryRow(total: total, formatter: formatter) {
                        onSelect(.category(total.slice))
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    static let accountsCardID = "accountsCard"

    var accountsCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 0) {
                InsightsCardTitle("Spending by account")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(accountTotals) { total in
                    InsightsAccountRow(total: total, formatter: formatter) {
                        onSelectAccount?(total.account)
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    var largestCard: some View {
        InsightsTappableCard {
            onSelect(.largest)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                InsightsCardTitle("Largest expenses")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                ForEach(largest, id: \.objectID) { transaction in
                    InsightsLogRow(transaction: transaction, dateFormat: "d MMM")
                }
                .padding(.horizontal, 6)
            }
            .padding(.bottom, 10)
        }
    }

    var recurringCard: some View {
        let monthly = recurring.reduce(0) { $0 + $1.monthly }

        return InsightsTappableCard {
            onSelect(.recurring)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        InsightsCardTitle("Recurring")

                        Spacer(minLength: 8)

                        Text("\(formatter.rounded(monthly * 12))/year")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        InsightsAmountText(amount: monthly, formatter: formatter, font: .system(.title2, design: .rounded).weight(.semibold))

                        Text("/month")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)

                    ConversionNote(report: InsightsRecurringCharge.report(for: recurring))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

                ForEach(recurring.prefix(3)) { charge in
                    InsightsLogRow(transaction: charge.transaction, subtitle: charge.due)
                }
                .padding(.horizontal, 6)
            }
            .padding(.bottom, 10)
        }
    }

    init(period: InsightsPeriod, dataController: DataController, incomeTracking: Bool, firstDay: Date?, formatter: InsightsFormatter, breaksDownByAccount: Bool = false, onSelectAccount: ((AccountChoice) -> Void)? = nil, onSelect: @escaping (InsightsRoute) -> Void) {
        self.period = period
        self.incomeTracking = incomeTracking
        self.formatter = formatter
        self.onSelect = onSelect
        self.onSelectAccount = onSelectAccount
        let accounts = InsightsAccountFilter.predicate(in: dataController)
        let spentInsights = dataController.getInsights(type: period.type, date: period.start, income: false, accounts: accounts)
        buckets = InsightsBucket.make(dates: spentInsights.dates, values: spentInsights.dateDictionary, type: period.type)
        spent = spentInsights.amount
        spentReport = spentInsights.report
        average = spentInsights.amount / Double(insightsAverageSpan(dataController, period: period, firstDay: firstDay))

        let previous = dataController.getInsights(type: period.type, date: period.shifted(by: -1).start, income: false, accounts: accounts).amount
        change = previous > 0 && spentInsights.amount > 0 ? (spentInsights.amount - previous) / previous : nil

        let expenses = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: false)
        categories = InsightsCategoryTotal.make(from: expenses)
        accountTotals = breaksDownByAccount ? InsightsAccountTotal.make(from: expenses) : []
        largest = Array(insightsLargestFirst(expenses).prefix(3))

        cashFlow = incomeTracking ? InsightsCashFlow.make(dataController, period: period, count: 6, firstDay: firstDay) : nil
        income = cashFlow?.income ?? 0
        net = income - spentInsights.amount

        recurring = period.isCurrent ? InsightsRecurringCharge.make(dataController) : []
        projection = InsightsProjection.make(period: period, expenses: expenses, previous: previous, firstDay: firstDay, recurring: recurring)
    }
}

// MARK: - Building blocks

struct InsightsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct InsightsCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.PrimaryText.opacity(configuration.isPressed ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Rows inside keep their own buttons; tapping anywhere else on the card opens its sheet.
struct InsightsTappableCard<Content: View>: View {
    let action: () -> Void
    let content: Content

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            InsightsCard {
                content
            }
        }
        .buttonStyle(InsightsCardButtonStyle())
    }
}

struct InsightsCategoryTile: View {
    let slice: CategorySlice
    var large = false

    var body: some View {
        EmojiLogView(category: slice.category, income: slice.income, future: false, huge: large)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityHidden(true)
    }
}

enum InsightsSavingsText {
    static func text(income: Double, spent: Double) -> Text {
        guard income > 0 else { return Text("No income this period") }

        let kept = (income - spent) / income
        let percent = Int((abs(kept) * 100).rounded())

        if kept >= 0 {
            return Text("You kept \(Text("\(percent)%").foregroundColor(Color.IncomeGreen).fontWeight(.semibold)) of income")
        } else {
            return Text("You spent \(Text("\(percent)% more").foregroundColor(Color.AlertRed).fontWeight(.semibold)) than you earned")
        }
    }
}

struct InsightsChangeLabel: View {
    let percent: Int
    let comparison: LocalizedStringKey
    var increaseIsGood = false

    var tint: Color {
        (percent > 0) == increaseIsGood ? Color.IncomeGreen : Color.AlertRed
    }

    var body: some View {
        (Text(Image(systemName: percent > 0 ? "arrow.up" : "arrow.down")).fontWeight(.semibold) + Text(" \(abs(percent))%"))
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundColor(tint)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(percent > 0 ? "up \(abs(percent)) percent" : "down \(abs(percent)) percent") + Text(" ") + Text(comparison))
    }
}

struct InsightsCategoryRing: View {
    let categories: [InsightsCategoryTotal]
    let formatter: InsightsFormatter
    let caption: Text
    let onSelect: (CategorySlice) -> Void

    var body: some View {
        let shown = categories.filter { $0.share >= 0.01 }
        let shownTotal = shown.reduce(0) { $0 + $1.share }
        var cursor = 0.0
        let segments: [ArcRingSegment] = shownTotal > 0 ? shown.map { total in
            let start = cursor
            cursor += total.share / shownTotal
            return ArcRingSegment(id: total.id, start: start, end: cursor, colour: total.slice.tokenColour, label: "\(total.slice.name), \(formatter.string(total.amount))")
        } : []

        ArcRing(segments: segments, onSelect: { id in
            if let total = shown.first(where: { $0.id == id }) {
                onSelect(total.slice)
            }
        }) {
            InsightsAmountText(amount: categories.reduce(0) { $0 + $1.amount }, formatter: formatter, font: .system(.title, design: .rounded).weight(.semibold))

            caption
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
        }
    }
}

struct ArcRingSegment: Identifiable {
    let id: String
    /// Where the segment starts and ends, as fractions of the whole arc.
    let start: Double
    let end: Double
    let colour: Color
    let label: String
}

/// A 70% ring open at the bottom: flat-ended segments with hairline gaps and rounded outer ends,
/// filling one after another, with an optional pace triangle on the outer edge.
struct ArcRing<Center: View>: View {
    let segments: [ArcRingSegment]
    var showsTrack = false
    var tick: Double?
    var onSelect: ((String) -> Void)?
    @ViewBuilder let center: Center

    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 220
    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var animated: Bool = true
    @State private var revealed = false

    private let arc: Double = 0.7
    private let gap: CGFloat = 2
    private let lineWidth: CGFloat = 16
    private let sweep: Double = 0.8

    private var rotation: Angle {
        .degrees(90 + (1 - arc) * 180)
    }

    var body: some View {
        let size = min(diameter, 260)
        let circumference = 2 * .pi * Double(size - lineWidth) / 2
        let cap = Double(lineWidth / 2) / circumference
        let halfGap = Double(gap / 2) / circumference
        let ring = Circle().inset(by: lineWidth / 2)
        let filled = segments.last?.end ?? 0

        ZStack {
            ZStack {
                if showsTrack {
                    ring
                        .trim(from: 0, to: arc)
                        .stroke(Color.PrimaryText.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(rotation)
                }

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let joinsNext = index < segments.count - 1 || (showsTrack && filled < 0.999)
                    let from = segment.start * arc + (index == 0 ? 0 : halfGap)
                    let to = max(from + 0.0001, segment.end * arc - (joinsNext ? halfGap : 0))

                    ring
                        .trim(from: from, to: revealed || !animated ? to : from)
                        .stroke(segment.colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(rotation)
                        .animation(animated ? .easeOut(duration: max(0.18, (segment.end - segment.start) * sweep)).delay(segment.start * sweep) : nil, value: revealed)
                        .contentShape(ring.trim(from: from, to: to).rotation(rotation).stroke(style: StrokeStyle(lineWidth: lineWidth + 12)))
                        .onTapGesture {
                            onSelect?(segment.id)
                        }
                        .allowsHitTesting(onSelect != nil)
                        .accessibilityElement()
                        .accessibilityLabel(segment.label)
                        .accessibilityAddTraits(onSelect != nil ? .isButton : [])
                }
            }
            .mask(
                ring
                    .trim(from: cap, to: arc - cap)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(rotation)
            )

            if let tick {
                let angle = rotation.degrees + min(max(tick, 0), 1) * arc * 360
                let radius = size / 2 + 1
                let radians = angle * .pi / 180

                RoundedTriangle(cornerRadius: 1.3)
                    .fill(Color.PrimaryText)
                    .frame(width: 14, height: 6.5)
                    .rotationEffect(.degrees(angle + 90))
                    .offset(x: radius * cos(radians), y: radius * sin(radians))
                    .accessibilityHidden(true)
            }

            VStack(spacing: 4) {
                center
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, lineWidth + 12)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        }
        .frame(width: size, height: size)
        .padding(.bottom, -size * 0.16)
        .frame(maxWidth: .infinity)
        .onAppear {
            revealed = true
        }
    }
}

struct InsightsShareBar: View {
    let categories: [InsightsCategoryTotal]

    private let spacing: CGFloat = 2
    private let height: CGFloat = 14

    var body: some View {
        let shown = categories.filter { $0.share >= 0.01 }
        let shownTotal = shown.reduce(0) { $0 + $1.share }

        GeometryReader { proxy in
            let available = proxy.size.width - spacing * CGFloat(max(0, shown.count - 1))

            HStack(spacing: spacing) {
                ForEach(shown) { total in
                    Rectangle()
                        .fill(total.slice.tokenColour)
                        .frame(width: max(6, available * total.share / max(shownTotal, 0.0001)))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// An account's spending with a bar for its share. Tapping it shows Insights for just that account.
struct InsightsAccountRow: View {
    let total: InsightsAccountTotal
    let formatter: InsightsFormatter
    let action: () -> Void

    var share: Int {
        Int((total.share * 100).rounded())
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(total.account.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(1)

                    Text("\(share)%")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    InsightsAmountText(amount: total.amount, formatter: formatter, font: .system(.body, design: .rounded).weight(.medium))
                        .layoutPriority(1)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.PrimaryText.opacity(0.08))

                        Capsule()
                            .fill(Color.PrimaryText.opacity(0.55))
                            .frame(width: max(6, proxy.size.width * total.share))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total.account.name), \(formatter.string(total.amount)), \(share) percent of spending")
        .accessibilityHint(Text("Shows insights for this account"))
        .accessibilityAddTraits(.isButton)
    }
}

struct InsightsCategoryRow: View {
    let total: InsightsCategoryTotal
    let formatter: InsightsFormatter
    var action: (() -> Void)?

    var share: Int {
        Int((total.share * 100).rounded())
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total.slice.name), \(formatter.string(total.amount)), \(share) percent of spending")
        .accessibilityAddTraits(action != nil ? .isButton : [])
    }

    var content: some View {
        HStack(spacing: 12) {
            InsightsCategoryTile(slice: total.slice)

            VStack(alignment: .leading, spacing: 2) {
                Text(total.slice.name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Text("\(share)% of spending")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            InsightsAmountText(amount: total.amount, formatter: formatter, font: .system(.body, design: .rounded).weight(.medium))
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct InsightsLogRow: View {
    let transaction: Transaction
    let subtitle: String

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showExpenseOrIncomeSign: Bool = true

    var body: some View {
        SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? "$", currency: currency, swapTimeLabel: false, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign, subtitle: subtitle)
    }
}

extension InsightsLogRow {
    init(transaction: Transaction, dateFormat: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = dateFormat
        self.init(transaction: transaction, subtitle: dateFormatter.string(from: transaction.wrappedDate).uppercased())
    }
}

struct InsightsTallyList: View {
    let title: String
    let items: [Transaction]
    let formatter: InsightsFormatter
    var sign = ""
    var dateFormat = "d MMM"
    var emptyTitle: LocalizedStringKey = "No transactions"

    var totalText: String {
        let money = items.total(using: .current())
        return money.report.marking(sign + formatter.string(money.value))
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(systemImage: "tray", title: emptyTitle)
                .fillsScrollViewport()
        } else {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack {
                        Text(title.uppercased())
                            .lineLimit(1)

                        Spacer()

                        Text(totalText)
                            .layoutPriority(1)
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    Line()
                        .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

                ForEach(items, id: \.objectID) { transaction in
                    InsightsLogRow(transaction: transaction, dateFormat: dateFormat)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

struct InsightsBarChart: View {
    let buckets: [InsightsBucket]
    var average: Double = 0
    var colour: Color = .PrimaryText
    let formatter: InsightsFormatter
    var onSelect: ((InsightsBucket) -> Void)?

    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var animated: Bool = true
    @State private var revealed = false
    @ScaledMetric(relativeTo: .footnote) private var averageLabelHeight: CGFloat = 22

    private let height: CGFloat = 150
    private let labelBackground = Color.SettingsBackground

    // Headroom keeps the tallest bar off the top of its track.
    private var maxValue: Double {
        let maximum = max(buckets.map(\.value).max() ?? 0, average)
        return maximum > 0 ? maximum * 1.1 : 1
    }

    private var spacing: CGFloat {
        buckets.count > 20 ? 3 : (buckets.count > 8 ? 6 : 10)
    }

    private var radius: CGFloat {
        buckets.count > 20 ? 3 : (buckets.count > 8 ? 6 : 8)
    }

    // Dim the other bars only while the period is still running, so today stands out.
    private var emphasisesCurrent: Bool {
        buckets.contains(where: \.isCurrent)
    }

    // An average of one or two scattered days is noise, so it needs a quarter of the elapsed buckets.
    private var showsAverage: Bool {
        let withData = buckets.filter { $0.value > 0 }.count
        let elapsed = buckets.filter { !$0.isFuture }.count
        return average > 0 && withData > 1 && Double(withData) >= Double(elapsed) * 0.25
    }

    private var trackOpacity: Double {
        buckets.count > 20 ? 0.055 : 0.07
    }

    private var averageY: CGFloat {
        height - height * average / maxValue
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    bar(bucket, index: index)
                }
            }
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                if showsAverage {
                    averageOverlay
                }
            }

            HStack(spacing: spacing) {
                ForEach(buckets) { bucket in
                    Text(bucket.label)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundColor(bucket.isCurrent ? Color.PrimaryText : Color.SubtitleText)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .onAppear {
            revealed = true
        }
    }

    // The label sits just above the line, or just below it when the line is too close to the top.
    // Its card-coloured capsule masks the bars it crosses.
    var averageOverlay: some View {
        let gap: CGFloat = 3
        let above = averageY - gap - averageLabelHeight
        let labelY = above >= 0 ? above : min(averageY + gap, height - averageLabelHeight)

        return ZStack(alignment: .topTrailing) {
            Line()
                .stroke(Color.SubtitleText, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
                .frame(height: 1)
                .offset(y: averageY)

            (Text("avg ") + Text(formatter.compact(average)).fontWeight(.semibold))
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: averageLabelHeight)
                .background(labelBackground.opacity(0.9), in: Capsule())
                .offset(y: labelY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Average") + Text(" ") + Text(formatter.string(average)))
    }

    func bar(_ bucket: InsightsBucket, index: Int) -> some View {
        let valueHeight = bucket.value > 0 ? max(6, height * bucket.value / maxValue) : 0
        let dimmed = emphasisesCurrent && !bucket.isCurrent

        return Button {
            onSelect?(bucket)
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.PrimaryText.opacity(bucket.isFuture ? trackOpacity / 2 : trackOpacity))

                if valueHeight > 0 {
                    RoundedRectangle(cornerRadius: min(radius, valueHeight / 2), style: .continuous)
                        .fill(colour.opacity(dimmed ? 0.7 : 1))
                        .frame(height: revealed || !animated ? valueHeight : 0)
                        .animation(animated ? .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.02) : nil, value: revealed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil || bucket.value == 0 || bucket.isFuture)
        .accessibilityLabel("\(bucket.accessibilityDate), \(formatter.string(bucket.value))")
    }
}

struct InsightsCashFlowChart: View {
    let points: [InsightsCashFlowPoint]
    let selected: Int?
    let formatter: InsightsFormatter
    var height: CGFloat = 64
    var onSelect: ((Int) -> Void)?

    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var animated: Bool = true
    @State private var revealed = false

    private var maxValue: Double {
        let maximum = points.map { max($0.income, $0.spent) }.max() ?? 0
        return maximum > 0 ? maximum * 1.1 : 1
    }

    private var barWidth: CGFloat {
        points.count > 9 ? 8 : (points.count > 6 ? 10 : 12)
    }

    // Past seven points the labels would collide, so every other one is labelled, always including the latest.
    func showsLabel(_ index: Int) -> Bool {
        points.count <= 7 || (points.count - 1 - index) % 2 == 0
    }

    // With nothing selected the slots inside the period are in focus, and the one containing today is labelled.
    func isEmphasised(_ index: Int) -> Bool {
        selected.map { $0 == index } ?? points[index].isCurrent
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    group(point, index: index)
                }
            }
            .frame(height: height)

            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    Text(showsLabel(index) ? point.label : "")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundColor(isEmphasised(index) ? Color.PrimaryText : Color.SubtitleText)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .onAppear {
            revealed = true
        }
    }

    @ViewBuilder
    func group(_ point: InsightsCashFlowPoint, index: Int) -> some View {
        let bars = ZStack(alignment: .bottom) {
            if point.hasData {
                HStack(alignment: .bottom, spacing: 3) {
                    bar(point.income, colour: Color.IncomeGreen, index: index)
                    bar(point.spent, colour: Color.PrimaryText, index: index)
                }
                .opacity(selected.map { $0 == index } ?? point.inPeriod ? 1 : 0.45)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(point.title) + Text(", ") + Text("Income") + Text(" \(formatter.string(point.income)), ") + Text("Spent") + Text(" \(formatter.string(point.spent))"))

        if let onSelect {
            Button {
                onSelect(index)
            } label: {
                bars
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(index == selected ? .isSelected : [])
        } else {
            bars
        }
    }

    func bar(_ value: Double, colour: Color, index: Int) -> some View {
        let valueHeight = value > 0 ? max(4, height * value / maxValue) : 4

        return RoundedRectangle(cornerRadius: min(4, barWidth / 2), style: .continuous)
            .fill(value > 0 ? colour : colour.opacity(0.3))
            .frame(width: barWidth, height: revealed || !animated ? valueHeight : 0)
            .animation(animated ? .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.03) : nil, value: revealed)
    }
}

// MARK: - Detail sheet

enum InsightsRoute: Identifiable, Hashable {
    case bucket(Date)
    case categoryBucket(CategorySlice, Date)
    case category(CategorySlice)
    case allCategories
    case largest
    case cashFlow
    case recurring

    var id: String {
        switch self {
        case let .bucket(date):
            return "bucket-\(date.timeIntervalSince1970)"
        case let .categoryBucket(slice, date):
            return "categoryBucket-\(slice.id)-\(date.timeIntervalSince1970)"
        case let .category(slice):
            return "category-\(slice.id)"
        case .allCategories:
            return "allCategories"
        case .largest:
            return "largest"
        case .cashFlow:
            return "cashFlow"
        case .recurring:
            return "recurring"
        }
    }
}

struct InsightsDetailSheet: View {
    let period: InsightsPeriod
    let firstDay: Date?
    let formatter: InsightsFormatter

    @State private var path: [InsightsRoute]
    @State private var refreshID = UUID()
    @StateObject private var sheetManager = OverallTransactionManager()

    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss

    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)

    var route: InsightsRoute {
        path.last ?? .allCategories
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
            routeContent
                .id(refreshID)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .tabHeader {
            GlassSheetHeader(title: title, showsBack: path.count > 1) {
                if path.count > 1 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = path.removeLast()
                    }
                } else {
                    dismiss()
                }
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
        .environmentObject(sheetManager)
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
    }

    var title: Text {
        switch route {
        case let .bucket(date), let .categoryBucket(_, date):
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = period.bucketDateFormat
            return Text(dateFormatter.string(from: date))
        case let .category(slice):
            return Text(slice.name)
        case .allCategories:
            return Text("Categories")
        case .largest:
            return Text("Largest Expenses")
        case .cashFlow:
            return Text("Cash flow")
        case .recurring:
            return Text("Recurring")
        }
    }

    @ViewBuilder
    var routeContent: some View {
        switch route {
        case let .bucket(date):
            bucketContent(date)
        case let .categoryBucket(slice, date):
            bucketContent(date, slice: slice)
        case let .category(slice):
            categoryContent(slice)
        case .allCategories:
            allCategoriesContent
        case .largest:
            largestContent
        case .cashFlow:
            InsightsCashFlowDetail(cashFlow: InsightsCashFlow.make(dataController, period: period, count: 12, firstDay: firstDay), formatter: formatter)
        case .recurring:
            recurringContent
        }
    }

    func bucketContent(_ date: Date, slice: CategorySlice? = nil) -> some View {
        let end = period.bucketEnd(for: date)
        let income = slice?.income ?? false
        let items = insightsTransactions(dataController, from: date, to: end, income: income, slice: slice).sorted { $0.wrappedDate > $1.wrappedDate }
        let converter = CurrencyConverter.current()
        let total = items.total(using: converter).value
        let periodItems = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: income, slice: slice)
        let spent = periodItems.total(using: converter).value
        let average = spent / Double(insightsAverageSpan(dataController, period: period, firstDay: firstDay))
        let ratio = average > 0 ? total / average : 0
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = period.bucketDateFormat

        return VStack(spacing: 20) {
            InsightsSheetSummary(amount: total, formatter: formatter, caption: ratio > 0 ? Text(String(format: "%.1f×", ratio)) + Text(" ") + Text(period.type == 3 ? "your monthly average" : "your daily average") : nil)

            InsightsTallyList(title: dateFormatter.string(from: date), items: items, formatter: formatter, dateFormat: period.type == 3 ? "d MMM" : "h:mm a")
        }
    }

    func changeCaption(_ change: Int?, increaseIsGood: Bool) -> Text {
        guard let change else { return Text("") }
        let tint = (change > 0) == increaseIsGood ? Color.IncomeGreen : Color.AlertRed

        return Text(" · ") + (Text(Image(systemName: change > 0 ? "arrow.up" : "arrow.down")).fontWeight(.semibold) + Text(" \(abs(change))%")).foregroundColor(tint)
    }

    func categoryContent(_ slice: CategorySlice) -> some View {
        let items = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: slice.income, slice: slice)
        let converter = CurrencyConverter.current()
        let total = items.total(using: converter).value
        let allTotal = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: slice.income).total(using: converter).value
        let share = allTotal > 0 ? Int((total / allTotal * 100).rounded()) : 0

        let dates = dataController.getInsights(type: period.type, date: period.start, income: slice.income, accounts: InsightsAccountFilter.predicate(in: dataController)).dates
        var values = [Date: Double]()
        for (index, bucketStart) in dates.enumerated() {
            let bucketEnd = index + 1 < dates.count ? dates[index + 1] : period.end
            values[bucketStart] = items.filter { $0.wrappedDate >= bucketStart && $0.wrappedDate < bucketEnd }.total(using: converter).value
        }
        let buckets = InsightsBucket.make(dates: dates, values: values, type: period.type)
        let average = total / Double(insightsAverageSpan(dataController, period: period, firstDay: firstDay))
        let change = insightsCategoryChange(dataController, period: period, slice: slice, amount: total)

        return VStack(spacing: 24) {
            VStack(spacing: 12) {
                InsightsCategoryTile(slice: slice, large: true)

                InsightsSheetSummary(amount: total, formatter: formatter, caption: Text("\(share)%") + Text(" ") + Text(slice.income ? "of income" : "of spending") + changeCaption(change, increaseIsGood: slice.income))
            }

            InsightsBarChart(buckets: buckets, average: average, colour: slice.tokenColour, formatter: formatter) { bucket in
                withAnimation(.easeInOut(duration: 0.2)) {
                    path.append(.categoryBucket(slice, bucket.date))
                }
            }
            .padding(.horizontal, 20)

            InsightsTallyList(title: period.title, items: items.sorted { $0.wrappedDate > $1.wrappedDate }, formatter: formatter, sign: slice.income ? "+" : "")
        }
    }

    @ViewBuilder
    var allCategoriesContent: some View {
        let expenses = insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: false)
        let categories = InsightsCategoryTotal.make(from: expenses)

        if categories.isEmpty {
            EmptyStateView(systemImage: "tray", title: "No transactions")
                .fillsScrollViewport()
        } else {
            VStack(spacing: 20) {
                InsightsCategoryRing(categories: categories, formatter: formatter, caption: Text("\(categories.count) ") + Text(categories.count == 1 ? "category" : "categories")) { slice in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        path.append(.category(slice))
                    }
                }

                ConversionNote(report: expenses.total(using: .current()).report)

                categoryRows(categories)
            }
        }
    }

    func categoryRows(_ categories: [InsightsCategoryTotal]) -> some View {
        VStack(spacing: 0) {
                ForEach(categories) { total in
                    InsightsCategoryRow(total: total, formatter: formatter) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            path.append(.category(total.slice))
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    var largestContent: some View {
        let items = Array(insightsLargestFirst(insightsTransactions(dataController, from: period.start, to: period.queryEnd, income: false)).prefix(25))

        if items.isEmpty {
            EmptyStateView(systemImage: "tray", title: "No transactions")
                .fillsScrollViewport()
        } else {
            VStack(spacing: 0) {
                ForEach(items, id: \.objectID) { transaction in
                    InsightsLogRow(transaction: transaction, dateFormat: "d MMM")
                }
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    var recurringContent: some View {
        let charges = InsightsRecurringCharge.make(dataController)
        let monthly = charges.reduce(0) { $0 + $1.monthly }

        if charges.isEmpty {
            EmptyStateView(systemImage: "repeat", title: "No recurring transactions")
                .fillsScrollViewport()
        } else {
            VStack(spacing: 20) {
                InsightsSheetSummary(amount: monthly, formatter: formatter, caption: Text("/month"))

                ConversionNote(report: InsightsRecurringCharge.report(for: charges))

                VStack(spacing: 0) {
                    ForEach(charges) { charge in
                        InsightsLogRow(transaction: charge.transaction, subtitle: charge.subtitle)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    init(route: InsightsRoute, period: InsightsPeriod, firstDay: Date?, formatter: InsightsFormatter) {
        _path = State(initialValue: [route])
        self.period = period
        self.firstDay = firstDay
        self.formatter = formatter
    }
}

struct InsightsSheetSummary<Detail: View>: View {
    let amount: Double
    let sign: String
    let formatter: InsightsFormatter
    let caption: Text?
    let detail: Detail

    var body: some View {
        VStack(spacing: 4) {
            InsightsAmountText(amount: amount, sign: sign, formatter: formatter, font: .system(.title, design: .rounded).weight(.semibold))

            detail

            if let caption {
                caption
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    init(amount: Double, sign: String = "", formatter: InsightsFormatter, caption: Text?, @ViewBuilder detail: () -> Detail) {
        self.amount = amount
        self.sign = sign
        self.formatter = formatter
        self.caption = caption
        self.detail = detail()
    }
}

extension InsightsSheetSummary where Detail == EmptyView {
    init(amount: Double, sign: String = "", formatter: InsightsFormatter, caption: Text?) {
        self.init(amount: amount, sign: sign, formatter: formatter, caption: caption) {
            EmptyView()
        }
    }
}

// Finer slots open on the whole period's total; tapping a slot focuses it, and tapping it again goes back.
struct InsightsCashFlowDetail: View {
    let cashFlow: InsightsCashFlow
    let formatter: InsightsFormatter

    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var sheetManager: OverallTransactionManager

    @State private var selected: Int?

    var body: some View {
        let point = selected.flatMap { cashFlow.points.indices.contains($0) ? cashFlow.points[$0] : nil }
        let income = point?.income ?? cashFlow.income
        let spent = point?.spent ?? cashFlow.spent
        let net = income - spent
        let start = point?.start ?? cashFlow.period.start
        let end = point?.end ?? cashFlow.period.queryEnd

        VStack(spacing: 24) {
            InsightsSheetSummary(amount: abs(net), sign: net < 0 ? "−" : "+", formatter: formatter, caption: InsightsSavingsText.text(income: income, spent: spent))

            VStack(alignment: .leading, spacing: 16) {
                InsightsCashFlowChart(points: cashFlow.points, selected: selected, formatter: formatter, height: 150) { index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = !cashFlow.usesPeriods && selected == index ? nil : index
                    }
                }

                HStack(spacing: 16) {
                    legendItem("Income", amount: income, colour: Color.IncomeGreen)

                    legendItem("Spent", amount: spent, colour: Color.PrimaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            InsightsTallyList(title: point?.title ?? cashFlow.period.title, items: insightsTransactions(dataController, from: start, to: end, income: true).sorted { $0.wrappedDate > $1.wrappedDate }, formatter: formatter, sign: "+")
                .id(start)
                .padding(.top, 8)
        }
    }

    func legendItem(_ title: LocalizedStringKey, amount: Double, colour: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colour)
                .frame(width: 8, height: 8)

            (Text(title) + Text(" ") + Text(formatter.string(amount)).foregroundColor(Color.PrimaryText))
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    init(cashFlow: InsightsCashFlow, formatter: InsightsFormatter) {
        self.cashFlow = cashFlow
        self.formatter = formatter
        _selected = State(initialValue: cashFlow.usesPeriods && !cashFlow.points.isEmpty ? cashFlow.points.count - 1 : nil)
    }
}

// MARK: - Shared

struct FilteredInsightsView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>
    let type: Int

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "calendar", title: type == 1 ? "No logs this week" : (type == 2 ? "No logs this month" : "No logs this year"))
                .fillsScrollViewport()
        } else {
            ListView(transactions: _transactions)
                .frame(maxHeight: .infinity)
        }
    }

    init(startDate: Date, income: Bool? = nil, type: Int) {
        self.type = type

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)

        let endPredicate: NSPredicate

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        if type == 1 {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else if type == 2 {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .month) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate: NSCompoundPredicate

        if let unwrappedIncome = income {
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedIncome)
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate, TransferPredicate.excluded])

        } else {
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, TransferPredicate.oneLegPerTransfer])
        }

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)
    }
}

struct ChartTimePickerView: View {
    @State var timeframe = ChartTimeFrame.week
    @Binding var showMenu: Bool

    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var chartType = 1

    var body: some View {
        GlassPopoverMenu {
            ForEach(ChartTimeFrame.allCases, id: \.self) { time in
                GlassPopoverRow(LocalizedStringKey(time.rawValue), isSelected: time == timeframe) {
                    if timeframe == time {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            timeframe = time
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }
        }
        .onChange(of: timeframe) { _ in
            if timeframe == .week {
                chartType = 1
            } else if timeframe == .month {
                chartType = 2
            } else if timeframe == .year {
                chartType = 3
            }
        }
        .onAppear {
            if chartType == 1 {
                timeframe = ChartTimeFrame.week
            } else if chartType == 2 {
                timeframe = ChartTimeFrame.month
            } else if chartType == 3 {
                timeframe = ChartTimeFrame.year
            }
        }
    }
}
