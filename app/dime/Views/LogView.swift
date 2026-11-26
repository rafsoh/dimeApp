//
//  LogView.swift
//  xpenz
//
//  Created by Rafael Soh on 19/5/22.
//

import CoreData
import Foundation
import Popovers
import SwiftUI

struct LogView: View {
    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>

    @EnvironmentObject var dataController: DataController
    @Environment(\.managedObjectContext) var moc

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    var topEdge: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @State var addTransaction = false

    // searching
    @State var searchMode = false
    @State var searchFieldVisible = false
    @State var searchQuery = ""
    @State private var searchResults: FilteredSearchView.Query?
    @FocusState private var searchFocused: Bool

    var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSupplementalRow: Bool {
        filter != .all && filter != .recurring && filter != .upcoming
    }

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    func resetIncomeFilterIfNeeded() {
        if !incomeTracking && filter == .type {
            filter = .all
        }
    }

    @State private var dataVersion = 0

    // top bar
    @State var showMenu = false
    @AppStorage("logTimeFrame", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var logTimeFrame = 2
    let subtitleText = ["today", "this week", "this month", "this year"]

    // show filter menu
    @State var showFilter = false
    @State var filter = FilterType.all

    // filters
    @State var categoryFilter: CategorySlice?
    @State var dateFilter = Date.now
    @State var weekFilter = Date.now
    @State var monthFilter = Date.now
    @State var income = false

    var launchSearch: Bool

    // Held in @State rather than @StateObject so pull updates only redraw the search button.
    @State private var pullToSearch = PullToSearchModel()

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "tray", title: "No logs yet")
                .padding(.top, topEdge)
                .tabBarClearance()
                .background(Color.PrimaryBackground)

        } else {
            ZStack {
                ScrollView(showsIndicators: false) {
                    LogListContent(filter: filter, category: categoryFilter, date: dateFilter, week: weekFilter, month: monthFilter, income: income, showCents: showCents, currencySymbol: currencySymbol, dataVersion: dataVersion)
                        .equatable()
                        .pullToSearch(pullToSearch, onTrigger: startSearch)
                }
                .tabBarClearance()
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .opacity(searchMode ? 0 : 1)
                .allowsHitTesting(!searchMode)
                .accessibilityHidden(searchMode)

                if searchMode {
                    ScrollView(showsIndicators: false) {
                        if let searchResults {
                            FilteredSearchView(query: searchResults)
                                .padding(.horizontal, 20)
                        } else {
                            EmptyStateView(systemImage: "magnifyingglass", title: "Search by note, category, amount or date")
                                .fillsScrollViewport()
                        }
                    }
                    .scrollDismissesKeyboardInteractively()
                    .tabBarClearance()
                    .transition(.opacity)
                    .task(id: trimmedQuery) {
                        guard !trimmedQuery.isEmpty else {
                            searchResults = nil
                            return
                        }
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !Task.isCancelled else { return }
                        searchResults = FilteredSearchView.Query(trimmedQuery)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: searchMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingAboveTabBar {
                ZStack {
                    if hasSupplementalRow {
                        supplementalFilterRow
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .opacity(searchMode ? 0 : 1)
                .allowsHitTesting(!searchMode)
                .accessibilityHidden(searchMode)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasSupplementalRow)
            }
            .tabHeader {
                headerRow
                    .padding(.horizontal, 25)
                    .frame(height: 44, alignment: .top)
                    .padding(.top, topEdge + 20)
                .padding(.bottom, 12)
            }
            .background(Color.PrimaryBackground)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                dataController.applicationWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: moc)) { _ in
                dataVersion &+= 1
            }
            .onChange(of: launchSearch) { _ in
                startSearch()
            }
            .onAppear {
                dataController.updateRecurringTransactionsIfReady()
                resetIncomeFilterIfNeeded()
            }
            .onChange(of: incomeTracking) { _ in
                resetIncomeFilterIfNeeded()
            }
            .onOpenURL { url in
                guard url.host == "search" else {
                    return
                }
                startSearch()
            }
        }
    }

    var headerRow: some View {
        HStack(spacing: 10) {
            searchCapsule

            if !searchMode {
                Spacer(minLength: 0)

                Group {
                    switch filter {
                    case .all:
                        EmptyView()
                    case .category:
                        filterTagView(text: "filter-tag-category")
                    case .day:
                        filterTagView(text: "filter-tag-day")
                    case .week:
                        filterTagView(text: "filter-tag-week")
                    case .month:
                        filterTagView(text: "filter-tag-month")
                    case .recurring:
                        filterTagView(text: "filter-tag-recurring")
                    case .type:
                        filterTagView(text: "filter-tag-type")
                    case .upcoming:
                        filterTagView(text: "filter-tag-upcoming")
                    }
                }
                .transition(.opacity)

                Spacer(minLength: 0)
            }

            GlassIconButton(
                systemName: searchMode ? "xmark" : "line.3.horizontal.decrease",
                accessibilityLabel: searchMode ? "Close search" : "Filter",
                tint: filterButtonActive ? Color.PrimaryText.opacity(0.25) : .glassTint,
                fallback: filterButtonActive ? Color.PrimaryText.opacity(0.2) : .SecondaryBackground
            ) {
                if searchMode {
                    endSearch()
                } else {
                    showFilter = true
                }
            }
            .popover(present: $showFilter, attributes: {
                $0.position = .absolute(
                    originAnchor: .bottomRight,
                    popoverAnchor: .topRight
                )
                $0.rubberBandingMode = .none
                $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                $0.presentation.animation = .easeInOut(duration: 0.2)
                $0.dismissal.animation = .easeInOut(duration: 0.3)
            }) {
                FilterPickerView(filterType: $filter, showMenu: $showFilter)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 5)
    }

    var searchCapsule: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(Color.PrimaryText)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text("Search")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }

                TextField("", text: $searchQuery)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .disableAutocorrection(true)
                    .accessibilityLabel("Search")
            }
            .disabled(!searchMode)
            .opacity(searchFieldVisible ? 1 : 0)

            if searchMode && !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.trailing, searchMode && searchQuery.isEmpty ? 16 : 0)
        .frame(minWidth: 44, maxWidth: searchMode ? .infinity : 44, alignment: .leading)
        .clipShape(Capsule())
        .glassCapsule(interactive: false)
        .overlay {
            if !searchMode {
                Button(action: startSearch) {
                    Color.clear
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }
        }
        .pullToSearchScale(pullToSearch)
    }

    var filterButtonActive: Bool {
        !searchMode && filter != .all
    }

    @ViewBuilder
    var supplementalFilterRow: some View {
        switch filter {
        case .category:
            CategoryStepperView(categoryFilter: $categoryFilter)
        case .day:
            DateStepperView(date: $dateFilter)
        case .week:
            WeekStepperView(showingDate: $weekFilter)
        case .month:
            MonthStepperView(showingDate: $monthFilter)
        case .type:
            GlassSegmentedPicker(selection: $income, options: [(false, "Expense"), (true, "filter-picker-income")])
        case .all, .recurring, .upcoming:
            EmptyView()
        }
    }

    func startSearch() {
        guard !searchMode else {
            searchFocused = true
            return
        }

        showFilter = false

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            searchMode = true
        }
        withAnimation(.easeOut(duration: 0.2).delay(0.12)) {
            searchFieldVisible = true
        }

        // Bringing up the keyboard blocks the main thread (about 300ms on the first
        // launch), so wait for the expansion to settle rather than freeze it midway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard searchMode else { return }
            searchFocused = true
        }
    }

    func endSearch() {
        searchFocused = false

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            searchMode = false
            searchQuery = ""
            searchResults = nil
        }
        withAnimation(.easeOut(duration: 0.2)) {
            searchFieldVisible = false
        }
    }

    func filterTagView(text: LocalizedStringKey) -> some View {
        GlassCapsuleTag(text, trailingAccessibilityLabel: "remove filter") {
            withAnimation(.easeIn(duration: 0.15)) {
                filter = .all
            }
        }
    }
}

