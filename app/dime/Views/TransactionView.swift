//
//  TransactionView.swift
//  xpenz
//
//  Created by Rafael Soh on 14/5/22.
//

import Combine
import CoreData
import Foundation
import Popovers
import SwiftUI

struct TransactionView: View {
    @ObservedObject var dataController = DataController.shared
    // Not the environment's context: a sheet SwiftUI shows without its environment would get an empty one.
    private var moc: NSManagedObjectContext {
        dataController.container.viewContext
    }
    @Environment(\.dismiss) var dismiss

    @Environment(\.colorScheme) var colorScheme

    @State private var note = ""
    @State var category: Category?
    @State private var date = Date.now
    @State private var repeatType = 0
    @State private var repeatCoefficient = 1
    @State var income = false

    var transactionTypeString: String {
        if income {
            return "Income"
        } else {
            return "Expense"
        }
    }

    @State var showCategorySheet = false

    // accounts and transfers
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accountObjects: FetchedResults<Account>
    /// Redraws account names and icons when Main is renamed or given another icon.
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainAccountName = ""
    @AppStorage(MainAccount.symbolKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainAccountSymbol = ""
    /// The account an expense or income goes into, or where a transfer comes from.
    @State private var account: AccountChoice = .main
    @State private var isTransfer = false
    /// Where a transfer goes.
    @State private var transferTo: AccountChoice?
    @State private var accountPicker: AccountPickerTarget?

    enum AccountPickerTarget: String, Identifiable {
        case account, from, to

        var id: String { rawValue }
    }

    enum EntryKind: Hashable {
        case expense, income, transfer
    }

    /// Accounts only show once there's one besides Main. A transfer being edited always shows, so it can be changed.
    var showsAccounts: Bool {
        !accountObjects.isEmpty || toEdit?.isTransfer == true
    }

    var allowsTransfer: Bool {
        showsAccounts && !isTemplate
    }

    var kindSelection: Binding<EntryKind> {
        Binding {
            isTransfer ? .transfer : (income ? .income : .expense)
        } set: { kind in
            let becomesTransfer = kind == .transfer

            if becomesTransfer && !isTransfer {
                // Transfers don't repeat, and go somewhere other than where they come from.
                repeatType = 0
                if transferTo == nil || transferTo == account {
                    transferTo = defaultTransferDestination
                }
            }

            isTransfer = becomesTransfer
            income = kind == .income
        }
    }

    var kindOptions: [(value: EntryKind, title: LocalizedStringKey)] {
        var options: [(value: EntryKind, title: LocalizedStringKey)] = [(value: .expense, title: "Expense")]

        if showsIncomeControls {
            options.append((value: .income, title: "transaction-view-income-picker"))
        }

        if allowsTransfer {
            options.append((value: .transfer, title: "Transfer"))
        }

        return options
    }

    /// The first account that isn't where the transfer comes from.
    var defaultTransferDestination: AccountChoice? {
        ([.main] + accountObjects.map(AccountChoice.account)).first { $0 != account }
    }

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @State var showingDatePicker = false

    // toasts
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // shaking category error

    @ObservedObject var keyboardHeightHelper = KeyboardHeightHelper()

    @AppStorage(
        "firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var firstLaunch: Bool = true

    // edit mode
    let toEdit: Transaction?

    /// What the page edits when it's a Quick Add template rather than a transaction.
    enum TemplateTarget {
        case new
        case existing(TemplateTransaction)
    }

    /// Set when the page edits a Quick Add template. Templates have no date and don't repeat.
    let template: TemplateTarget?

    var isTemplate: Bool {
        template != nil
    }

    var editedTemplate: TemplateTransaction? {
        if case let .existing(existing) = template {
            return existing
        }
        return nil
    }

    /// The saved transaction or template this page edits, if any.
    var editedObject: NSManagedObject? {
        if let toEdit {
            return toEdit
        }
        return editedTemplate
    }

    var isEditing: Bool {
        toEdit != nil || editedTemplate != nil
    }

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    var showsIncomeControls: Bool {
        incomeTracking || toEdit?.income == true || editedTemplate?.income == true
    }

    // delete mode

    @State var toDelete: Transaction?
    @State var deleteMode = false

    let numberArray = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var repeatButtonAccessibility: String {
        if repeatType == 1 {
            return "transaction recurs daily, button to edit recurring duration"
        } else if repeatType == 2 {
            return "transaction recurs weekly, button to edit recurring duration"
        } else if repeatType == 3 {
            return "transaction recurs monthly, button to edit recurring duration"
        } else {
            return "button to make transaction recurring"
        }
    }

    var dateString: String {
        CachedFormatter.date(format: "d MMM yyyy").string(from: date)
    }

    @State var showPicker = false
    @State var animateIcon = false

    @State var swipingOffset: CGFloat = 0
    @GestureState var isDragging = false
    @State private var isDismissDragging = false

    // show recommendations

    @State var textFieldFocused: Bool = false

    @AppStorage(
        "showTransactionRecommendations", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var showRecommendations: Bool = false

    var suggestedTransactions: [Transaction] {
        return dataController.getSuggestedNotes(searchQuery: note, category: category, income: income)
    }

    var showingNotePicker: Bool {
        return note != "" && !isEditing && !suggestedTransactions.isEmpty && textFieldFocused
        && showRecommendations
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var capsuleWidth: CGFloat {
        if dynamicTypeSize > .xLarge {
            return 120
        } else {
            return 100
        }
    }

    @State private var price: Double = 0
    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var numberEntryType: Int = 1
    @State var isEditingDecimal = false
    @State var decimalValuesAssigned: AssignedDecimal = .none
    @State private var priceString: String = "0"

    @State private var selectedCurrency: String?
    @State private var showCurrencyPicker = false

    var transactionCurrency: String {
        if let selectedCurrency {
            return selectedCurrency
        }

        if let transaction = toEdit {
            return (transaction.currencyCode ?? currency).uppercased()
        }

        if let editedTemplate {
            return (editedTemplate.currencyCode ?? currency).uppercased()
        }

        return dataController.currencyForNewEntry()
    }

    var usesMainCurrency: Bool {
        CurrencyPreferences.isSameCurrency(transactionCurrency, as: nil, mainCurrency: currency)
    }

    var fractionDigits: Int {
        CurrencyDigits.fractionDigits(for: transactionCurrency)
    }

    var convertedPreview: String? {
        guard !usesMainCurrency else {
            return nil
        }

        guard let converted = CurrencyConverter.current().convert(price, from: transactionCurrency, on: date) else {
            return String(localized: "No exchange rate yet")
        }

        return "≈ " + MoneyFormatter.string(converted, currencyCode: currency)
    }

    @State private var usesVerticalBar = VerticalBar.isActiveInKeyWindow

    var body: some View {
        sideBarNavigation {
            GeometryReader { proxy in
                let sideOcclusion = proxy.sideOcclusionInsets

                VStack(spacing: 8) {
                    // income/expense picker
                    HStack(spacing: 10) {
                        if !usesVerticalBar {
                            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                                dismiss()
                            }

                            Spacer()

                            if !isTemplate && !isTransfer {
                                RecurringMenu(
                                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient,
                                    showPicker: $showPicker, accessibilityLabel: repeatButtonAccessibility)
                            }
                        }
                    }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if showToast {
                            GlassToast(title: toastTitle, systemImage: toastImage, color: Color.AlertRed)
                        } else if kindOptions.count > 1 && usesVerticalBar {
                            // The Duo's sheet has room for every choice side by side.
                            GlassSegmentedPicker(selection: kindSelection, options: kindOptions, segmentPadding: kindOptions.count > 2 ? 12 : 16)
                        } else if kindOptions.count > 1 {
                            EntryKindMenu(selection: kindSelection, options: kindOptions)
                        } else {
                            CategoryEditorTitle(title: "Expense")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isEditing && !usesVerticalBar {
                            GlassIconButton(
                                systemName: "trash.fill",
                                accessibilityLabel: "delete transaction",
                                foreground: Color.AlertRed,
                                tint: Color.AlertRed.opacity(0.2),
                                fallback: Color.AlertRed.opacity(0.23)
                            ) {
                                toDelete = toEdit
                                deleteMode = true
                            }
                            .offset(y: 44 + 10)
                        }
                    }
                    .padding(.top, 3)
                    .zIndex(1)

                    ZStack {
                        // swipe to change between income and expense
                        Color.PrimaryBackground
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(
                                DragGesture()
                                    .updating(
                                        $isDragging,
                                        body: { _, state, _ in
                                            state = true
                                        }
                                    )
                                    .onChanged { gesture in
                                        let swipe = gesture.translation.width

                                        guard showsIncomeControls, !isTransfer, abs(swipe) > abs(gesture.translation.height) else { return }

                                        if income {
                                            if swipe < 0 {
                                                swipingOffset = max(-capsuleWidth, -pow(abs(swipe), 0.8)) + capsuleWidth
                                            }

                                        } else {
                                            if swipe > 0 {
                                                swipingOffset = min(capsuleWidth, pow(swipe, 0.8))
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        guard !isTransfer else { return }

                                        if income {
                                            if swipingOffset < (capsuleWidth / 2) {
                                                withAnimation {
                                                    swipingOffset = 0
                                                    income = false
                                                }
                                            } else {
                                                withAnimation {
                                                    swipingOffset = capsuleWidth
                                                }
                                            }
                                        } else {
                                            if swipingOffset > (capsuleWidth / 2) {
                                                withAnimation {
                                                    swipingOffset = capsuleWidth
                                                    income = true
                                                }
                                            } else {
                                                withAnimation {
                                                    swipingOffset = 0
                                                }
                                            }
                                        }
                                    }
                            )

                        // number display and note view
                        VStack(spacing: 8) {
                            NumberPadTextView(price: $price, isEditingDecimal: $isEditingDecimal, decimalValuesAssigned: $decimalValuesAssigned, fractionDigits: fractionDigits, currencyCode: usesMainCurrency ? nil : transactionCurrency) {
                                showCurrencyPicker = true
                            }

                            if let convertedPreview {
                                Text(convertedPreview)
                                    .font(.app(.subheadline, weight: .medium))
                                    .foregroundColor(Color.SubtitleText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }

                            NoteView(note: $note, focused: $textFieldFocused)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .featureTipHost()

                    if showingNotePicker {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedTransactions, id: \.self) { transaction in
                                    Button {
                                        note = transaction.wrappedNote
                                        withAnimation {
                                            if price == 0 {
                                                price = transaction.wrappedAmount
                                                selectedCurrency = (transaction.currencyCode ?? currency).uppercased()
                                            }
                                            if category == nil {
                                                category = transaction.category
                                            }
                                        }
                                        self.hideKeyboard()
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(transaction.wrappedNote)
                                                .foregroundStyle(Color.PrimaryText)
                                                .lineLimit(1)
                                                .padding(.vertical, 3.5)
                                                .padding(.horizontal, 7)

                                            Text("\(symbol(for: transaction))\(Int(round(transaction.wrappedAmount)))")
                                                .lineLimit(1)
                                                .foregroundStyle(Color(hex: transaction.wrappedColour))
                                                .padding(.vertical, 3.5)
                                                .padding(.horizontal, 5)
                                                .background(
                                                    Color(hex: transaction.wrappedColour).opacity(0.23),
                                                    in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                        }
                                        .font(.app(.body, weight: .semibold))
                                        .padding(5)
                                        .background(
                                            Color.SecondaryBackground,
                                            in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 5)
                    } else {
                        dateCategoryLine
                            .disabled(isDismissDragging)
                            .padding(.bottom, 4)
                    }

                    NumberPad(
                        price: $price,
                        category: $category,
                        isEditingDecimal: $isEditingDecimal,
                        decimalValuesAssigned: $decimalValuesAssigned,
                        showingNotePicker: showingNotePicker,
                        fractionDigits: fractionDigits
                    ) {
                        submit()
                    }
                    .disabled(isDismissDragging)
                }
                .padding(.vertical, 17)
                .padding(.leading, max(17, sideOcclusion.leading))
                .padding(.trailing, max(17, sideOcclusion.trailing))
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.PrimaryBackground)
                .onTapGesture {
                    self.hideKeyboard()
                }
                .confirmationSheet(
                    isPresented: $deleteMode,
                    title: isTemplate ? "Delete Template?" : (toEdit?.isTransfer == true ? "Delete Transfer?" : "Delete Expense?"),
                    message: isTemplate ? "Transactions you've logged with it stay as they are." : (toEdit?.isTransfer == true ? "Both of its accounts lose it. This action cannot be undone." : "This action cannot be undone."),
                    onDismiss: { toDelete = nil }
                ) {
                    withAnimation {
                        if let editedTemplate {
                            dataController.deleteQuickAddTemplate(editedTemplate)
                        } else if let itemToDelete = toDelete {
                            // Deletes both legs of a transfer.
                            dataController.deleteTransaction(itemToDelete)
                        }
                    }

                    dismiss()
                }
            }
        }
        .readsVerticalBar($usesVerticalBar)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .ignoresSafeArea(.keyboard, edges: .all)
        .frame(maxHeight: .infinity)
        .background(Color.PrimaryBackground)
        .edgesIgnoringSafeArea(.all)
        .modifier(SwipeDownToDismiss(isLocked: hasUnsavedInput, isDragging: $isDismissDragging))
        .interactiveDismissDisabled(hasUnsavedInput)
        .modifier(TransactionSheetPresentation())
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: income) { newValue in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = nil
            swipingOffset = newValue ? capsuleWidth : 0
        }
        .onChange(of: isDragging) { _ in
            if !isDragging {
                if income {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        swipingOffset = capsuleWidth
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        swipingOffset = 0
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            runScreenshotStep()
            #endif

            DispatchQueue.main.async {
                if let transaction = toEdit {
                    repeatType = Int(transaction.recurringType)
                    repeatCoefficient = Int(transaction.recurringCoefficient)
                    price = transaction.wrappedAmount

                    if transaction.wrappedAmount.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 && fractionDigits > 0 {
                        isEditingDecimal = true
                        decimalValuesAssigned = AssignedDecimal(count: fractionDigits)
                    }

                    if transaction.wrappedDate > Date.now {
                        animateIcon = true
                    }
                }

                if let editedTemplate {
                    price = editedTemplate.wrappedAmount

                    if editedTemplate.wrappedAmount.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 && fractionDigits > 0 {
                        isEditingDecimal = true
                        decimalValuesAssigned = AssignedDecimal(count: fractionDigits)
                    }
                }

                #if DEBUG
                if toEdit == nil && editedTemplate == nil && ProcessInfo.processInfo.arguments.contains("-screenshotAdd") {
                    price = DemoLocale.amount(5.8)
                    note = DemoLocale.text("Oat latte")
                    category = dataController.results(for: dataController.fetchRequestForCategoriesMigration(income: false)).first { $0.name == DemoLocale.text("Coffee") }

                    if price.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 && fractionDigits > 0 {
                        isEditingDecimal = true
                        decimalValuesAssigned = AssignedDecimal(count: fractionDigits)
                    }
                }
                #endif
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryPickerSheet(category: $category, income: income, allowsNone: true)
        }
        .sheet(item: $accountPicker) { target in
            accountPickerSheet(for: target)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showPicker) {
            if #available(iOS 16.0, *) {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker
                )
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.hidden)
            } else {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            DateTimePickerSheet(date: $date)
        }
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerSheet(currencyCode: Binding(get: { transactionCurrency }, set: { selectCurrency($0) }), mainCurrency: currency)
        }
        .onChange(of: dateString) { _ in
            animateIcon = date > Date.now
        }
        .onChange(of: dynamicTypeSize) { _ in
            if income {
                swipingOffset = capsuleWidth
            }
        }
    }

    #if DEBUG
    /// `-entryKind transfer` opens on a transfer, and `-entrySheet account` opens the account picker, for screenshots.
    func runScreenshotStep() {
        let arguments = ProcessInfo.processInfo.arguments

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        if value(after: "-entryKind") == "transfer", allowsTransfer {
            kindSelection.wrappedValue = .transfer
            price = 250
        } else if arguments.contains("-entryKind") {
            price = 18.4
            note = "Groceries"
        }

        if value(after: "-entrySheet") == "account" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                accountPicker = isTransfer ? .to : .account
            }
        }
    }
    #endif

    /// Whether the edit changes what the transaction is filed under: its kind, category or accounts.
    func filingChanged(from transaction: Transaction) -> Bool {
        if isTransfer != transaction.isTransfer {
            return true
        }

        if isTransfer {
            let saved = transaction.transferAccounts
            return account != saved?.from || transferTo != saved?.to
        }

        return category != transaction.category || income != transaction.income || account != transaction.accountChoice
    }

    var hasUnsavedInput: Bool {
        if let editedTemplate {
            return price != editedTemplate.wrappedAmount
                || note != editedTemplate.wrappedNote
                || category != editedTemplate.category
                || account != editedTemplate.accountChoice
                || income != editedTemplate.income
                || !CurrencyPreferences.isSameCurrency(editedTemplate.currencyCode, as: transactionCurrency, mainCurrency: currency)
        } else if let transaction = toEdit {
            return price != transaction.wrappedAmount
                || note != transaction.wrappedNote
                || date != (transaction.date ?? date)
                || repeatType != Int(transaction.recurringType)
                || repeatCoefficient != Int(transaction.recurringCoefficient)
                || filingChanged(from: transaction)
                || !CurrencyPreferences.isSameCurrency(transaction.currencyCode, as: transactionCurrency, mainCurrency: currency)
        } else {
            return price > 0 || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func symbol(for transaction: Transaction) -> String {
        guard let code = transaction.currencyCode else {
            return currencySymbol
        }

        return Locale.current.localizedCurrencySymbol(forCurrencyCode: code) ?? code
    }

    func selectCurrency(_ code: String) {
        selectedCurrency = code

        let digits = CurrencyDigits.fractionDigits(for: code)
        price = AmountEntry.truncated(price, fractionDigits: digits)

        if decimalValuesAssigned.count > digits {
            decimalValuesAssigned = AssignedDecimal(count: digits)
        }

        if digits == 0 {
            isEditingDecimal = false
        }

        dataController.ensureLatestExchangeRates()
    }

    var dateTokenText: String {
        if isDateToday(date: date) {
            return String(format: NSLocalizedString("Today, %@", comment: ""), getTimeString(date: date))
        } else {
            return getDateString(date: date) + ", " + getTimeString(date: date)
        }
    }

    /// The date, then what the entry is filed under: a category and, with accounts, an account; or for a
    /// transfer, the two accounts. Wraps onto more lines when it doesn't fit.
    @ViewBuilder var dateCategoryLine: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    leadingToken
                    lineSeparator
                    filingTokens
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 0) {
                    leadingToken
                    HStack(spacing: 8) {
                        filingTokens
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(spacing: 0) {
                    leadingToken
                    stackedFilingTokens
                }
            }
        } else if dynamicTypeSize > .xLarge || showsAccounts {
            VStack(spacing: 0) {
                leadingToken
                stackedFilingTokens
            }
        } else {
            HStack(spacing: 8) {
                leadingToken
                lineSeparator
                categoryToken
            }
        }
    }

    /// Side by side, separated by dots.
    @ViewBuilder var filingTokens: some View {
        if isTransfer {
            transferTokens
        } else if showsAccounts {
            categoryToken
            lineSeparator
            accountToken
        } else {
            categoryToken
        }
    }

    /// One under the other, for when they don't fit side by side.
    @ViewBuilder var stackedFilingTokens: some View {
        if isTransfer {
            transferTokens
        } else {
            categoryToken
            if showsAccounts {
                accountToken
            }
        }
    }

    var accountToken: some View {
        AccountToken(name: account.name, symbol: account.symbol) {
            UIApplication.shared.endEditing()
            accountPicker = .account
        }
    }

    /// "Main → Savings", each side tappable.
    var transferTokens: some View {
        HStack(spacing: 2) {
            AccountToken(name: account.name, symbol: account.symbol, isError: account == transferTo) {
                UIApplication.shared.endEditing()
                accountPicker = .from
            }
            .accessibilityLabel(Text("From") + Text(", ") + Text(account.name))

            Image(systemName: "arrow.right")
                .font(.app(.subheadline, weight: .bold))
                .foregroundColor(Color.SubtitleText.opacity(0.6))
                .accessibilityHidden(true)

            AccountToken(name: transferTo?.name ?? String(localized: "Account"), symbol: transferTo?.symbol, isError: account == transferTo) {
                UIApplication.shared.endEditing()
                accountPicker = .to
            }
            .accessibilityLabel(Text("To") + Text(", ") + Text(transferTo?.name ?? ""))
        }
    }

    @ViewBuilder
    func accountPickerSheet(for target: AccountPickerTarget) -> some View {
        switch target {
        case .account:
            AccountPickerSheet(title: "Account", selection: Binding(get: { account }, set: { account = $0 ?? .main }))
        case .from:
            AccountPickerSheet(title: "From", selection: Binding(get: { account }, set: { account = $0 ?? .main }), unavailable: transferTo)
        case .to:
            AccountPickerSheet(title: "To", selection: $transferTo, unavailable: account)
        }
    }

    /// The date, or on a template, which has no date, a label saying it's a Quick Add template.
    @ViewBuilder var leadingToken: some View {
        if isTemplate {
            templateToken
        } else {
            dateToken
        }
    }

    var templateToken: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.app(.subheadline, weight: .semibold))

            Text("Quick Add")
                .font(.app(.body, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(Color.SubtitleText)
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    var dateToken: some View {
        Button {
            UIApplication.shared.endEditing()
            showingDatePicker = true
        } label: {
            HStack(spacing: 5) {
                if date > Date.now {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: "rays")
                                .symbolEffect(
                                    .variableColor.iterative.dimInactiveLayers.nonReversing,
                                    options: .repeating, value: animateIcon)
                        } else {
                            Image(systemName: "slowmo")
                        }
                    }
                    .font(.app(.subheadline, weight: .semibold))
                }

                Text(dateTokenText)
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(Color.SubtitleText)
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Date") + Text(", ") + Text(dateTokenText))
        .accessibilityAddTraits(.isButton)
    }

    var lineSeparator: some View {
        Text("·")
            .font(.app(.body, weight: .semibold))
            .foregroundColor(Color.SubtitleText.opacity(0.5))
            .accessibilityHidden(true)
    }

    var categoryToken: some View {
        CategoryToken(category: category, isError: false, shake: false) {
            UIApplication.shared.endEditing()
            showCategorySheet = true
        }
    }

    func isDateToday(date: Date) -> Bool {
        let calendar = Calendar.current

        return calendar.isDateInToday(date)
    }

    func getDateString(date: Date) -> String {
        let formatter = DateFormatter()

        if isDateToday(date: date) {
            formatter.dateFormat = "d MMM"

            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "E, d MMM"

            return formatter.string(from: date)
        }
    }

    func getTimeString(date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    func submit() {
        let generator = UINotificationFeedbackGenerator()

        if price == 0 {
            toastImage = "centsign.circle"
            toastTitle = "Missing Amount"
            showToast = true
            generator.notificationOccurred(.error)
            return
        }

        // What this page edits, or the category picked on it, can be deleted while the page is open,
        // most often by a change synced from another device. Linking a deleted object throws
        // "Illegal attempt to establish a relationship ... between objects in different contexts".
        let targetContext: NSManagedObjectContext?

        if let edited = editedObject {
            targetContext = edited.isDeleted ? nil : edited.managedObjectContext
        } else {
            targetContext = moc
        }

        guard let saveContext = targetContext else {
            toastImage = "trash"
            toastTitle = isTemplate ? "Template Was Deleted" : "Expense Was Deleted"
            showToast = true
            generator.notificationOccurred(.error)
            return
        }

        // An account picked here can be deleted while the page is open, most often by a change synced from
        // another device. Linking a deleted account throws "Illegal attempt to establish a relationship ...
        // between objects in different contexts", so it's flagged and put back before anything is saved.
        if account.account?.isGone == true || (isTransfer && transferTo?.account?.isGone == true) {
            if account.account?.isGone == true {
                account = .main
            }

            if transferTo?.account?.isGone == true {
                transferTo = nil
            }

            toastImage = AccountSymbol.outline
            toastTitle = "Account Was Deleted"
            showToast = true
            generator.notificationOccurred(.error)
            return
        }

        if !isTransfer, let chosen = category, chosen.isDeleted || chosen.managedObjectContext !== saveContext {
            category = nil
            toastImage = "tray"
            toastTitle = "Category Was Deleted"
            showToast = true
            generator.notificationOccurred(.error)
            return
        }

        let chosenCurrency = transactionCurrency

        if isTransfer {
            guard let destination = transferTo, destination != account else {
                toastImage = "arrow.left.arrow.right"
                toastTitle = "Pick Two Accounts"
                showToast = true
                generator.notificationOccurred(.error)
                return
            }

            generator.notificationOccurred(.success)

            let edited = toEdit
            let from = account
            let amount = price
            let transferDate = date
            let transferNote = note

            // Edits wait for the sheet to start closing, like other edits, so the list animates the change.
            DispatchQueue.main.asyncAfter(deadline: .now() + (edited == nil ? 0 : 0.3)) {
                // Sync can still delete the leg being edited during this delay.
                guard edited?.isGone != true else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.5)) {
                    _ = dataController.saveTransfer(editing: edited, from: from, to: destination, amount: amount, currencyCode: chosenCurrency, date: transferDate, note: transferNote)
                }
            }

            CurrencyPreferences.record(chosenCurrency, in: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))

            if !CurrencyPreferences.isSameCurrency(chosenCurrency, as: nil, mainCurrency: currency) {
                dataController.refreshExchangeRates()
            }

            dismiss()
            return
        }

        generator.notificationOccurred(.success)

        if let template {
            saveTemplate(template, currencyCode: chosenCurrency)
            dismiss()
            return
        }

        if let editedTransaction = toEdit {
            // A transfer edited into an expense or income keeps this leg and drops the other.
            if editedTransaction.isTransfer {
                dataController.endTransfer(keeping: editedTransaction)
            }

            editedTransaction.account = account.account

            if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                editedTransaction.note = category?.wrappedName ?? ""
            } else {
                editedTransaction.note = note.trimmingCharacters(in: .whitespaces)
            }

            // A category removed on purpose isn't put back by Apple Intelligence.
            let removedCategory = editedTransaction.category != nil && category == nil

            // Assigned even when nil, so an edit can remove the category.
            editedTransaction.category = category

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Sync can still delete it during this delay.
                guard !editedTransaction.isGone else {
                    return
                }

                var occurrences: [Transaction] = []

                withAnimation(.easeInOut(duration: 0.5)) {
                    editedTransaction.amount = price

                    if !CurrencyPreferences.isSameCurrency(editedTransaction.currencyCode, as: chosenCurrency, mainCurrency: currency) {
                        editedTransaction.currencyCode = chosenCurrency
                    }

                    editedTransaction.date = date
                    editedTransaction.income = income

                    let calendar = Calendar(identifier: .gregorian)

                    editedTransaction.day =
                    calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

                    let dateComponents = calendar.dateComponents([.month, .year], from: date)

                    editedTransaction.month = calendar.date(from: dateComponents) ?? Date.now

                    if repeatType > 0 {
                        editedTransaction.onceRecurring = true
                        editedTransaction.recurringType = Int16(repeatType)
                        editedTransaction.recurringCoefficient = Int16(repeatCoefficient)

                        dataController.updateRecurringTransaction(transaction: editedTransaction) { occurrences.append($0) }
                    } else {
                        editedTransaction.onceRecurring = false
                        editedTransaction.recurringType = Int16(repeatType)
                        editedTransaction.recurringCoefficient = Int16(repeatCoefficient)
                    }

                    dataController.save()

                    if !CurrencyPreferences.isSameCurrency(chosenCurrency, as: nil, mainCurrency: currency) {
                        dataController.refreshExchangeRates()
                    }
                }

                if !removedCategory {
                    AutoCategorizer.shared.categoriseIfNeeded([editedTransaction] + occurrences)
                }
            }

            dismiss()

            return
        }

        let transaction = Transaction(context: moc)

        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income

        if let unwrappedCategory = category {
            transaction.category = unwrappedCategory
        }

        transaction.account = account.account
        AccountPreferences.record(account)

        transaction.amount = price

        transaction.currencyCode = chosenCurrency
        CurrencyPreferences.record(chosenCurrency, in: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))

        transaction.date = date
        transaction.id = UUID()

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        // Occurrences already due, when it's backdated, which go under the same category.
        var occurrences: [Transaction] = []

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            dataController.updateRecurringTransaction(transaction: transaction) { occurrences.append($0) }
        }

