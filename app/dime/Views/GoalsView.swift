//
//  GoalsView.swift
//  dime
//
//  The Goals and Debts pages of the Budget tab, laid out like budgets: a card with the total, tiles, and a sheet
//  for each. Goals and debts are accounts (see Goals.swift); money goes in and comes out with transfers.
//

import CoreData
import Popovers
import SwiftUI

#if DEBUG
/// Launch arguments for screenshots of goals and debts. Remove before merging, with the other screenshot arguments.
/// `-planSection goals|debts` opens that page of the Budget tab; `-planDetail <name>` its sheet;
/// `-detailAction add|takeOut|pay|charge|everyday` a button or menu item on that sheet; `-planEditor new|<name>`
/// the editor, with `-editorFill` to fill in a new one and `-editorField amount|saved|deadline|rate|payment|reminder|timing`
/// to open one of its parts; `-planConvert <name>` the sheet that makes an everyday account a goal or debt.
enum PlanScreenshot {
    static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func account(named name: String?) -> Account? {
        guard let name else { return nil }
        return DataController.shared.accounts().first { $0.wrappedName == name }
    }
}
#endif

// MARK: - Sections

/// What the Budget tab shows.
enum PlanSection: String, CaseIterable {
    case budgets, goals, debts
}

/// The Budget tab's header: the three pages, and New for the one showing.
struct PlanHeader: View {
    @Binding var section: PlanSection
    let onNew: () -> Void
    /// An everyday account to make a goal or debt.
    let onConvert: (AccountConversion) -> Void

