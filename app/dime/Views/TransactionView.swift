//
//  TransactionView.swift
//  xpenz
//
//  Created by Rafael Soh on 14/5/22.
//

import Combine
import Foundation
import Popovers
import SwiftUI

struct TransactionView: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
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

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @State var showingDatePicker = false

    // toasts
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // shaking category error
    @State var categoryError = false
    @State var shake: Bool = false

    @ObservedObject var keyboardHeightHelper = KeyboardHeightHelper()

    @AppStorage(
        "firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var firstLaunch: Bool = true

    // edit mode
    let toEdit: Transaction?

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    var showsIncomeControls: Bool {
        incomeTracking || toEdit?.income == true
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        return dateFormatter.string(from: date)
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
        return note != "" && toEdit == nil && !suggestedTransactions.isEmpty && textFieldFocused
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

                            RecurringMenu(
                                repeatType: $repeatType, repeatCoefficient: $repeatCoefficient,
                                showPicker: $showPicker, accessibilityLabel: repeatButtonAccessibility)
                        }
                    }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if showToast {
                            GlassToast(title: toastTitle, systemImage: toastImage, color: Color.AlertRed)
                        } else if showsIncomeControls {
                            GlassSegmentedPicker(selection: $income, options: [
                                (value: false, title: "Expense"),
                                (value: true, title: "transaction-view-income-picker")
                            ])
                        } else {
                            CategoryEditorTitle(title: "Expense")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if toEdit != nil && !usesVerticalBar {
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

                                        guard showsIncomeControls, abs(swipe) > abs(gesture.translation.height) else { return }

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
                            NumberPadTextView(price: $price, isEditingDecimal: $isEditingDecimal, decimalValuesAssigned: $decimalValuesAssigned)
                            NoteView(note: $note, focused: $textFieldFocused)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showingNotePicker {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedTransactions, id: \.self) { transaction in
                                    Button {
                                        note = transaction.wrappedNote
                                        withAnimation {
                                            if price == 0 {
                                                price = transaction.wrappedAmount
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

                                            Text("\(currencySymbol)\(Int(round(transaction.wrappedAmount)))")
                                                .lineLimit(1)
                                                .foregroundStyle(Color(hex: transaction.wrappedColour))
                                                .padding(.vertical, 3.5)
                                                .padding(.horizontal, 5)
                                                .background(
                                                    Color(hex: transaction.wrappedColour).opacity(0.23),
                                                    in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                        }
                                        .font(.system(.body, design: .rounded).weight(.semibold))
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
                        showingNotePicker: showingNotePicker
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
                    title: "Delete Expense?",
                    message: "This action cannot be undone.",
                    onDismiss: { toDelete = nil }
                ) {
                    withAnimation {
                        if let itemToDelete = toDelete {
                            moc.delete(itemToDelete)
                        }
                        dataController.save()
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
            DispatchQueue.main.async {
                if let transaction = toEdit {
                    repeatType = Int(transaction.recurringType)
                    repeatCoefficient = Int(transaction.recurringCoefficient)
                    price = transaction.wrappedAmount

                    if transaction.wrappedAmount.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 {
                        isEditingDecimal = true
                        decimalValuesAssigned = .second
                    }

                    if transaction.wrappedDate > Date.now {
                        animateIcon = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryPickerSheet(category: $category, income: income)
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
        .onChange(of: dateString) { _ in
            animateIcon = date > Date.now
        }
        .onChange(of: dynamicTypeSize) { _ in
            if income {
                swipingOffset = capsuleWidth
            }
        }
    }

    var hasUnsavedInput: Bool {
        if let transaction = toEdit {
            return price != transaction.wrappedAmount
                || note != transaction.wrappedNote
                || category != transaction.category
                || income != transaction.income
                || date != (transaction.date ?? date)
                || repeatType != Int(transaction.recurringType)
                || repeatCoefficient != Int(transaction.recurringCoefficient)
        } else {
            return price > 0 || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var dateTokenText: String {
        if isDateToday(date: date) {
            return String(format: NSLocalizedString("Today, %@", comment: ""), getTimeString(date: date))
        } else {
            return getDateString(date: date) + ", " + getTimeString(date: date)
        }
    }

    @ViewBuilder var dateCategoryLine: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    dateToken
                    lineSeparator
                    categoryToken
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 0) {
                    dateToken
                    categoryToken
                }
            }
        } else if dynamicTypeSize > .xLarge {
            VStack(spacing: 0) {
                dateToken
                categoryToken
            }
        } else {
            HStack(spacing: 8) {
                dateToken
                lineSeparator
                categoryToken
            }
        }
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
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }

                Text(dateTokenText)
                    .font(.system(.body, design: .rounded).weight(.semibold))
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
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(Color.SubtitleText.opacity(0.5))
            .accessibilityHidden(true)
    }

    var categoryToken: some View {
        CategoryToken(category: category, isError: categoryError, shake: shake) {
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

    func toggleFieldColors() {
        if categoryError {
            withAnimation(.linear) {
                categoryError = false
            }
        } else {
            withAnimation(.easeOut(duration: 1.0)) {
                categoryError = true
            }
            withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    shake = false
                }
                withAnimation(.easeOut(duration: 0.6)) {
                    categoryError = false
                }
            }
        }
    }

    func submit() {
        let generator = UINotificationFeedbackGenerator()

        if price == 0 && category == nil {
            toastImage = "questionmark.app"
            toastTitle = "Incomplete Entry"
            showToast = true
            toggleFieldColors()

            generator.notificationOccurred(.error)

            return
        } else if price == 0 {
            toastImage = "centsign.circle"
            toastTitle = "Missing Amount"
            showToast = true
            generator.notificationOccurred(.error)
            return
        } else if category == nil {
            toastImage = "tray"
            toastTitle = "Missing Category"
            showToast = true

            toggleFieldColors()

            generator.notificationOccurred(.error)
            return
        }

        generator.notificationOccurred(.success)

        if let editedTransaction = toEdit {
            if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                editedTransaction.note = category!.wrappedName
            } else {
                editedTransaction.note = note.trimmingCharacters(in: .whitespaces)
            }

            if let unwrappedCategory = category {
                editedTransaction.category = unwrappedCategory
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    editedTransaction.amount = price
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

                        dataController.updateRecurringTransaction(transaction: editedTransaction)
                    } else {
                        editedTransaction.onceRecurring = false
                        editedTransaction.recurringType = Int16(repeatType)
                        editedTransaction.recurringCoefficient = Int16(repeatCoefficient)
                    }

                    dataController.save()
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

        transaction.amount = price
        transaction.date = date
        transaction.id = UUID()

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            dataController.updateRecurringTransaction(transaction: transaction)
        }

        dataController.save()

        dismiss()
    }

    init(toEdit: Transaction? = nil) {
        if let transaction = toEdit {
            _note = State(initialValue: transaction.wrappedNote)

            if let unwrappedCategory = transaction.category {
                _category = State(initialValue: unwrappedCategory)
            }

            _income = State(initialValue: transaction.income)

            if transaction.income {
                _swipingOffset = State(initialValue: 100)
            }

            _date = State(initialValue: transaction.date ?? Date.now)
        }
        self.toEdit = toEdit
    }

    init(category: Category? = nil) {
        if let unwrappedCategory = category {
            _income = State(initialValue: false)
            _category = State(initialValue: unwrappedCategory)
        }

        toEdit = nil
    }

    @ViewBuilder
    private func sideBarNavigation<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 16.0, *), usesVerticalBar {
            NavigationStack {
                content()
                    .ignoresSafeArea(.container, edges: .vertical)
                    .toolbar { sideBarItems }
            }
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
            RecurringToolbarMenu(
                repeatType: $repeatType, repeatCoefficient: $repeatCoefficient,
                showPicker: $showPicker, accessibilityLabel: repeatButtonAccessibility)

            if toEdit != nil {
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
                type: .and, subpredicates: [compound, categoryPredicate])

            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: andPredicate)
        } else {
            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: compound)
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
                .font(.system(.subheadline, design: .rounded).weight(.medium))
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
        .font(.system(.body, design: .rounded).weight(.medium))
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
                .font(.system(.body, design: .rounded).weight(.semibold))
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

                Spacer()

                GlassIconButton(
                    systemName: "checkmark",
                    accessibilityLabel: "Save",
                    foreground: Color.LightIcon,
                    tint: Color.DarkBackground,
                    fallback: Color.DarkBackground
                ) {
                    repeatType = holdingType
                    repeatCoefficient = holdingCoefficient

                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    dismiss()
                }
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: "Custom Interval")
            }

            Text("Repeats every")
                .font(.system(.body, design: .rounded).weight(.medium))
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
                        .font(.system(.title2, design: .rounded).weight(.semibold))
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
                    .font(.system(.title3, design: .rounded).weight(.semibold))
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
                .font(.system(.body, design: .rounded).weight(.semibold))
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
            .font(.system(size: 34, weight: .regular, design: .rounded))
            .frame(width: size.width * 0.3, height: size.height * 0.22)
            .background(Color.SecondaryBackground)
            .foregroundColor(Color.PrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