        dataController.save()

        // Feature Lab: a note without a category gets one from Apple Intelligence, while its row glimmers.
        AutoCategorizer.shared.categoriseIfNeeded([transaction] + occurrences)

        if !CurrencyPreferences.isSameCurrency(chosenCurrency, as: nil, mainCurrency: currency) {
            dataController.refreshExchangeRates()
        }

        dismiss()
    }

    /// Saves the page to a Quick Add template. The note is kept as typed: a blank one shows the category's name instead.
    func saveTemplate(_ target: TemplateTarget, currencyCode: String) {
        let saved: TemplateTransaction

        switch target {
        case let .existing(existing):
            saved = existing
        case .new:
            guard dataController.canAddQuickAddTemplate else {
                return
            }

            // Worked out before inserting, or the new template counts itself.
            let order = dataController.nextQuickAddOrder
            saved = TemplateTransaction(context: moc)
            saved.id = UUID()
            saved.order = order
        }

        saved.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.amount = price
        saved.income = income
        saved.category = category
        saved.account = account.account
        saved.currencyCode = currencyCode
        saved.recurringType = 0
        saved.recurringCoefficient = 0

        CurrencyPreferences.record(currencyCode, in: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
        dataController.save()
    }

    init(toEdit: Transaction? = nil) {
        if let transaction = toEdit {
            _note = State(initialValue: transaction.wrappedNote)

            if let unwrappedCategory = transaction.category {
                _category = State(initialValue: unwrappedCategory)
            }

            if let accounts = transaction.transferAccounts {
                // A leg whose other half hasn't synced still opens with its own side filled in.
                _isTransfer = State(initialValue: true)
                _account = State(initialValue: accounts.from ?? .main)
                _transferTo = State(initialValue: accounts.to)
                _income = State(initialValue: false)
            } else {
                _account = State(initialValue: transaction.accountChoice)
                _income = State(initialValue: transaction.income)

                if transaction.income {
                    _swipingOffset = State(initialValue: 100)
                }
            }

            _date = State(initialValue: transaction.date ?? Date.now)
        } else {
            _account = State(initialValue: AccountPreferences.lastUsed(among: DataController.shared.accounts()))
        }
        self.toEdit = toEdit
        template = nil
    }

    init(category: Category? = nil) {
        if let unwrappedCategory = category {
            _income = State(initialValue: false)
            _category = State(initialValue: unwrappedCategory)
        }

        _account = State(initialValue: AccountPreferences.lastUsed(among: DataController.shared.accounts()))
        toEdit = nil
        template = nil
    }

    init(template: TemplateTarget) {
        if case let .existing(existing) = template {
            _note = State(initialValue: existing.wrappedNote)
            _category = State(initialValue: existing.category)
            _income = State(initialValue: existing.income)
            _account = State(initialValue: existing.accountChoice)

            if existing.income {
                _swipingOffset = State(initialValue: 100)
            }
        } else {
            _account = State(initialValue: AccountPreferences.lastUsed(among: DataController.shared.accounts()))
        }

        toEdit = nil
        self.template = template
    }

    @ViewBuilder
    private func sideBarNavigation<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 16.0, *), usesVerticalBar {
            NavigationStack {
                content()
                    .ignoresSafeArea(.container, edges: .vertical)
                    // The page's own keyboard setting doesn't reach inside the stack, so repeat it here.
                    // Without this the page shrinks for the note keyboard instead of letting it cover the number pad.
                    .ignoresSafeArea(.keyboard, edges: .all)
                    .toolbar { sideBarItems }
            }
            .ignoresSafeArea(.keyboard, edges: .all)
        } else {
            content()
        }
    }

    @available(iOS 16.0, *)
    @ToolbarContentBuilder
    private var sideBarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isTemplate {
                RecurringToolbarMenu(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient,
                    showPicker: $showPicker, accessibilityLabel: repeatButtonAccessibility)
            }

            if isEditing {
                Button(role: .destructive) {
                    toDelete = toEdit
                    deleteMode = true
                } label: {
                    Label("delete transaction", systemImage: "trash.fill")
                }
                .tint(Color.AlertRed)
            }
        }
    }
}