struct NumberView: AnimatableModifier {
    var number: Double
    var dynamicTypeSize: DynamicTypeSize
    let netTotal: Bool
    let positive: Bool
    let hasCents: Bool

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 60
        case .small:
            return 61
        case .medium:
            return 62
        case .large:
            return 65
        case .xLarge:
            return 72
        case .xxLarge:
            return 75
        case .xxxLarge:
            return 80
        default:
            return 65
        }
    }
    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    func body(content _: Content) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Group {
                Text(netTotal ? (positive ? "+\(currencySymbol)" : "-\(currencySymbol)") : currencySymbol)
                    .foregroundColor(Color.SubtitleText) +

                Text("\(number, specifier: showCents && hasCents ? "%.2f" : "%.0f")")
                    .foregroundColor(Color.PrimaryText)
            }
            .font(.system(size: fontSize, weight: .regular, design: .rounded))
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)

    }
}

/// The log's insights and transactions. Equatable so search and header state changes
/// in `LogView` don't rebuild the list: `TransactionsList` holds a fetch request that
/// SwiftUI never sees as unchanged, so recreating it redraws every visible row.
struct LogListContent: View, Equatable {
    let filter: FilterType
    let category: CategorySlice?
    let date: Date
    let week: Date
    let month: Date
    let income: Bool
    let showCents: Bool
    let currencySymbol: String
    /// Insights and upcoming rows fetch in their bodies, so bump this on every store
    /// change to rebuild them.
    let dataVersion: Int

    var body: some View {
        VStack {
            if filter == .all {
                LogInsightsView(showCents: showCents, currencySymbol: currencySymbol)
            }

            TransactionsList(filter: filter, category: category, date: date, week: week, month: month, income: income)
                .zIndex(0)
                .padding(.horizontal, 20)
        }
    }
}

struct LogInsightsView: View {
    @EnvironmentObject var dataController: DataController
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let showCents: Bool
    let currencySymbol: String

    @State var showMenu1 = false
    let subtitleText = ["today", "this week", "this month", "this year", "all time"]

    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var timeframe = 2
    @AppStorage("logInsightsType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var insightsType = 1
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    var displayType: Int {
        incomeTracking ? insightsType : 3
    }

    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var lineGraph: Bool = false

    var netTotal: (value: Double, positive: Bool) {
        dataController.getLogViewTotalNet(type: timeframe)
    }

    var range: Int {
        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
        calendar.minimumDaysInFirstWeek = 4

        if timeframe == 3 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents) ?? Date.now
            let numberOfDays = calendar.dateComponents([.day], from: thisMonth, to: Date.now)

            return (numberOfDays.day ?? 0) + 1
        } else if timeframe == 4 {
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents) ?? Date.now

            let numberOfMonths = calendar.dateComponents([.month], from: thisYear, to: Date.now)