    /// Everyday accounts, which New offers to make goals or debts.
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)], predicate: AccountKind.everyday.predicate) private var accounts: FetchedResults<Account>

    var body: some View {
        HStack(spacing: 12) {
            GlassSegmentedPicker(selection: $section, options: [
                (value: PlanSection.budgets, title: "Budgets"),
                (value: PlanSection.goals, title: "Goals"),
                (value: PlanSection.debts, title: "Debts")
            ], segmentPadding: 12)

            Spacer(minLength: 0)

            if section == .budgets || accounts.isEmpty {
                GlassIconButton(systemName: "plus", accessibilityLabel: newLabel, action: onNew)
            } else {
                newMenu
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// New, or an account the user already has, made a goal or debt.
    var newMenu: some View {
        let kind: AccountKind = section == .goals ? .goal : .debt

        return Menu {
            Button(action: onNew) {
                Label(newLabel, systemImage: "plus")
            }

            Section {
                ForEach(accounts, id: \.objectID) { account in
                    Button {
                        onConvert(AccountConversion(account: account, kind: kind))
                    } label: {
                        Label(account.wrappedName, systemImage: AccountIcons.displayable(account.wrappedSymbol))
                    }
                }
            } header: {
                kind == .goal ? Text("Make an Account a Goal") : Text("Make an Account a Debt")
            }
        } label: {
            Image(systemName: "plus")
                .font(.app(.body, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.PrimaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .glassBackground(in: Circle(), tint: .glassTint)
        .accessibilityLabel(newLabel)
    }

    var newLabel: LocalizedStringKey {
        switch section {
        case .budgets:
            return "New Budget"
        case .goals:
            return "New Goal"
        case .debts:
            return "New Debt"
        }
    }
}

// MARK: - Lists

/// Every goal or every debt: a card with the total, then a tile for each, then those put away.
struct SavingsList: View {
    let kind: AccountKind

    @ObservedObject var dataController = DataController.shared
    @EnvironmentObject var toastPresenter: OverallToastPresenter
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @AppStorage("budgetViewStyle", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var budgetRows: Bool = false

    @FetchRequest private var accounts: FetchedResults<Account>

    @State private var detail: Account?
    @State private var refreshID = UUID()
    private let didSave = NSManagedObjectContext.recordsDidSave

    init(kind: AccountKind) {
        self.kind = kind
        _accounts = FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)], predicate: kind.predicate)
    }

    var columns: [GridItem] {
        let count = budgetRows || dynamicTypeSize >= .xxLarge ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    var open: [Account] {
        accounts.filter { !$0.isClosed && !$0.isGone }
    }

    var closed: [Account] {
        accounts.filter { $0.isClosed && !$0.isGone }
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                EmptyStateView(systemImage: kind == .goal ? "target" : "creditcard", title: kind == .goal ? "No goals yet" : "No debts yet")
                    .tabBarClearance()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !open.isEmpty {
                            SavingsSummaryCard(kind: kind, accounts: open)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(open, id: \.objectID) { account in
                                    tile(account)
                                }
                            }
                            .padding(.top, 12)
                        }

                        if !closed.isEmpty {
                            (kind == .goal ? Text("goals-done-section") : Text("debts-paid-off-section"))
                                .font(.app(.subheadline, weight: .semibold))
                                .foregroundColor(Color.SubtitleText)
                                .textCase(.uppercase)
                                .padding(.horizontal, 6)
                                .padding(.top, open.isEmpty ? 4 : 28)
                                .padding(.bottom, 10)
                                .accessibilityAddTraits(.isHeader)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(closed, id: \.objectID) { account in
                                    tile(account)
                                        .opacity(0.6)
                                }
                            }
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
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
        #if DEBUG
        .onAppear {
            guard let account = PlanScreenshot.account(named: PlanScreenshot.value(after: "-planDetail")), account.accountKind == kind else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                detail = account
            }
        }
        #endif
        .sheet(item: $detail) { account in
            SavingsDetailSheet(account: account)
                .environmentObject(dataController)
                .environmentObject(toastPresenter)
        }
    }

    func tile(_ account: Account) -> some View {
        Button {
            detail = account
        } label: {
            SavingsTile(account: account)
        }
        .buttonStyle(InsightsCardButtonStyle())
    }
}

/// The total across goals or debts, like the overall budget's card.
struct SavingsSummaryCard: View {
    let kind: AccountKind
    let accounts: [Account]
    let formatter = BudgetFormatter.current

    var body: some View {
        let converter = CurrencyConverter.current()
        let balances = accounts.map { $0.balance(using: converter).value }
        let thisMonth = accounts.reduce(0) { $0 + $1.netThisMonth(using: converter) }
        let total = kind == .goal ? balances.reduce(0, +) : -balances.reduce(0, +)

        InsightsCard {
            VStack(alignment: .leading, spacing: 0) {
                (kind == .goal ? Text("Saved") : Text("Owed"))
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .accessibilityAddTraits(.isHeader)

                BudgetAmountText(amount: total, font: .app(.largeTitle, weight: .semibold), formatter: formatter)
                    .padding(.top, 6)

                Text(monthLine(thisMonth))
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundColor(Color.SubtitleText)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    /// What went in this month: put aside towards goals, or paid off debts.
    func monthLine(_ net: Double) -> String {
        guard abs(net) >= 0.005 else {
            return kind == .goal ? String(localized: "Nothing put aside this month") : String(localized: "Nothing paid off this month")
        }

        if kind == .goal {
            return net > 0 ? String(localized: "\(formatter.money(net)) put aside this month") : String(localized: "\(formatter.money(net)) taken out this month")
        }
        return net > 0 ? String(localized: "\(formatter.money(net)) paid off this month") : String(localized: "\(formatter.money(net)) added this month")
    }
}

/// A goal or debt, laid out like a budget's tile. Goals fill towards their target; debts fill as they're paid off.
struct SavingsTile: View {
    @ObservedObject var account: Account
    let formatter = BudgetFormatter.current

    var body: some View {
        if account.isGone {
            EmptyView()
        } else {
            let summary = SavingsSummary(account: account, formatter: formatter)

            InsightsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        AccountIconView(symbol: account.wrappedSymbol)
                            .font(.app(.body, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)

                        Text(account.wrappedName)
                            .font(.app(.body, weight: .semibold))
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)

                        if summary.isDone {
                            Spacer(minLength: 4)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.app(.subheadline, weight: .semibold))
                                .foregroundColor(Color.IncomeGreen)
                                .accessibilityLabel(account.isGoal ? Text("Reached") : Text("Paid off"))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        BudgetAmountText(amount: summary.amount, font: .app(.title, weight: .semibold), formatter: formatter)
                            .layoutPriority(1)

                        Text(summary.word)
                            .font(.app(.body, weight: .medium))
                            .foregroundColor(Color.SubtitleText)
                            .lineLimit(1)
                    }
                    .padding(.top, 10)

                    Text(summary.status)
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    BudgetMeter(share: summary.share, colour: summary.colour, tick: nil, height: 14)
                        .padding(.top, 12)
                }
                .padding(EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Detail sheet

/// One goal or debt: its ring, where it's heading, a way to put money in or take it out, and what's in it.
struct SavingsDetailSheet: View {
    @ObservedObject var account: Account

    @Environment(\.dismiss) var dismiss
    @ObservedObject var dataController = DataController.shared
    @StateObject private var sheetManager = OverallTransactionManager()

    @State private var refreshID = UUID()
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var confirmedDelete = false
    @State private var entry: SavingsEntry?
    @State private var conversion: AccountConversion?
    private let didSave = NSManagedObjectContext.recordsDidSave
    let formatter = BudgetFormatter.current

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
            if !account.isGone {
                VStack(spacing: 32) {
                    hero

                    actions
                        .padding(.horizontal, 24)

                    FilteredAccountView(account: .account(account))
                        .padding(.horizontal, 14)
                }
                .id(refreshID)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .tabHeader {
            header
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
        .sheet(item: $entry) { entry in
            switch entry {
            case let .transfer(from, to):
                TransactionView(transferFrom: from, to: to)
            case let .expense(choice):
                TransactionView(expenseIn: choice)
            }
        }
        .sheet(isPresented: $showEdit) {
            SavingsEditorView(target: .edit(account))
        }
        .sheet(item: $conversion) { conversion in
            AccountConversionSheet(conversion: conversion) {
                // It's not a goal or debt any more, so it leaves this page.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    dismiss()
                }
            }
        }
        .confirmationSheet(isPresented: $showDelete, title: deleteTitle, message: deleteMessage, onDismiss: deleteIfConfirmed) {
            confirmedDelete = true
        }
        .environmentObject(sheetManager)
        .onReceive(didSave) { _ in
            refreshID = UUID()
        }
        #if DEBUG
        .onAppear {
            let everyday = AccountPreferences.lastUsed(among: dataController.accounts(of: .everyday))
            let here = AccountChoice.account(account)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                switch PlanScreenshot.value(after: "-detailAction") {
                case "add", "pay":
                    entry = .transfer(from: everyday, to: here)
                case "takeOut":
                    entry = .transfer(from: here, to: everyday)
                case "charge":
                    entry = .expense(here)
                case "everyday":
                    conversion = AccountConversion(account: account, kind: .everyday)
                case "delete":
                    showDelete = true
                default:
                    break
                }
            }
        }
        #endif
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    menuItems
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    var hero: some View {
        let summary = SavingsSummary(account: account, formatter: formatter)
        let segments = summary.share >= 0.005 ? [ArcRingSegment(id: "fill", start: 0, end: summary.share, colour: summary.colour, label: "")] : []

        return VStack(spacing: 4) {
            ArcRing(segments: segments, showsTrack: true) {
                BudgetAmountText(amount: summary.amount, font: .app(.title, weight: .semibold), formatter: formatter)

                Text(summary.word)
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundColor(Color.SubtitleText)

                if !summary.status.isEmpty {
                    Text(summary.status)
                        .font(.app(.footnote, weight: .medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 6)
                        .padding(.horizontal, 30)
                }
            }
            .accessibilityElement(children: .combine)

            if !summary.detail.isEmpty {
                Text(summary.detail)
                    .font(.app(.footnote, weight: .medium))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Goals take money in and out; debts take payments and new charges.
    var actions: some View {
        let everyday = AccountPreferences.lastUsed(among: dataController.accounts(of: .everyday))
        let here = AccountChoice.account(account)

        return HStack(spacing: 12) {
            if account.isGoal {
                actionButton("Add Money", systemImage: "plus", isPrimary: true) {
                    entry = .transfer(from: everyday, to: here)
                }
                actionButton("Take Out", systemImage: "minus", isPrimary: false) {
                    entry = .transfer(from: here, to: everyday)
                }
            } else {
                actionButton("Make a Payment", systemImage: "arrow.down", isPrimary: true) {
                    entry = .transfer(from: everyday, to: here)
                }
                actionButton("Add a Charge", systemImage: "plus", isPrimary: false) {
                    entry = .expense(here)
                }
            }
        }
    }

    func actionButton(_ title: LocalizedStringKey, systemImage: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.app(.body, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(isPrimary ? Color.LightIcon : Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Capsule(), tint: isPrimary ? Color.DarkBackground : Color.glassTint, fallback: isPrimary ? Color.DarkBackground : Color.SecondaryBackground)
    }

    var header: some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            .hiddenInSideBar()

            Spacer()

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .glassBackground(in: Circle(), tint: .glassTint)
            .accessibilityLabel("More")
            .hiddenInSideBar()
        }
        .frame(height: 44)
        .overlay {
            HStack(spacing: 6) {
                AccountIconView(symbol: account.wrappedSymbol)
                Text(account.wrappedName)
                    .lineLimit(1)
            }
            .font(.app(.title3, weight: .semibold))
            .foregroundColor(Color.PrimaryText)
            .padding(.horizontal, 56)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder var menuItems: some View {
        Button {
            showEdit = true
        } label: {
            if account.isGoal {
                Label("Edit Goal", systemImage: "pencil")
            } else {
                Label("Edit Debt", systemImage: "pencil")
            }
        }

        Button {
            withAnimation {
                dataController.setClosed(account, !account.isClosed)
            }
        } label: {
            if account.isClosed {
                Label("Move Back", systemImage: "arrow.uturn.backward")
            } else if account.isGoal {
                Label("Mark as Done", systemImage: "checkmark.circle")
            } else {
                Label("Mark as Paid Off", systemImage: "checkmark.circle")
            }
        }

        Button {
            conversion = AccountConversion(account: account, kind: .everyday)
        } label: {
            Label("Make It an Everyday Account", systemImage: "wallet.bifold")
        }

        Button(role: .destructive) {
            showDelete = true
        } label: {
            if account.isGoal {
                Label("Delete Goal", systemImage: "trash")
            } else {
                Label("Delete Debt", systemImage: "trash")
            }
        }
    }

    var deleteTitle: LocalizedStringKey {
        "Delete '\(account.wrappedName)'?"
    }

    var deleteMessage: LocalizedStringKey {
        if account.isGoal {
            return "Money you put in goes back to where it came from, and spending from it moves to \(MainAccount.name). To keep it, mark it as done instead."
        }
        return "Payments from \(MainAccount.name) and their interest are deleted, and other charges move to \(MainAccount.name). To keep it, mark it as paid off instead."
    }

    func deleteIfConfirmed() {
        guard confirmedDelete else { return }
        let deleted = account
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                dataController.deleteAccount(deleted)
            }
        }
    }
}

/// What the detail sheet's buttons open the entry page with.
enum SavingsEntry: Identifiable {
    case transfer(from: AccountChoice, to: AccountChoice)
    case expense(AccountChoice)

    var id: String {
        switch self {
        case let .transfer(from, to):
            return "transfer-\(from.key)-\(to.key)"
        case let .expense(choice):
            return "expense-\(choice.key)"
        }
    }
}

// MARK: - Editor

/// Creates or edits a goal or debt, written as a sentence like the budget editor: "Save $3,000 by 1 Jun 2027,
/// starting with $500." or "I owe $6,900 at 6.9% a year, paying $310 a month."
struct SavingsEditorView: View {
    enum Target: Identifiable {
        case new(AccountKind)
        case edit(Account)

        var id: String {
            switch self {
            case let .new(kind):
                return "new-\(kind.rawValue)"
            case let .edit(account):
                return account.key
            }
        }
    }

    /// The parts of the sentence that open an editor at the bottom.
    private enum Field: Hashable {
        case amount, saved, deadline, rate, payment, reminder
    }

    /// When a goal is for.
    private enum Timing: Hashable {
        case anyTime, byDate, everyMonth
    }

    /// A number typed on the keypad, with the keypad's own decimal state.
    private struct Entry {
        var value: Double = 0
        var isEditingDecimal = false
        var decimals: AssignedDecimal = .none
    }

    let target: Target

    @ObservedObject var dataController = DataController.shared
    @Environment(\.dismiss) var dismiss

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"
    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1
    @AppStorage("keyboard", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var savedKeyboardHeight: Double = .init(UIScreen.main.bounds.height / 2.5)

    @State private var name: String
    @State private var pickedSymbol: String?
    @State private var amount: Entry
    @State private var saved: Entry
    @State private var rate: Entry
    @State private var payment: Entry
    @State private var timing: Timing
    @State private var deadline: Date
    /// The day of the month to be reminded on, or 0 for never.
    @State private var reminderDay: Int

    @State private var activeField: Field?
    @State private var showTimingMenu = false
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastImage = ""
    @State private var errorFields: Set<Field> = []
    @State private var shake = false

    @ScaledMetric(relativeTo: .title) private var sentenceSize: CGFloat = 27

    private let editorAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)
    private let bottomBarTopPadding: CGFloat = 20

    init(target: Target) {
        self.target = target

        let nextYear = Calendar.current.date(byAdding: .year, value: 1, to: Date.now) ?? Date.now

        switch target {
        case .new:
            _name = State(initialValue: "")
            _amount = State(initialValue: Entry())
            _saved = State(initialValue: Entry())
            _rate = State(initialValue: Entry())
            _payment = State(initialValue: Entry())
            _timing = State(initialValue: .anyTime)
            _deadline = State(initialValue: nextYear)
            _reminderDay = State(initialValue: 0)
        case let .edit(account):
            _reminderDay = State(initialValue: SavingsReminders.day(for: account) ?? 0)
            _name = State(initialValue: account.wrappedName)
            _pickedSymbol = State(initialValue: account.wrappedSymbol)
            _rate = State(initialValue: Self.entry(account.interestRate))
            _payment = State(initialValue: Self.entry(account.paymentAmount))
            _deadline = State(initialValue: account.targetDate ?? nextYear)

            if account.isDebt {
                let owed = -account.balance(using: DataController.shared.currencyConverter).value
                _amount = State(initialValue: Self.entry(max(owed, 0)))
                _saved = State(initialValue: Entry())
                _timing = State(initialValue: .anyTime)
            } else {
                _amount = State(initialValue: Self.entry(account.targetAmount))
                _saved = State(initialValue: Self.entry(account.startingBalance))
                _timing = State(initialValue: account.repeatsMonthly ? .everyMonth : (account.targetDate == nil ? .anyTime : .byDate))
            }
        }
    }

    private static func entry(_ value: Double) -> Entry {
        let hasCents = value.truncatingRemainder(dividingBy: 1) != 0
        return Entry(value: value, isEditingDecimal: hasCents, decimals: hasCents ? .second : .none)
    }

    var kind: AccountKind {
        switch target {
        case let .new(kind):
            return kind
        case let .edit(account):
            return account.accountKind
        }
    }

    var editing: Account? {
        if case let .edit(account) = target {
            return account
        }
        return nil
    }

    var isDebt: Bool {
        kind == .debt
    }

    /// The icon picked here, or until one is, one that suits the name.
    var symbol: String {
        if let pickedSymbol {
            return pickedSymbol
        }
        let guessed = AccountIcons.guess(for: name)
        if guessed == AccountIcons.defaultSymbol {
            return isDebt ? "creditcard" : "star"
        }
        return guessed
    }

    var sentenceFont: Font {
        .app(size: min(sentenceSize, 33), weight: .semibold)
    }

    var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? "$"
    }

    var deadlineRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date.now)) ?? Date.now
        let later = calendar.date(byAdding: .year, value: 30, to: tomorrow) ?? tomorrow
        // An existing goal's deadline can have passed; it stays pickable.
        return min(tomorrow, deadline) ... later
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    nameRow

                    VStack(alignment: .leading, spacing: 16) {
                        sentence

                        if let hint {
                            Text(hint)
                                .font(.app(.body, weight: .medium))
                                .foregroundColor(Color.SubtitleText)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .padding(.horizontal, 20)
            }
            .budgetScrollBounceBasedOnSize()
        }
        .tabHeader {
            header
                .padding(.top, 20)
                .padding(.horizontal, 20)
        }
        .bottomBar {
            Group {
                if let activeField {
                    editor(activeField)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    primaryButton
                        .padding(.top, bottomBarTopPadding)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color.PrimaryBackground)
        .modifier(TransactionSheetPresentation())
        .animation(.easeOut(duration: 0.2), value: showToast)
        .animation(editorAnimation, value: activeField)
        .animation(.easeInOut(duration: 0.2), value: timing)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        #if DEBUG
        .onAppear {
            if editing == nil, ProcessInfo.processInfo.arguments.contains("-editorFill") {
                if isDebt {
                    name = "Student loan"
                    amount = Self.entry(DemoLocale.amount(8_400))
                    rate = Entry(value: 4.5, isEditingDecimal: true, decimals: .first)
                    payment = Self.entry(DemoLocale.amount(250))
                    reminderDay = 20
                } else {
                    name = "Wedding"
                    amount = Self.entry(DemoLocale.amount(12_000))
                    saved = Self.entry(DemoLocale.amount(1_500))
                    timing = .byDate
                    deadline = Calendar.current.date(byAdding: .month, value: 18, to: Date.now) ?? deadline
                    reminderDay = 1
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                UIApplication.shared.endEditing()
                switch PlanScreenshot.value(after: "-editorField") {
                case "amount":
                    activeField = .amount
                case "saved":
                    activeField = .saved
                case "deadline":
                    activeField = .deadline
                case "rate":
                    activeField = .rate
                case "payment":
                    activeField = .payment
                case "reminder":
                    activeField = .reminder
                case "timing":
                    showTimingMenu = true
                default:
                    break
                }
            }
        }
        #endif
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
        }
    }

    var header: some View {
        HStack {
            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            .hiddenInSideBar()

            Spacer()
        }
        .frame(height: 44)
        .overlay {
            if showToast {
                GlassToast(title: toastTitle, systemImage: toastImage, color: Color.AlertRed)
            } else {
                CategoryEditorTitle(title: title)
            }
        }
    }

    var title: LocalizedStringKey {
        switch (kind, editing == nil) {
        case (.debt, true):
            return "New Debt"
        case (.debt, false):
            return "Edit Debt"
        case (_, true):
            return "New Goal"
        default:
            return "Edit Goal"
        }
    }

    /// The icon, which opens every icon, and the name.
    var nameRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(AccountIcons.all, id: \.self) { icon in
                    Button {
                        pickedSymbol = icon
                    } label: {
                        Image(systemName: AccountIcons.displayable(icon))
                    }
                }
            } label: {
                AccountIconView(symbol: symbol)
                    .font(.app(.title3, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .glassBackground(in: Circle(), tint: .glassTint)
            .accessibilityLabel("Icon")
            .simultaneousGesture(TapGesture().onEnded { closeField() })

            NormalTextField(text: $name, placeholder: isDebt ? String(localized: "Debt Name") : String(localized: "Goal Name"), autofocus: editing == nil) {
                UIApplication.shared.endEditing()
            }
            .foregroundColor(Color.PrimaryText)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .glassField(in: Capsule(), isFocused: false)
            .simultaneousGesture(TapGesture().onEnded { closeField() })
        }
    }

    var primaryButton: some View {
        Button {
            submit()
        } label: {
            Text(primaryTitle)
                .font(.app(.headline))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Capsule())
        }
        .whiteGlassButtonStyle()
    }

    var primaryTitle: LocalizedStringKey {
        if editing != nil {
            return "Save"
        }
        return isDebt ? "Add Debt" : "Add Goal"
    }

    // MARK: Sentence

    @ViewBuilder var sentence: some View {
        Group {
            if #available(iOS 16.0, *) {
                SentenceFlowLayout(spacing: 10, lineSpacing: 6) {
                    if isDebt {
                        lead("I owe").layoutValue(key: KeepWithNext.self, value: true)
                        token(.amount)
                        lead("at").layoutValue(key: KeepWithNext.self, value: true)
                        HStack(spacing: 0) {
                            token(.rate)
                            comma
                        }
                        lead("paying").layoutValue(key: KeepWithNext.self, value: true)
                        token(.payment).layoutValue(key: KeepWithNext.self, value: true)
                        lead("a month.")
                        lead("Remind me").layoutValue(key: KeepWithNext.self, value: true)
                        HStack(spacing: 0) {
                            reminderToken
                            fullStop
                        }
                    } else {
                        lead("goal-sentence-save").layoutValue(key: KeepWithNext.self, value: true)
                        token(.amount)
                        HStack(spacing: 0) {
                            timingToken
                            comma
                        }
                        lead("starting with").layoutValue(key: KeepWithNext.self, value: true)
                        HStack(spacing: 0) {
                            token(.saved)
                            fullStop
                        }
                        lead("Remind me").layoutValue(key: KeepWithNext.self, value: true)
                        HStack(spacing: 0) {
                            reminderToken
                            fullStop
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if isDebt {
                        clause("I owe") { token(.amount) }
                        clause("at") { token(.rate) }
                        clause("paying") { token(.payment) }
                        lead("a month.")
                    } else {
                        clause("goal-sentence-save") { token(.amount) }
                        timingToken
                        clause("starting with") { token(.saved) }
                    }
                    clause("Remind me") { reminderToken }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    func lead(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(sentenceFont)
            .foregroundColor(Color.PrimaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    func clause<Token: View>(_ text: LocalizedStringKey, @ViewBuilder token: () -> Token) -> some View {
        HStack(spacing: 10) {
            lead(text)
            token()
        }
    }

    var comma: some View {
        Text(",")
            .font(sentenceFont)
            .foregroundColor(Color.PrimaryText)
            .accessibilityHidden(true)
    }

    var fullStop: some View {
        Text(".")
            .font(sentenceFont)
            .foregroundColor(Color.PrimaryText)
            .accessibilityHidden(true)
    }

    private func token(_ field: Field) -> some View {
        let isFocused = activeField == field
        let value = entry(field).value
        let text = tokenText(field)

        return SentenceTokenButton(
            text: text,
            font: sentenceFont,
            foreground: value == 0 && !isFocused ? Color.SubtitleText : Color.PrimaryText,
            tint: nil,
            isFocused: isFocused,
            isError: errorFields.contains(field),
            shake: shake && errorFields.contains(field),
            accessibilityLabel: Text(accessibilityName(field)) + Text(", ") + Text(text),
            clear: isFocused && (value != 0 || entry(field).isEditingDecimal) ? { clear(field) } : nil
        ) {
            toggle(field)
        }
    }

    var reminderToken: some View {
        let isFocused = activeField == .reminder

        return SentenceTokenButton(
            text: reminderText,
            font: sentenceFont,
            foreground: reminderDay == 0 && !isFocused ? Color.SubtitleText : Color.PrimaryText,
            tint: nil,
            isFocused: isFocused,
            isError: false,
            shake: false,
            accessibilityLabel: Text("Remind me") + Text(", ") + Text(reminderText),
            clear: isFocused && reminderDay != 0 ? {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                reminderDay = 0
            } : nil
        ) {
            toggle(.reminder)
        }
        .accessibilityHint("A notification on this day every month")
    }

    var reminderText: String {
        guard reminderDay > 0 else {
            return String(localized: "never")
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let day = formatter.string(from: NSNumber(value: reminderDay)) ?? "\(reminderDay)"
        return String(localized: "on the \(day)")
    }

    var timingToken: some View {
        SentenceTokenButton(
            text: timingText,
            font: sentenceFont,
            foreground: Color.PrimaryText,
            tint: nil,
            isFocused: activeField == .deadline,
            isError: false,
            shake: false,
            accessibilityLabel: Text("When") + Text(", ") + Text(timingText)
        ) {
            closeField {
                showTimingMenu = true
            }
        }
        .popover(present: $showTimingMenu, attributes: popoverAttributes) {
            GlassPopoverMenu {
                GlassPopoverRow("with no deadline", isSelected: timing == .anyTime) {
                    select(.anyTime)
                }
                GlassPopoverRow("by a date", isSelected: timing == .byDate) {
                    select(.byDate)
                }
                GlassPopoverRow("every month", isSelected: timing == .everyMonth) {
                    select(.everyMonth)
                }
            }
        }
    }

    var timingText: String {
        switch timing {
        case .anyTime:
            return String(localized: "with no deadline")
        case .byDate:
            return String(localized: "by \(deadline.formatted(.dateTime.day().month(.abbreviated).year()))")
        case .everyMonth:
            return String(localized: "every month")
        }
    }

    func popoverAttributes(_ attributes: inout Popover.Attributes) {
        attributes.position = .absolute(originAnchor: .bottom, popoverAnchor: .top)
        attributes.rubberBandingMode = .none
        attributes.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -8, right: 0)
        attributes.presentation.animation = .easeInOut(duration: 0.2)
        attributes.dismissal.animation = .easeInOut(duration: 0.3)
    }

    private func accessibilityName(_ field: Field) -> LocalizedStringKey {
        switch field {
        case .amount:
            return isDebt ? "Owed" : "Amount"
        case .saved:
            return "Already saved"
        case .deadline:
            return "Deadline"
        case .rate:
            return "Interest"
        case .payment:
            return "Monthly payment"
        case .reminder:
            return "Remind me"
        }
    }

    private func tokenText(_ field: Field) -> String {
        let value = entry(field)

        if field == .rate {
            if activeField != .rate && value.value == 0 {
                return String(localized: "no interest")
            }
            return String(localized: "\(typed(value))% a year")
        }

        if activeField == field || value.value == 0 {
            return currencySymbol + typed(value)
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let digits = value.value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value.value)) ?? currencySymbol + typed(value)
    }

    /// The number as it's being typed, like the budget editor's amount.
    private func typed(_ entry: Entry) -> String {
        if numberEntryType == 1 {
            return String(format: "%.2f", entry.value)
        }
        if entry.isEditingDecimal {
            switch entry.decimals {
            case .none:
                return String(format: "%.0f", entry.value) + "."
            case .first:
                return String(format: "%.1f", entry.value)
            case .second:
                return String(format: "%.2f", entry.value)
            case .third:
                return String(format: "%.3f", entry.value)
            }
        }
        return String(format: "%.0f", entry.value)
    }

    /// The monthly amount a goal with a deadline needs, or when a debt ends.
    var hint: String? {
        let formatter = BudgetFormatter.current

        if isDebt {
            guard amount.value > 0, payment.value > 0 else { return nil }

            guard let projection = DebtProjection.make(owed: amount.value, yearlyRate: rate.value, payment: payment.value) else {
                return String(localized: "That payment doesn't cover the interest, so this debt won't go down.")
            }

            let date = projection.payoffDate().formatted(.dateTime.month(.wide).year())
            if projection.interest >= 1 {
                return String(localized: "Paid off around \(date), with about \(formatter.approx(projection.interest)) in interest.")
            }
            return String(localized: "Paid off around \(date).")
        }

        guard timing == .byDate, amount.value > 0 else { return nil }

        let progress = GoalProgress(saved: currentSaved, target: amount.value, deadline: deadline, repeatsMonthly: false, savedThisMonth: 0, now: .now)

        if progress.isReached {
            return String(localized: "Already saved.")
        }

        guard let perMonth = progress.perMonth else { return nil }
        return String(localized: "≈ \(formatter.approx(perMonth)) a month")
    }

    /// What's in the goal: what was already saved, plus what's been put in since.
    var currentSaved: Double {
        guard let editing else { return saved.value }
        return editing.balance(using: dataController.currencyConverter).value - editing.startingBalance + saved.value
    }

    // MARK: Bottom editors

    private func editor(_ field: Field) -> some View {
        ZStack {
            switch field {
            case .deadline:
                GlassDatePicker(selection: $deadline, in: deadlineRange, visibleWeeks: 5) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard activeField == .deadline else { return }
                        closeField()
                    }
                }
                .padding(.top, bottomBarTopPadding - 4)
                .padding(.bottom, 15)
                .transition(.opacity)
            case .reminder:
                BudgetDayGrid(selection: $reminderDay, title: { day in
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .ordinal
                    return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
                }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard activeField == .reminder else { return }
                        closeField()
                    }
                }
                .padding(.top, bottomBarTopPadding - 4)
                .padding(.bottom, 15)
                .transition(.opacity)
            default:
                NumberPad(
                    price: binding(field).value,
                    category: .constant(nil),
                    isEditingDecimal: binding(field).isEditingDecimal,
                    decimalValuesAssigned: binding(field).decimals
                ) {
                    commit(field)
                }
                .frame(height: CGFloat(savedKeyboardHeight))
                .padding(.top, bottomBarTopPadding)
                .transition(.opacity)
            }
        }
    }

    private func entry(_ field: Field) -> Entry {
        switch field {
        case .amount, .deadline, .reminder:
            return amount
        case .saved:
            return saved
        case .rate:
            return rate
        case .payment:
            return payment
        }
    }

    private func binding(_ field: Field) -> Binding<Entry> {
        switch field {
        case .amount, .deadline, .reminder:
            return $amount
        case .saved:
            return $saved
        case .rate:
            return $rate
        case .payment:
            return $payment
        }
    }

    // MARK: Actions

    private func toggle(_ field: Field) {
        UIApplication.shared.endEditing()
        withAnimation(editorAnimation) {
            activeField = activeField == field ? nil : field
        }
    }

    private func closeField(then action: (() -> Void)? = nil) {
        if activeField != nil {
            withAnimation(editorAnimation) {
                activeField = nil
            }
            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
            }
        } else {
            action?()
        }
    }

    private func select(_ newTiming: Timing) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        timing = newTiming

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showTimingMenu = false

            if newTiming == .byDate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(editorAnimation) {
                        activeField = .deadline
                    }
                }
            }
        }
    }

    private func commit(_ field: Field) {
        if field == .amount && amount.value == 0 {
            flagError(title: "Missing Amount", image: "centsign.circle", fields: [.amount])
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        closeField()
    }

    private func clear(_ field: Field) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        binding(field).wrappedValue = Entry()
    }

    private func flagError(title: String, image: String, fields: Set<Field>) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        toastTitle = title
        toastImage = image
        showToast = true

        withAnimation(.easeOut(duration: 0.2)) {
            errorFields = fields
        }
        withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.1)) {
                shake = false
            }
            withAnimation(.easeOut(duration: 0.6)) {
                errorFields = []
            }
        }
    }

    func submit() {
        if editing?.isGone == true {
            flagError(title: isDebt ? String(localized: "Debt Was Deleted") : String(localized: "Goal Was Deleted"), image: "trash", fields: [])
            return
        }

        switch dataController.accountNameCheck(name, editing: editing.map(AccountChoice.account)) {
        case .missingName:
            flagError(title: String(localized: "Missing Name"), image: "character.cursor.ibeam", fields: [])
            return
        case .duplicateName:
            flagError(title: String(localized: "Duplicate Name"), image: "character.cursor.ibeam", fields: [])
            return
        case .none:
            break
        }

        if amount.value == 0 {
            flagError(title: String(localized: "Missing Amount"), image: "centsign.circle", fields: [.amount])
            withAnimation(editorAnimation) {
                activeField = .amount
            }
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let saved: Account

        if isDebt {
            if let editing {
                dataController.updateDebt(editing, name: name, symbol: symbol, owed: amount.value, yearlyRate: rate.value, payment: payment.value)
                saved = editing
            } else {
                saved = dataController.addDebt(named: name, symbol: symbol, owed: amount.value, yearlyRate: rate.value, payment: payment.value)
            }
        } else {
            let date = timing == .byDate ? deadline : nil
            if let editing {
                dataController.updateGoal(editing, name: name, symbol: symbol, target: amount.value, repeatsMonthly: timing == .everyMonth, deadline: date, alreadySaved: self.saved.value)
                saved = editing
            } else {
                saved = dataController.addGoal(named: name, symbol: symbol, target: amount.value, repeatsMonthly: timing == .everyMonth, deadline: date, alreadySaved: self.saved.value)
            }
        }

        let previousDay = SavingsReminders.day(for: saved)
        SavingsReminders.set(reminderDay == 0 ? nil : reminderDay, for: saved)

        if reminderDay != 0 {
            NotificationScheduler.shared.requestAuthorizationAndReschedule()
        } else if previousDay != nil {
            NotificationScheduler.shared.reschedule()
        }

        dismiss()
    }
}

// MARK: - Converting accounts

/// An account to make a goal, a debt or an everyday account again.
struct AccountConversion: Identifiable {
    let account: Account
    let kind: AccountKind

    var id: String {
        "\(account.key)-\(kind.rawValue)"
    }
}

/// Says what converting an account changes before it's done. Nothing is deleted either way, but what its expenses
/// and income count towards changes.
struct AccountConversionSheet: View {
    let conversion: AccountConversion
    let onConvert: () -> Void

    @ObservedObject var dataController = DataController.shared
    @Environment(\.dismiss) private var dismiss
    let formatter = BudgetFormatter.current

    var body: some View {
        ConfirmationSheet(title: title, message: message, systemImage: systemImage) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dataController.convertAccount(conversion.account, to: conversion.kind)
                dismiss()
                onConvert()
            } label: {
                Text(confirmTitle)
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.LightIcon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(in: Capsule(), tint: Color.DarkBackground, fallback: Color.DarkBackground)

            ConfirmationCancelButton {
                dismiss()
            }
        }
    }

    var name: String {
        conversion.account.wrappedName
    }

    var systemImage: String {
        switch conversion.kind {
        case .goal:
            return "target"
        case .debt:
            return "creditcard"
        case .everyday:
            return "wallet.bifold"
        }
    }

    var title: LocalizedStringKey {
        switch conversion.kind {
        case .goal:
            return "Make '\(name)' a goal?"
        case .debt:
            return "Make '\(name)' a debt?"
        case .everyday:
            return "Make '\(name)' an everyday account?"
        }
    }

    var confirmTitle: LocalizedStringKey {
        switch conversion.kind {
        case .goal:
            return "Make It a Goal"
        case .debt:
            return "Make It a Debt"
        case .everyday:
            return "Make It an Everyday Account"
        }
    }

    var message: LocalizedStringKey {
        let counts = dataController.entryCounts(in: conversion.account)
        let balance = conversion.account.balance(using: dataController.currencyConverter).value

        switch conversion.kind {
        case .goal:
            let saved = formatter.money(max(balance, 0))
            if counts.expenses == 0 {
                return "It starts with the \(saved) in it now. Nothing is deleted."
            }
            return "It starts with the \(saved) in it now. Its \(counts.expenses) expenses become spending from the goal: they still count in Insights, but no longer against your budgets. Nothing is deleted."
        case .debt:
            let owed = formatter.money(max(-balance, 0))
            return "It starts out owing \(owed): its spending less what's come into it. Its expenses still count as spending and against your budgets, and new ones add to what it owes. Nothing is deleted."
        case .everyday:
            return "It moves back to Settings › Accounts with everything in it, and no longer shows a target or what's owed. Nothing is deleted."
        }
    }
}