struct FilteredSearchNewTransactionView: View {
    @FetchRequest<Transaction> private var transactions: FetchedResults<Transaction>

    var searchQuery: String
    var category: Category?

    var body: some View {
        ScrollView(.horizontal) {
            if transactions.count > 0 && category != nil {
                HStack {
                    ForEach(filterOutDupes(day: transactions)) { transaction in
                        Text(transaction.wrappedNote)
                    }
                }
            }
        }
    }

    init(searchQuery: String, category: Category?) {
        let beginPredicate = NSPredicate(
            format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(
            format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [
            beginPredicate, containPredicate
        ])

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(
                format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(
                type: .and, subpredicates: [compound, categoryPredicate, TransferPredicate.excluded])

            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: andPredicate)
        } else {
            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: TransferPredicate.excluding(compound))
        }

        self.searchQuery = searchQuery
        self.category = category
    }

    func filterOutDupes(day: FetchedResults<Transaction>) -> [Transaction] {
        var seen = [Transaction]()
        let filtered = day.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
    }
}

struct NumPadButton: ButtonStyle {
    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.3), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct NoteView: View {
    @Binding var note: String
    @Binding var focused: Bool

    @FocusState private var textFocused: Bool
    let characterLimit = 50

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.alignleft")
                .font(.app(.subheadline, weight: .medium))
                .foregroundColor(Color.SubtitleText.opacity(0.6))
                .accessibilityHidden(true)

            // The invisible text sizes the field to its content so the icon and field stay centred as one group,
            // and the caret starts exactly where the prompt begins.
            Text(note.isEmpty ? String(localized: "Note") : note)
                .lineLimit(1)
                .padding(.trailing, 2)
                .opacity(0)
                .accessibilityHidden(true)
                .overlay(alignment: .leading) {
                    TextField("Note", text: $note, prompt: Text("Note").foregroundColor(Color.SubtitleText.opacity(0.6)))
                        .onReceive(Just(note)) { _ in limitText(characterLimit) }
                        .focused($textFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            textFocused = false
                        }
                        .foregroundColor(Color.PrimaryText)
                        .accessibilityLabel(Text("Note"))
                }
        }
        .font(.app(.body, weight: .medium))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: UIScreen.main.bounds.width / 1.5)
        .padding(.horizontal, 44)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            textFocused = true
        }
        .onChange(of: textFocused) { newValue in
            focused = newValue
        }
    }

    func limitText(_ upper: Int) {
        if note.count > upper {
            note = String(note.prefix(upper))
        }
    }
}