            return (numberOfMonths.month ?? 0) + 1
        } else {
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)
            let thisWeek = calendar.date(from: dateComponents) ?? Date.now
            let numberOfDays = calendar.dateComponents([.day], from: thisWeek, to: Date.now)

            return (numberOfDays.day ?? 0) + 1
        }
    }

    var totalSpent: Double {
        return dataController.getLogViewTotalSpent(type: timeframe)
    }

    var totalIncome: Double {
        return dataController.getLogViewTotalIncome(type: timeframe)
    }

    var lineGraphData: [LineGraphDataPoint] {
        if displayType == 1 {
            return dataController.getLineGraphDataNet(type: timeframe)
        } else if displayType == 2 {
            return dataController.getLineGraphData(income: true, type: timeframe)
        } else {
            return dataController.getLineGraphData(income: false, type: timeframe)
        }
    }

    var lineGraphGreen: Bool {
        if displayType == 1 {
            return (lineGraphData.first?.amount ?? 0.0) < (lineGraphData.last?.amount ?? 0.0)
        } else if displayType == 2 {
            return true
        } else {
            return false
        }
    }

    var amount: Double {
        if displayType == 1 {
            return netTotal.value
        } else if displayType == 2 {
            return totalIncome
        } else {
            return totalSpent
        }
    }

    var displayedReport: ConversionReport {
        if displayType == 1 {
            return dataController.logViewNetTotal(type: timeframe).report
        } else if displayType == 2 {
            return dataController.logViewTotal(type: timeframe, income: true).report
        } else {
            return dataController.logViewTotal(type: timeframe, income: false).report
        }
    }

    var headingText: String {
        if displayType == 1 {
            return "Net total"
        } else if displayType == 2 {
            return "Earned"
        } else {
            return "Spent"
        }
    }

    var body: some View {
        VStack(spacing: -3) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(headingText))
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)

                    GlassCapsuleButton(LocalizedStringKey(subtitleText[timeframe - 1]), trailingSystemImage: "chevron.up.chevron.down", font: .system(.title3, design: .rounded).weight(.medium)) {
                        showMenu1 = true
                    }
                    .popover(present: $showMenu1, attributes: {
                        $0.position = .absolute(
                            originAnchor: .bottom,
                            popoverAnchor: .top
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        TimePickerView(showMenu: $showMenu1, timeframe: $timeframe)
                    }
                }

                EmptyView()
                    .modifier(NumberView(number: amount, dynamicTypeSize: _dynamicTypeSize.wrappedValue, netTotal: displayType == 1, positive: netTotal.positive, hasCents: Int((abs(amount) * 100).rounded()) % 100 != 0))

                ConversionNote(report: displayedReport)
            }
            .padding(7)
            .contentShape(Rectangle())
            .contextMenu {
                if incomeTracking {
                    if insightsType != 3 {
                        Button {
                            insightsType = 3
                        } label: {
                            Label("Total Spent", systemImage: "minus")
                        }
                    }

                    if insightsType != 2 {
                        Button {
                            insightsType = 2
                        } label: {
                            Label("Total Income", systemImage: "plus")
                        }
                    }

                    if insightsType != 1 {
                        Button {
                            insightsType = 1
                        } label: {
                            Label("Net Total", systemImage: "alternatingcurrent")
                        }
                    }
                }
            }

            if totalSpent != 0 && totalIncome != 0 && displayType == 1 {
                HStack {
//                    if showCents {
//                        Text("+\(totalIncome, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    } else {
//                        Text("+\(Int(floor(totalIncome)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    }

                    Text("+\(formatNumber(showCents: showCents, number: totalIncome))")
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.IncomeGreen)
                        .lineLimit(1)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundColor(Color.Outline)

                    Text("-\(formatNumber(showCents: showCents, number: totalSpent))")
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.AlertRed)
                        .lineLimit(1)

//                    if showCents {
//                        Text("-\(totalSpent, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    } else {
//                        Text("-\(Int(floor(totalSpent)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    }
                }
                .padding(.bottom, 13)
            }

            if lineGraph {
                LineGraph(data: lineGraphData, green: lineGraphGreen, type: timeframe, range: range)
                    .frame(height: 25)
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
            }
        }
        .padding([.bottom, .horizontal], 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: lineGraph ? 295 : 225)
    }

    func formatNumber(showCents: Bool, number: Double) -> String {
        if showCents {
            return String(format: "%.2f", number)
        } else {
            return String(format: "%d", Int(floor(number)))
        }
    }
}

struct FilteredSearchView: View {
    struct Query {
        let text: String
        let predicate: NSPredicate

        init(_ text: String) {
            self.text = text
            self.predicate = FilteredSearchView.predicate(for: text)
        }
    }

    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var searchQuery: String

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No results for “\(searchQuery)”")
                .fillsScrollViewport()
        } else {
            ListView(transactions: _transactions)
        }
    }

    init(query: Query) {
        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: query.predicate)

        self.searchQuery = query.text
    }

    /// A date narrows the list. Words beside it have to match too, and the
    /// original wording still matches a note or category on its own.
    private static func predicate(for query: String) -> NSPredicate {
        let text = textPredicate(query)
        let parsed = TransactionSearchQuery.parse(query)
        guard let range = parsed.range else { return text }

        let dated = NSPredicate(
            format: "%K >= %@ AND %K < %@",
            #keyPath(Transaction.date), range.start as CVarArg,
            #keyPath(Transaction.date), range.end as CVarArg
        )
        if parsed.remainder.isEmpty {
            return NSCompoundPredicate(orPredicateWithSubpredicates: [dated, text])
        }
        let narrowed = NSCompoundPredicate(andPredicateWithSubpredicates: [dated, textPredicate(parsed.remainder)])
        return NSCompoundPredicate(orPredicateWithSubpredicates: [narrowed, text])
    }

    private static func textPredicate(_ query: String) -> NSPredicate {
        let begins = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), query)
        let contains = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), query)
        let category = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.category.name), query)
        var parts = [begins, contains, category]
        if let amount = TransactionAmountSearch.value(in: query) {
            // Stored amounts are binary doubles, so match to the cent rather than exactly.
            parts.append(NSPredicate(format: "amount >= %@ AND amount < %@", NSNumber(value: amount - 0.005), NSNumber(value: amount + 0.005)))
        }
        if query.count == 3, query.allSatisfy(\.isLetter) {
            parts.append(NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.currencyCode), query))
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: parts)
    }
}

