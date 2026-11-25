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

    private var orderedBudgets: [Budget] {
        budgets.sorted { lhs, rhs in
            let left = lhs.category?.order ?? Int64.max
            let right = rhs.category?.order ?? Int64.max
            if left == right {
                return (lhs.dateCreated ?? .distantPast) < (rhs.dateCreated ?? .distantPast)
            }
            return left < right
        }
    }

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
                                ForEach(orderedBudgets, id: \.objectID) { budget in
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
            // `-budgetSheet overall|<category name>` opens that budget's sheet, and `-budgetEdit` its edit sheet, for screenshots.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-budgetSheet"), index + 1 < arguments.count {
                let value = arguments[index + 1]
                if value == "overall", let overall = mainBudget.first {
                    detail = .overall(overall)
                } else if let budget = budgets.first(where: { $0.wrappedName == value }) {
                    detail = .category(budget)
                }
            } else if let index = arguments.firstIndex(of: "-budgetEdit"), index + 1 < arguments.count {
                let value = arguments[index + 1]
                if value == "overall", let overall = mainBudget.first {
                    toEditMain = overall
                } else if value == "new" {
                    newBudget = true
                } else if let budget = budgets.first(where: { $0.wrappedName == value }) {
                    toEdit = budget
                }
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

// MARK: - Tab cells

struct BudgetOverallCard: View {
    @ObservedObject var budget: MainBudget
    @FetchRequest private var transactions: FetchedResults<Transaction>
    @FetchRequest private var rolloverTransactions: FetchedResults<Transaction>

    let period: BudgetPeriod
    let rollover: BudgetRollover?
    let formatter = BudgetFormatter.current

    init(budget: MainBudget) {
        self.budget = budget
        period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        rollover = BudgetRollover(budget)
        _transactions = FetchRequest(sortDescriptors: [], predicate: budgetPredicate(from: period.start, to: period.end, category: nil))
        _rolloverTransactions = FetchRequest(sortDescriptors: [], predicate: BudgetRollover.spendingPredicate(rollover, before: period.start, category: nil))
    }

    var body: some View {
        if budget.isGone {
            EmptyView()
        } else {
            let spending = transactions.total(using: .current())
            let carry = rollover?.carryIn(at: period.start, spentSinceAnchor: rolloverTransactions.total(using: .current()).value)
            let snapshot = BudgetSnapshot(amount: budget.amount, spent: spending.value, period: period, carryIn: carry)

            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        InsightsCardTitle("Overall")
                        if rollover != nil {
                            BudgetRolloverIcon()
                        }
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

                    ConversionNote(report: spending.report)
                        .padding(.top, 4)
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
    @FetchRequest private var rolloverTransactions: FetchedResults<Transaction>

    let period: BudgetPeriod
    let rollover: BudgetRollover?
    let formatter = BudgetFormatter.current

    init(budget: Budget) {
        self.budget = budget
        period = BudgetPeriod(type: Int(budget.type), start: budget.wrappedDate)
        rollover = BudgetRollover(budget)
        _transactions = FetchRequest(sortDescriptors: [], predicate: budgetPredicate(from: period.start, to: period.end, category: budget.category))
        _rolloverTransactions = FetchRequest(sortDescriptors: [], predicate: BudgetRollover.spendingPredicate(rollover, before: period.start, category: budget.category))
    }

    var body: some View {
        if budget.isGone {
            EmptyView()
        } else {
            let spending = transactions.total(using: .current())
            let carry = rollover?.carryIn(at: period.start, spentSinceAnchor: rolloverTransactions.total(using: .current()).value)
            let snapshot = BudgetSnapshot(amount: budget.amount, spent: spending.value, period: period, carryIn: carry)

            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(budget.wrappedEmoji)
                            .font(.system(.body, design: .rounded))
                        Text(budget.wrappedName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)
                        if rollover != nil {
                            BudgetRolloverIcon()
                        }

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

                    ConversionNote(report: spending.report)

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

    var rollover: BudgetRollover? {
        switch self {
        case let .overall(budget):
            return BudgetRollover(budget)
        case let .category(budget):
            return BudgetRollover(budget)
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

    /// Whether the period `target` periods back can be shown; a past period counts once the one after it starts after the first transaction.
    func canReach(_ target: Int) -> Bool {
        guard target != offset else { return true }
        guard target >= 0 else { return false }
        guard target > 0 else { return true }
        let first = earliest.first?.day ?? Date.now
        return route.currentPeriod.shifted(by: 1 - target).start > first
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
                    previousLabel: stepLabels.previous,
                    nextLabel: stepLabels.next
                ) { step in
                    canReach(offset - step) ? route.currentPeriod.shifted(by: step - offset).rangeTitle : nil
                } onStep: { step in
                    guard canReach(offset - step) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        offset -= step
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
    @FetchRequest private var rolloverTransactions: FetchedResults<Transaction>
    @SectionedFetchRequest<Date?, Transaction> private var list: SectionedFetchResults<Date?, Transaction>

    let rollover: BudgetRollover?

    init(route: BudgetDetailRoute, period: BudgetPeriod) {
        self.route = route
        self.period = period
        rollover = route.rollover
        _rolloverTransactions = FetchRequest(sortDescriptors: [], predicate: BudgetRollover.spendingPredicate(rollover, before: period.start, category: route.category))
        _periodTransactions = FetchRequest(sortDescriptors: [SortDescriptor(\.date)], predicate: budgetPredicate(from: period.start, to: period.end, category: route.category))
        _list = SectionedFetchRequest(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: budgetPredicate(from: period.start, to: period.end, category: route.category))
    }

    var body: some View {
        let transactions = Array(periodTransactions)
        let spending = transactions.total(using: .current())
        let carry = rollover?.carryIn(at: period.start, spentSinceAnchor: rolloverTransactions.total(using: .current()).value)
        let snapshot = BudgetSnapshot(amount: route.amount, spent: spending.value, period: period, carryIn: carry)

        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                hero(snapshot, transactions: transactions)

                if let summary = rolloverSummary(snapshot) {
                    summary
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }

                ConversionNote(report: spending.report)
            }
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

            // Inside the ring, so it stays in view when the sheet is at half height.
            BudgetRolloverChip(snapshot: snapshot, formatter: formatter)
                .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
    }

    /// How the budget and what rolled in add up to what can be spent this period, under the ring.
    func rolloverSummary(_ snapshot: BudgetSnapshot) -> Text? {
        guard let carry = snapshot.carryIn, abs(carry) >= 0.005 else { return nil }
        let sign = carry < 0 ? "−" : "+"
        let total = (snapshot.amount < 0 ? "−" : "") + formatter.money(snapshot.amount)
        return Text(String(localized: "\(formatter.whole(snapshot.base)) budget \(sign) \(formatter.money(carry)) = \(total)"))
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
            .monospacedDigit()
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
        let converter = CurrencyConverter.current()
        var values = [Date: Double]()
        var index = 0
        for (start, end) in zip(starts, ends) {
            var total = 0.0
            while index < transactions.count && transactions[index].wrappedDate < end {
                total += converter.amountInBreakdown(of: transactions[index].money)
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