private struct RecurringToolbarMenu: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool
    let accessibilityLabel: String

    private let presetKeys = ["none", "daily", "weekly", "monthly"]

    private var preset: Binding<Int?> {
        Binding {
            repeatType == 0 || repeatCoefficient == 1 ? repeatType : nil
        } set: { index in
            guard let index else { return }
            repeatType = index
            repeatCoefficient = 1
        }
    }

    var body: some View {
        Menu {
            Picker(selection: preset) {
                ForEach(presetKeys.indices, id: \.self) { index in
                    Text(NSLocalizedString(presetKeys[index], comment: "").localizedCapitalized)
                        .tag(Optional(index))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)

            Button {
                showPicker = true
            } label: {
                Text(NSLocalizedString("custom", comment: "").localizedCapitalized)
            }
        } label: {
            Label("Repeat", systemImage: "repeat")
        }
        .tint(repeatType > 0 ? Color.IncomeGreen : Color.PrimaryText)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Expense, Income or Transfer as a menu, like the repeat menu, so the top bar stays uncluttered.
private struct EntryKindMenu: View {
    @Binding var selection: TransactionView.EntryKind
    let options: [(value: TransactionView.EntryKind, title: LocalizedStringKey)]

    @State private var showMenu = false

    var selectedTitle: LocalizedStringKey {
        options.first { $0.value == selection }?.title ?? "Expense"
    }

    var body: some View {
        GlassCapsuleButton(selectedTitle, trailingSystemImage: "chevron.up.chevron.down", font: .app(.body, weight: .semibold)) {
            showMenu = true
        }
        .accessibilityLabel(Text("Type") + Text(", ") + Text(selectedTitle))
        .popover(present: $showMenu, attributes: {
            $0.position = .absolute(
                originAnchor: .bottom,
                popoverAnchor: .top
            )
            $0.rubberBandingMode = .none
            $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
            $0.presentation.animation = .easeInOut(duration: 0.2)
            $0.dismissal.animation = .easeInOut(duration: 0.3)
        }) {
            GlassPopoverMenu {
                ForEach(options.indices, id: \.self) { index in
                    GlassPopoverRow(options[index].title, isSelected: options[index].value == selection) {
                        if options[index].value != selection {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = options[index].value
                            }
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showMenu = false
                        }
                    }
                }
            }
        }
    }
}

struct RecurringMenu: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool
    let accessibilityLabel: String

    @State private var showRecurring = false

    let presetKeys = ["none", "daily", "weekly", "monthly"]

    var customDetail: LocalizedStringKey? {
        guard repeatCoefficient > 1 else { return nil }

        let unit: String
        switch repeatType {
        case 1:
            unit = String(localized: "\(repeatCoefficient) days")
        case 2:
            unit = String(localized: "\(repeatCoefficient) weeks")
        case 3:
            unit = String(localized: "\(repeatCoefficient) months")
        default:
            unit = ""
        }

        let detail = "\(repeatCoefficient) \(unit)"
        return LocalizedStringKey(detail)
    }

    func isPresetSelected(_ index: Int) -> Bool {
        index == 0 ? repeatType == 0 : repeatType == index && repeatCoefficient == 1
    }

    var body: some View {
        Button {
            showRecurring = true
        } label: {
            Image(systemName: "repeat")
                .font(.app(.body, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundColor(repeatType > 0 ? Color.IncomeGreen : Color.PrimaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(
            in: Circle(),
            tint: repeatType > 0 ? Color.IncomeGreen.opacity(0.2) : Color.glassTint,
            fallback: repeatType > 0 ? Color.IncomeGreen.opacity(0.23) : Color.SecondaryBackground
        )
        .accessibilityLabel(accessibilityLabel)
        .popover(present: $showRecurring, attributes: {
            $0.position = .absolute(
                originAnchor: .bottomRight,
                popoverAnchor: .topRight
            )
            $0.rubberBandingMode = .none
            $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
            $0.presentation.animation = .easeInOut(duration: 0.2)
            $0.dismissal.animation = .easeInOut(duration: 0.3)
        }) {
            GlassPopoverMenu {
                ForEach(presetKeys.indices, id: \.self) { index in
                    GlassPopoverRow(
                        LocalizedStringKey(NSLocalizedString(presetKeys[index], comment: "").localizedCapitalized),
                        isSelected: isPresetSelected(index)
                    ) {
                        selectPreset(index)
                    }
                }

                GlassPopoverRow(
                    LocalizedStringKey(NSLocalizedString("custom", comment: "").localizedCapitalized),
                    detail: customDetail,
                    isSelected: repeatType > 0 && repeatCoefficient > 1
                ) {
                    showRecurring = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPicker = true
                    }
                }
            }
        }
    }

    func selectPreset(_ index: Int) {
        if isPresetSelected(index) {
            showRecurring = false
            return
        }

        withAnimation(.easeIn(duration: 0.15)) {
            repeatType = index
            repeatCoefficient = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showRecurring = false
        }
    }
}

struct CustomRecurringView: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool

    @Environment(\.dismiss) var dismiss

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }
                .hiddenInSideBar()

                Spacer()

                GlassIconButton(
                    systemName: "checkmark",
                    accessibilityLabel: "Save",
                    foreground: Color.LightIcon,
                    tint: Color.DarkBackground,
                    fallback: Color.DarkBackground,
                    action: save
                )
                .hiddenInSideBar()
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: "Custom Interval")
            }

            Text("Repeats every")
                .font(.app(.body, weight: .medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                CustomRecurringStepper(
                    decrementImage: "minus",
                    decrementLabel: "Decrease interval",
                    canDecrement: holdingCoefficient > 2,
                    incrementImage: "plus",
                    incrementLabel: "Increase interval",
                    canIncrement: holdingCoefficient < 30,
                    decrement: { holdingCoefficient -= 1 },
                    increment: { holdingCoefficient += 1 }
                ) {
                    Text("\(holdingCoefficient)")
                        .font(.app(.title2, weight: .semibold))
                        .monospacedDigit()
                }

                CustomRecurringStepper(
                    decrementImage: "chevron.left",
                    decrementLabel: "Previous unit",
                    canDecrement: holdingType > 1,
                    incrementImage: "chevron.right",
                    incrementLabel: "Next unit",
                    canIncrement: holdingType < 3,
                    decrement: { holdingType -= 1 },
                    increment: { holdingType += 1 }
                ) {
                    Group {
                        if holdingType == 1 {
                            Text("\(holdingCoefficient) days")
                        } else if holdingType == 2 {
                            Text("\(holdingCoefficient) weeks")
                        } else if holdingType == 3 {
                            Text("\(holdingCoefficient) months")
                        }
                    }
                    .font(.app(.title3, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetBackground()
        .onAppear {
            if repeatCoefficient > 1 {
                holdingType = repeatType
                holdingCoefficient = repeatCoefficient
            } else {
                holdingType = 2
                holdingCoefficient = 2
            }
        }
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
            SideBarConfirmItem(title: "Save", action: save)
        }
    }

    func save() {
        repeatType = holdingType
        repeatCoefficient = holdingCoefficient

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        dismiss()
    }
}

struct DateTimePickerSheet: View {
    @Binding var date: Date

    @Environment(\.dismiss) var dismiss
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    @available(iOS 16.0, *)
    var detents: Set<PresentationDetent> {
        if contentHeight == 0 {
            return [.height(480)]
        } else if contentHeight > UIScreen.main.bounds.height * 0.9 {
            return [.large]
        } else {
            return [.height(contentHeight)]
        }
    }

    var content: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }
                .hiddenInSideBar()

                Spacer()

                GlassIconButton(
                    systemName: "checkmark",
                    accessibilityLabel: "Done",
                    foreground: Color.LightIcon,
                    tint: Color.DarkBackground,
                    fallback: Color.DarkBackground
                ) {
                    dismiss()
                }
                .hiddenInSideBar()
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: "Date & Time")
            }

            GlassDatePicker(selection: $date, showsTime: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(SheetContentHeightKey.self) { height in
            contentHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetBackground()
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
            SideBarConfirmItem(title: "Done") { dismiss() }
        }
    }
}