struct TimePickerView: View {
    let timeframes = ["today", "this week", "this month", "this year", "all time"]

    @Binding var showMenu: Bool
    @Binding var timeframe: Int
    @State var holdingTimeframe = 0

    var body: some View {
        GlassPopoverMenu {
            ForEach(timeframes.indices, id: \.self) { index in
                GlassPopoverRow(LocalizedStringKey(timeframes[index]), isSelected: holdingTimeframe == index + 1) {
                    if holdingTimeframe == index + 1 {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            holdingTimeframe = index + 1
                        }

                        timeframe = index + 1

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }
        }
        .onAppear {
            holdingTimeframe = timeframe
        }
    }
}

struct FilterPickerView: View {
    @Binding var filterType: FilterType
    @Binding var showMenu: Bool

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    var filters: [FilterType] {
        incomeTracking ? FilterType.allCases : FilterType.allCases.filter { $0 != .type }
    }

    var body: some View {
        GlassPopoverMenu {
            ForEach(filters, id: \.self) { filter in
                GlassPopoverRow(LocalizedStringKey(filter.rawValue), systemImage: FilterType.imageDictionary[filter], isSelected: filterType == filter) {
                    if filterType == filter {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            filterType = filter
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showMenu = false
                        }
                    }
                }
            }
        }
    }
}

struct TransactionsList: View {
    var filter: FilterType
    var category: CategorySlice?
    var date: Date
    var week: Date
    var month: Date
    var income: Bool

    @AppStorage("showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showUpcoming: Bool = true
    @AppStorage("showUpcomingTransactionsWhenUpcoming", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showSoon: Bool = false

    @EnvironmentObject var dataController: DataController

    @SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
        SortDescriptor(\.day, order: .reverse),
        SortDescriptor(\.date, order: .reverse),
        SortDescriptor(\.note)
    ], predicate: NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactions: SectionedFetchResults<Date?, Transaction>

    var body: some View {
        VStack {
            if (filter == .all && showUpcoming) || filter == .upcoming {
                FutureListView(dataController: dataController, filterMode: filter == .upcoming, limitedMode: showSoon)
                    .padding(.top, 10)
            }

            switch filter {
            case .all:
                ListView(transactions: _transactions)
            case .category:
                FilteredCategoryView(category: category)
            case .day:
                FilteredDateView(date: date)
            case .week:
                FilteredInsightsView(startDate: week, type: 1)
            case .month:
                FilteredInsightsView(startDate: month, type: 2)
            case .recurring:
                FilteredRecurringView()
            case .type:
                FilteredTypeView(income: income)
            case .upcoming:
                EmptyView()
            }
        }
    }
}

struct ListView: View {
    @SectionedFetchRequest<Date?, Transaction> var transactions: SectionedFetchResults<Date?, Transaction>

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var swapTimeLabel: Bool = false

    @EnvironmentObject var toastPresenter: OverallToastPresenter

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(transactions) { day in
                let filtered = filterOutDupes(day: day)
                let dateText = dateConverter(date: day.id ?? Date.now).uppercased()

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(dateText)
                            Spacer()

                            Text(filtered.string)
                                .layoutPriority(1)
                        }
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(currencySymbol)\(String(format: "%.2f", filtered.string)) was spent \(dateConverterAccessibilityLabel(date: day.id ?? Date.now))")

                        Line()
                            .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    ForEach(filtered.transactions, id: \.id) { transaction in
                        SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if #available(iOS 16.0, *) {
                        Button {
                            guard let image = ImageRenderer(content: SingleDayPhotoView(amountText: filtered.string, dateText: dateText, transactions: filtered.transactions, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false)).uiImage else {
                                return
                            }

                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

                            self.toastPresenter.showToast.toggle()
                        } label: {
                            Label("Save as Photo", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }

    func filterOutDupes(day: SectionedFetchResults<Date?, Transaction>.Element) -> (transactions: [Transaction], string: String) {
        var seen = [Transaction]()
        let filtered = day.filter { entity -> Bool in
            if seen.contains(where: { $0.id == entity.id }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        let dayMoney = filtered.total(using: .current(), signed: true)
        let total = dayMoney.value

        let text: String

        if total >= 0 {
            text = "+" + (numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        } else {
            text = (numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        }

        return (filtered, dayMoney.report.marking(text))
    }
}

struct FutureListView: View {
    @EnvironmentObject var dataController: DataController

    @FetchRequest private var fetchedResults: FetchedResults<Transaction>
    var filterMode: Bool
    var limitedMode: Bool

    var transactions: [Transaction] {
        if limitedMode {
            let calendar = Calendar.current

            let startOfToday = calendar.startOfDay(for: Date.now)
            let twoWeeksFromStartOfToday = calendar.date(byAdding: .weekOfYear, value: 2, to: startOfToday)!

            let holding = fetchedResults.filter {
                let date = $0.wrappedDate > Date.now ? $0.wrappedDate : $0.nextTransactionDate

                return date < twoWeeksFromStartOfToday
            }

            return holding.sorted { itemA, itemB in
                let date1 = itemA.wrappedDate > Date.now ? itemA.wrappedDate : itemA.nextTransactionDate
                let date2 = itemB.wrappedDate > Date.now ? itemB.wrappedDate : itemB.nextTransactionDate

                return date1 > date2
            }

        } else {
            return fetchedResults.sorted { itemA, itemB in
                let date1 = itemA.wrappedDate > Date.now ? itemA.wrappedDate : itemA.nextTransactionDate
                let date2 = itemB.wrappedDate > Date.now ? itemB.wrappedDate : itemB.nextTransactionDate

                return date1 > date2
            }
        }
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var swapTimeLabel: Bool = false

    var totalString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        let money = transactions.total(using: .current(), signed: true)
        let total = money.value

        if total >= 0 {
            return money.report.marking("+" + (numberFormatter.string(from: NSNumber(value: total)) ?? "$0"))
        } else {
            return money.report.marking(numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        }
    }

    var body: some View {
        if !transactions.isEmpty {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack {
                        Text("UPCOMING")
                        Spacer()

                        Text(totalString)
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .accessibilityElement(children: .ignore)

                    Line()
                        .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                .padding(.horizontal, 10)

                ForEach(transactions) { transaction in
                    SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: true, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                }
            }
            .padding(.bottom, 18)
        } else if filterMode {
            EmptyStateView(systemImage: "calendar.badge.clock", title: "No upcoming logs")
                .fillsScrollViewport()
        } else {
            EmptyView()
        }
    }

    init(dataController _: DataController, filterMode: Bool, limitedMode: Bool) {
        let recurringPredicate = NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0)
        let futurePredicate = NSPredicate(format: "%K > %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .or, subpredicates: [recurringPredicate, futurePredicate])

        _fetchedResults = FetchRequest<Transaction>(sortDescriptors: [], predicate: andPredicate)

        self.filterMode = filterMode
        self.limitedMode = limitedMode
    }
}

struct SingleTransactionView: View {
    let transaction: Transaction
    let showCents: Bool
    let currencySymbol: String
    let currency: String
    let swapTimeLabel: Bool
    let future: Bool
    let showExpenseOrIncomeSign: Bool
    var subtitle: String? = nil

    @State var refreshID = UUID()

    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var transactionManager: OverallTransactionManager

    // delete mode
//    @State private var toDelete: Transaction?
//    @State var deleteMode = false
//
//    // edit mode
//    @State private var toEdit: Transaction?

    @State private var offset: CGFloat = 0
    @State private var deleted: Bool = false
    var deletePopup: Bool {
        return abs(offset) > UIScreen.main.bounds.width * 0.2
    }

    var deleteConfirm: Bool {
        return abs(offset) > UIScreen.main.bounds.width * 0.42
    }

    @GestureState var isDragging = false
    @State private var swipeAxis: Axis?
    @State private var isPressed = false
    @State private var rowHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat?

    private let deleteButtonReveal: CGFloat = 66

    var revealProgress: CGFloat {
        min(1, abs(offset) / (UIScreen.main.bounds.width * 0.2))
    }

    var deleteButtonScale: CGFloat {
        deleteConfirm ? 1.08 : 0.6 + 0.4 * revealProgress
    }

    var transactionAmountString: String {
        if let code = transaction.currencyCode, code.uppercased() != currency.uppercased() {
            return MoneyFormatter.string(transaction.amount, currencyCode: code, showCents: showCents)
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: transaction.amount)) ?? "$0"
    }

    var accessibilityAmount: String {
        guard let converted = transaction.convertedAmountText(showCents: showCents) else {
            return "\(currencySymbol)\(String(format: "%.2f", transaction.wrappedAmount))"
        }

        return "\(transactionAmountString), \(converted)"
    }

    @ViewBuilder
    func amountWithConversion(_ amount: Text) -> some View {
        if let converted = transaction.convertedAmountText(showCents: showCents) {
            VStack(alignment: .trailing, spacing: 0) {
                amount

                Text(converted)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        } else {
            amount
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: deleteConfirm ? "trash.fill" : "trash")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundColor(deleteConfirm ? Color.AlertRed : Color.PrimaryText)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), tint: deleteConfirm ? Color.AlertRed.opacity(0.35) : .glassTint, interactive: false, fallback: deleteConfirm ? Color.AlertRed.opacity(0.23) : Color.SecondaryBackground)
                .scaleEffect(deleteButtonScale)
                .opacity(deleted ? 0 : revealProgress)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: deleteConfirm)
                .padding(.trailing, 10)
                .offset(x: max(0, deleteButtonReveal + offset))
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                EmojiLogView(transaction: transaction, future: future)
                    .fixedSize(horizontal: true, vertical: true)
                    .overlay(alignment: .bottomTrailing) {
                        if transaction.recurringType > 0 {
                            Image(systemName: "repeat")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.IncomeGreen)
                                .frame(width: 20, height: 20)
                                .glassBackground(in: Circle(), tint: Color.IncomeGreen.opacity(0.25), interactive: false, fallback: Color.IncomeGreen.opacity(0.2))
                                .offset(x: 5, y: 5)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.displayTitle)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(future ? Color.SubtitleText : Color.PrimaryText)
                        .lineLimit(1)

                    Text(getSubtitle())
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundColor(future ? Color.EvenLighterText : Color.SubtitleText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if transaction.income {
                    amountWithConversion(Text(showExpenseOrIncomeSign ? "+\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(future ? Color.SubtitleText : Color.IncomeGreen))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)

                } else {
                    amountWithConversion(Text(showExpenseOrIncomeSign ? "-\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(future ? Color.SubtitleText : Color.PrimaryText))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .id(refreshID)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.SettingsBackground)
                    .opacity(isPressed ? 1 : 0)
            }
            .scaleEffect(isPressed ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                transactionManager.toEdit = transaction
            }
            .onLongPressGesture(minimumDuration: 60, maximumDistance: 8, pressing: { pressing in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = pressing && offset == 0 && !isDragging
                }
            }, perform: {})
            .contextMenu {
                if transaction.recurringType > 0 {
                    Button {
                        transaction.recurringType = 0
                        dataController.save()
                    } label: {
                        Label("Stop Recurring", systemImage: "xmark")
                    }
                }

                Button {
                    transactionManager.toEdit = transaction
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                if !(future && transaction.wrappedDate < Date.now && transaction.recurringType > 0) {
                    Button {
                        transactionManager.toDelete = transaction
                        transactionManager.future = future
                        transactionManager.showPopup = true

//                        toDelete = transaction
//                        deleteMode = true
                    } label: {
                        Label("Delete", systemImage: "xmark.bin")
                    }
                }
            }
            .offset(x: offset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(transaction.displayTitle), \(accessibilityAmount), Transaction Category: \(transaction.wrappedCategoryName), Transaction made at \(timeConverterAccessibilityLabel(date: transaction.wrappedDate))")
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { rowHeight = $0 }
            }
        }
        .frame(height: collapsedHeight, alignment: .top)
        .clipShape(Rectangle().inset(by: collapsedHeight == nil ? -UIScreen.main.bounds.width : 0))
        .onChange(of: deletePopup) { _ in
            if deletePopup {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .onChange(of: deleteConfirm) { _ in
            if deleteConfirm {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .animation(.easeInOut, value: deletePopup)
        .modifier(RowSwipeModifier(legacy: legacySwipe, onChanged: { width in
            withAnimation {
                offset = min(0, width)
            }
        }, onEnded: finishSwipe))
        .onChange(of: isDragging) { _ in
            if !isDragging && !deleted {
                swipeAxis = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    offset = 0
                }
            }
        }
        .onChange(of: transactionManager.toDelete) { newValue in
            if newValue == nil {
                deleted = false
                offset = 0
                collapsedHeight = nil
//                withAnimation(.easeInOut(duration: 0.3)){
//                   offset = 0
//                }
            }
        }
    }

    var legacySwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($isDragging, body: { _, state, _ in
                state = true
            })
            .onChanged { value in
                let width = value.translation.width
                let height = value.translation.height

                if swipeAxis == nil {
                    swipeAxis = width < 0 && abs(width) > abs(height) * 1.6 ? .horizontal : .vertical
                }

                if swipeAxis == .horizontal {
                    withAnimation {
                        offset = min(0, width)
                    }
                }
            }
            .onEnded { _ in
                let wasHorizontal = swipeAxis == .horizontal
                swipeAxis = nil
                if wasHorizontal {
                    finishSwipe()
                }
            }
    }

    func finishSwipe() {
        if deleteConfirm {
            deleted = true
            withAnimation(.easeInOut(duration: 0.3)) {
                offset -= UIScreen.main.bounds.width
            }

            if future, transaction.wrappedDate < Date.now, transaction.recurringType > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        transaction.recurringType = 0
                        dataController.save()
                    }
                }
            } else {
                collapsedHeight = rowHeight

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        collapsedHeight = 0
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        dataController.deleteTransaction(transaction)
                    }
                }
            }
        } else if deletePopup {
            withAnimation(.easeInOut(duration: 0.3)) {
                offset = 0
            }

            transactionManager.future = future
            transactionManager.toDelete = transaction
            transactionManager.showPopup = true
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                offset = 0
            }
        }
    }

    func getSubtitle() -> String {
        if let subtitle {
            return subtitle
        }

        if future {
            if transaction.wrappedDate > Date.now {
                return dateFormatter(date: transaction.wrappedDate)
            } else {
                return dateFormatter(date: transaction.nextTransactionDate)
            }
        } else {
            if swapTimeLabel {
                return transaction.wrappedCategoryName
            } else {
                let formatter = DateFormatter()
                formatter.setLocalizedDateFormatFromTemplate("jmm")

                return formatter.string(from: transaction.wrappedDate)
            }
        }
    }
}

func dateFormatter(date: Date) -> String {
    let dateFormatter = DateFormatter()

    dateFormatter.dateFormat = "d MMM"
    return dateFormatter.string(from: date).uppercased()
}

struct EmojiLogView: View {
    let emoji: String
    let colour: String
    let future: Bool
    let huge: Bool
    /// An SF Symbol shown in place of the emoji, for transactions without a category.
    var symbol: String?

    var body: some View {
        ZStack {
            if future {
                RoundedRectangle(cornerRadius: huge ? 18 : 12, style: .continuous)
                    .strokeBorder(Color(hex: colour).opacity(0.73), lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: huge ? 18 : 12, style: .continuous)
                    .fill(Color(hex: colour).opacity(0.25))
            }

            if let symbol {
                // A hidden emoji keeps the tile the same size as a categorised one.
                Text("😄")
                    .font(.system(huge ? .title : .title3))
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(8)
                    .hidden()
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(huge ? .title2 : .body, design: .rounded).weight(.bold))
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .foregroundColor(Color(hex: colour))
                    }
            } else {
                Text(emoji)
                    .font(.system(huge ? .title : .title3))
                    // future ? .caption :
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(8)
            }
//                .font(.system(size: huge ? 45 : future ? 16: 20))
        }
        .opacity(future ? 0.6 : 1)
    }

    init(emoji: String, colour: String, future: Bool, huge: Bool = false) {
        self.emoji = emoji
        self.colour = colour
        self.future = future
        self.huge = huge
    }

    /// The transaction's category, or a grey arrow when it has none.
    init(transaction: Transaction, future: Bool, huge: Bool = false) {
        self.init(category: transaction.category, income: transaction.income, future: future, huge: huge)
    }

    init(category: Category?, income: Bool, future: Bool, huge: Bool = false) {
        if let category {
            self.init(emoji: category.wrappedEmoji, colour: category.wrappedColour, future: future, huge: huge)
        } else {
            self.init(emoji: "", colour: Uncategorised.colour, future: future, huge: huge)
            symbol = Uncategorised.symbol(income: income)
        }
    }
}

struct DeleteTransactionAlert: View {
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var transactionManager: OverallTransactionManager

    var stopRecurring: Bool {
        if let unwrapped = transactionManager.toDelete {
            return transactionManager.future && unwrapped.wrappedDate < Date.now && unwrapped.recurringType > 0
        } else {
            return false
        }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .sheet(isPresented: $transactionManager.showPopup) {
                if let unwrappedToDelete = transactionManager.toDelete, unwrappedToDelete.managedObjectContext != nil {
                    ConfirmationSheet(
                        title: stopRecurring ? "Stop Recurring?" : "Delete '\(unwrappedToDelete.displayTitle)'?",
                        message: stopRecurring ? "The transaction will no longer be automatically logged." : "This action cannot be undone."
                    ) {
                        ConfirmationDestructiveButton(stopRecurring ? "Confirm" : "Delete") {
                            transactionManager.showPopup = false

                            if stopRecurring {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    unwrappedToDelete.recurringType = 0
                                    dataController.save()
                                }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        dataController.deleteTransaction(unwrappedToDelete)
                                    }
                                    transactionManager.toDelete = nil
                                }
                            }
                        }

                        ConfirmationCancelButton {
                            transactionManager.showPopup = false
                        }
                    }
                }
            }
    }
}

struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}

struct FilteredRecurringView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "arrow.triangle.2.circlepath", title: "No recurring logs")
                .fillsScrollViewport()
        } else {
            ListView(transactions: _transactions)
        }
    }

    init() {
        let recurringPredicate = NSPredicate(format: "%K = %d", #keyPath(Transaction.onceRecurring), true)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [recurringPredicate, datePredicate])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse),
            SortDescriptor(\.note, order: .reverse)
        ], predicate: andPredicate)
    }
}

struct FilteredTypeView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var income: Bool

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "tray", title: income ? "No income logs" : "No expense logs")
                .fillsScrollViewport()
        } else {
            ListView(transactions: _transactions)
        }
    }

    init(income: Bool) {
        let incomePredicate = NSPredicate(format: "income = %d", income)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [incomePredicate, datePredicate])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.income = income
    }
}

struct FilteredCategoryView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var category: CategorySlice?

    var body: some View {
        if transactions.isEmpty || category == nil {
            EmptyStateView(systemImage: "square.grid.2x2", title: "No logs in this category")
                .fillsScrollViewport()
        } else {
            ListView(transactions: _transactions)
        }
    }

    init(category: CategorySlice?) {
        if let category {
            let categoryPredicate = category.predicate
            let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [categoryPredicate, datePredicate])

            _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
                SortDescriptor(\.day, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ], predicate: andPredicate)
        } else {
            _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
                SortDescriptor(\.day, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ])
        }

        self.category = category
    }
}