struct TransactionSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.PrimaryBackground)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}

struct SwipeDownToDismiss: ViewModifier {
    let isLocked: Bool
    @Binding var isDragging: Bool

    @Environment(\.dismiss) private var dismiss
    @GestureState private var isSwipingDown = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .updating($isSwipingDown) { value, state, _ in
                        if !state {
                            state = isDownwardSwipe(value.translation)
                        }
                    }
                    .onEnded { value in
                        let passedThreshold = value.translation.height > 100 || value.predictedEndTranslation.height > 200

                        if !isLocked && isDownwardSwipe(value.translation) && passedThreshold {
                            dismiss()
                        }
                    }
            )
            .onChange(of: isSwipingDown) { swiping in
                if swiping {
                    isDragging = true
                } else {
                    DispatchQueue.main.async {
                        isDragging = false
                    }
                }
            }
    }

    private func isDownwardSwipe(_ translation: CGSize) -> Bool {
        translation.height > 0 && translation.height > abs(translation.width) * 1.5
    }
}

struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CustomRecurringStepper<Value: View>: View {
    let decrementImage: String
    let decrementLabel: LocalizedStringKey
    let canDecrement: Bool
    let incrementImage: String
    let incrementLabel: LocalizedStringKey
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: decrementImage, label: decrementLabel, enabled: canDecrement, action: decrement)

            value()
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            stepButton(systemName: incrementImage, label: incrementLabel, enabled: canIncrement, action: increment)
        }
        .padding(.horizontal, 3)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .glassField(in: Capsule(), isFocused: false)
    }

    func stepButton(systemName: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.app(.body, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.PrimaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

struct ButtonView: View {
    let number: Int
    let size: CGSize

    var body: some View {
        Text("\(number)")
            .font(.app(size: 34, weight: .regular))
            .frame(width: size.width * 0.3, height: size.height * 0.22)
            .background(Color.SecondaryBackground)
            .foregroundColor(Color.PrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