struct FilteredDateView: View {
    @FetchRequest private var transactions: FetchedResults<Transaction>

    var date: Date

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var swapTimeLabel: Bool = false

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var showExpenseOrIncomeSign: Bool = true

    var body: some View {
        if transactions.isEmpty {
            EmptyStateView(systemImage: "calendar", title: "No logs on this day")
                .fillsScrollViewport()
        } else {
            VStack(spacing: 0) {
                ForEach(transactions) { transaction in
                    SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                }
            }
        }
    }

    init(date: Date) {
        let datePredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.day), date as CVarArg)
        let futurePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [futurePredicate, datePredicate])

        _transactions = FetchRequest<Transaction>(sortDescriptors: [
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.date = date
    }
}

struct CategoryStepperView: View {
    @Binding var categoryFilter: CategorySlice?
    @EnvironmentObject var dataController: DataController
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true
    @State var income = false
    @State var showPicker = false

    var incomeSelection: Binding<Bool> {
        Binding {
            income
        } set: { newValue in
            guard newValue != income else { return }

            income = newValue
            categoryFilter = firstSlice(income: newValue)
        }
    }

    /// The first category of a type, or No Category when there are none.
    func firstSlice(income: Bool) -> CategorySlice {
        let holding = dataController.results(for: dataController.fetchRequestForCategories(income: income))
        return holding.first.map { .categorised($0) } ?? .uncategorised(income: income)
    }

    /// The picker works in categories; picking No Category there filters to transactions without one.
    var pickerSelection: Binding<Category?> {
        Binding {
            categoryFilter?.category
        } set: { newValue in
            categoryFilter = newValue.map { .categorised($0) } ?? .uncategorised(income: income)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if incomeTracking {
                GlassSegmentedPicker(selection: incomeSelection, options: [(false, "Expense"), (true, "filter-picker-income")])
            }

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    if let categoryFilter {
                        if let category = categoryFilter.category {
                            Text(category.wrappedEmoji)
                        } else {
                            Image(systemName: Uncategorised.symbol(income: income))
                                .foregroundColor(Color(hex: Uncategorised.colour))
                        }
                        Text(categoryFilter.name)
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)
                    } else {
                        Text("Category")
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Color.SubtitleText)
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(in: Capsule(), tint: capsuleColour.opacity(0.25), fallback: capsuleColour.opacity(0.23))
            .disabled(categoryFilter == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Category filter") + Text(", ") + Text(categoryFilter?.name ?? ""))
            .accessibilityAddTraits(.isButton)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(isPresented: $showPicker) {
            CategoryPickerSheet(category: pickerSelection, income: income, allowsEditing: false, allowsNone: true)
        }
        .onAppear {
            categoryFilter = firstSlice(income: income)
        }
    }

    var capsuleColour: Color {
        categoryFilter?.tokenColour ?? Color.SubtitleText
    }

    init(categoryFilter: Binding<CategorySlice?>?) {
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
    }
}

struct DateStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @Binding var date: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            return transactions[0].day ?? Date.now
        }
    }

    let currentDate = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date.now) ?? Date.now

    func dateString(_ date: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM yyyy"

        return dateFormatter.string(from: date)
    }

    func shifted(by days: Int) -> Date? {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) else { return nil }
        guard days == 0 || (shifted >= endDate && shifted <= currentDate) else { return nil }
        return shifted
    }

    var body: some View {
        GlassStepperCapsule(
            accessibilityTitle: "showing transactions on \(dateString(date))",
            previousLabel: "Previous day",
            nextLabel: "Next day"
        ) { offset in
            shifted(by: offset).map(dateString)
        } onStep: { offset in
            if let shifted = shifted(by: offset) {
                date = shifted
            }
        }
        .onAppear {
            date = currentDate
        }
    }
}

struct WeekStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day, order: .reverse)
    ], predicate: NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactionsReversed: FetchedResults<Transaction>

    @Binding var showingDate: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
            calendar.minimumDaysInFirstWeek = 4

            let date = transactions[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)

            return calendar.date(from: dateComponents) ?? Date.now
        }
    }

    @State var startDate = Date.now

    func dateString(_ weekStart: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = Calendar.current.date(byAdding: endComponents, to: weekStart) ?? Date.now

        return dateFormatter.string(from: weekStart) + " - " + dateFormatter.string(from: endWeekDate)
    }

    func shifted(by weeks: Int) -> Date? {
        guard let shifted = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: showingDate) else { return nil }
        guard weeks == 0 || (shifted >= endDate && shifted <= startDate) else { return nil }
        return shifted
    }

    var accessibilityDateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = Calendar.current.date(byAdding: endComponents, to: showingDate) ?? Date.now

        return "showing transactions from " + dateFormatter.string(from: showingDate) + " to " + dateFormatter.string(from: endWeekDate)
    }

    var body: some View {
        GlassStepperCapsule(
            accessibilityTitle: accessibilityDateString,
            previousLabel: "Previous week",
            nextLabel: "Next week"
        ) { offset in
            shifted(by: offset).map(dateString)
        } onStep: { offset in
            if let shifted = shifted(by: offset) {
                showingDate = shifted
            }
        }
        .onAppear {
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
            calendar.minimumDaysInFirstWeek = 4

            let date = transactionsReversed[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)

            startDate = calendar.date(from: dateComponents) ?? Date.now

            showingDate = startDate
        }
    }
}

struct MonthStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day, order: .reverse)
    ], predicate: NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactionsReversed: FetchedResults<Transaction>

    @Binding var showingDate: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            let calendar = Calendar(identifier: .gregorian)

            let date = transactions[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.month, .year], from: date)

            return calendar.date(from: dateComponents) ?? Date.now
        }
    }

    @State var startDate = Date.now

    func dateString(_ month: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "MMM yyyy"

        return dateFormatter.string(from: month)
    }

    func shifted(by months: Int) -> Date? {
        guard let shifted = Calendar.current.date(byAdding: .month, value: months, to: showingDate) else { return nil }
        guard months == 0 || (shifted >= endDate && shifted <= startDate) else { return nil }
        return shifted
    }

    var body: some View {
        GlassStepperCapsule(
            accessibilityTitle: "showing transactions in \(dateString(showingDate))",
            previousLabel: "Previous month",
            nextLabel: "Next month"
        ) { offset in
            shifted(by: offset).map(dateString)
        } onStep: { offset in
            if let shifted = shifted(by: offset) {
                showingDate = shifted
            }
        }
        .onAppear {
            let calendar = Calendar(identifier: .gregorian)

            let date = transactionsReversed[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.month, .year], from: date)

            startDate = calendar.date(from: dateComponents) ?? Date.now

            showingDate = startDate
        }
    }
}

func dateConverter(date: Date) -> String {
    let calendar = Calendar.current

    let dateComponents = calendar.dateComponents([.year], from: Date.now)

    let startOfCurrentYear = calendar.date(from: dateComponents) ?? Date.now

    if calendar.isDateInToday(date) {
        return String(localized: "today")
    } else if calendar.isDateInYesterday(date) {
        return String(localized: "yesterday")
    } else if startOfCurrentYear > date {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM yy"

        var string = dateFormatter.string(from: date)
        string.insert("'", at: string.index(string.endIndex, offsetBy: -2))

        return string
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM"

        return dateFormatter.string(from: date)
    }
}

func dateConverterAccessibilityLabel(date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
        return "today"
    } else if calendar.isDateInYesterday(date) {
        return "yesterday"
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM yyyy"

        return "on " + dateFormatter.string(from: date)
    }
}

func timeConverterAccessibilityLabel(date: Date) -> String {
    let dateFormatter = DateFormatter()

    dateFormatter.setLocalizedDateFormatFromTemplate("jmm")

    return dateFormatter.string(from: date)
}

func dayTotal(dayTransaction: [Transaction]) -> Double {
    dayTransaction.total(using: .current(), signed: true).value
}

/// Swipe-to-delete on a row. On iOS 18+ a UIKit pan that only begins on a clear leftward swipe,
/// so vertical drags go untouched to the scroll view and the sheet.
private struct RowSwipeModifier<Legacy: Gesture>: ViewModifier {
    let legacy: Legacy
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(LeftSwipeGesture(onChanged: onChanged, onEnded: onEnded))
        } else {
            content.simultaneousGesture(legacy)
        }
    }
}

@available(iOS 18.0, *)
private struct LeftSwipeGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.6
        }
    }
}
