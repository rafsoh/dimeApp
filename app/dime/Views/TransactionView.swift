//
//  TransactionView.swift
//  xpenz
//
//  Created by Rafael Soh on 14/5/22.
//

import Combine
import Foundation
import SwiftUI

struct TransactionView: View {
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "income = %d", false)) private
    var expenseCategories: FetchedResults<Category>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "income = %d", true)) private
    var incomeCategories: FetchedResults<Category>

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss

    @Environment(\.colorScheme) var colorScheme
    var boldText: Bool {
        UIAccessibility.isBoldTextEnabled
    }

    @AppStorage("topEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var topEdge:
    Double = 20

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

    @State var showCategoryPicker = false
    @State var showCategorySheet = false

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @State var showingDatePicker = false
    @State var showingCategoryView = false

    // toasts
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // shaking category error
    @State var categoryButtonTextColor = Color.SubtitleText
    @State var categoryButtonBackgroundColor = Color.clear
    @State var categoryButtonOutlineColor = Color.Outline
    @State var shake: Bool = false

    @ObservedObject var keyboardHeightHelper = KeyboardHeightHelper()

    @AppStorage(
        "firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var firstLaunch: Bool = true

    // edit mode
    let toEdit: Transaction?

    // delete mode

    @State var toDelete: Transaction?
    @State var deleteMode = false

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    let repeatOverlays = ["D", "W", "M"]
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

    var showTime: Bool {
        let roundedFont = UIFont.rounded(ofSize: fontSize, weight: .semibold)

        let attributes = [NSAttributedString.Key.font: roundedFont]

        let dateSize: CGSize

        if isDateToday(date: date) {
            dateSize = (("Today, " + getDateString(date: date)) as NSString).size(
                withAttributes: attributes)
        } else {
            dateSize = (getDateString(date: date) as NSString).size(withAttributes: attributes)
        }

        let categorySize = (category?.fullName ?? "X Category").size(withAttributes: attributes)
        let timeSize = (getTimeString(date: date) as NSString).size(withAttributes: attributes)

        let screenWidth: CGFloat

        if boldText {
            screenWidth = (UIScreen.main.bounds.width - 200)
        } else {
            screenWidth = (UIScreen.main.bounds.width - 150)
        }

        if (dateSize.width + categorySize.width + timeSize.width) > screenWidth {
            return false
        } else {
            return true
        }
    }

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var backgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkBackground")
        } else {
            return Color("AlwaysLightBackground")
        }
    }

    @State var showPicker = false
    @State var animateIcon = false

    @Namespace var animation

    @State var swipingOffset: CGFloat = 0
    @GestureState var isDragging = false

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

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 14
        case .small:
            return 15
        case .medium:
            return 16
        case .large:
            return 17
        case .xLarge:
            return 19
        case .xxLarge:
            return 21
        case .xxxLarge:
            return 23
        default:
            return 23
        }
    }

    var widthOfCategoryButton: CGFloat {
        let fontSize = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)

        return "Category".widthOfRoundedString(size: fontSize, weight: .semibold) + 50
    }

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

    // foreign currency entry
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var homeCurrency: String = Locale.current.currencyCode ?? "USD"
    @State private var tags: [String] = []
    @State private var tagSuggestions: [String] = []
    @State private var entryCurrency: String?
    @State private var exchangeRate: Double?
    @State private var fetchingRate = false
    @State private var showCurrencyPicker = false
    @State private var showManualRate = false
    @State private var manualRateText = ""

    private var isForeignEntry: Bool {
        if let entryCurrency {
            return entryCurrency != homeCurrency
        }
        return false
    }

    private var convertedPrice: Double? {
        guard isForeignEntry, let exchangeRate else { return nil }
        return ExchangeRates.convert(price, rate: exchangeRate, to: homeCurrency)
    }

    private func loadRate() {
        guard isForeignEntry, let from = entryCurrency else {
            exchangeRate = nil
            return
        }
        let to = homeCurrency
        // keep the stored (historic or manual) rate when opening an edit
        if let edited = toEdit, edited.originalCurrency == from, edited.exchangeRate > 0 {
            exchangeRate = edited.exchangeRate
            return
        }
        exchangeRate = ExchangeRates.cachedRate(from: from, to: to)
        fetchingRate = true
        Task {
            let fresh = try? await ExchangeRates.fetchRate(from: from, to: to, on: date)
            await MainActor.run {
                if entryCurrency == from, let fresh {
                    exchangeRate = fresh
                }
                fetchingRate = false
            }
        }
    }

    @ViewBuilder
    private var currencyChip: some View {
        Menu {
            Button {
                entryCurrency = nil
            } label: {
                Text(homeCurrency)
            }
            ForEach(ExchangeRates.recentCurrencies.filter { $0 != homeCurrency }, id: \.self) { code in
                Button {
                    entryCurrency = code
                } label: {
                    Text(code)
                }
            }
            Divider()
            Button {
                showCurrencyPicker = true
            } label: {
                Text("Other Currency")
            }
            if isForeignEntry {
                Button {
                    manualRateText = exchangeRate.map { String($0) } ?? ""
                    showManualRate = true
                } label: {
                    Text("Set Exchange Rate")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(entryCurrency ?? homeCurrency)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(Color.SubtitleText)

                if isForeignEntry {
                    Group {
                        if let convertedPrice {
                            Text("≈ \(convertedPrice.formatted(.currency(code: homeCurrency)))")
                        } else if fetchingRate {
                            Text("Fetching rate…")
                        } else {
                            Text("No exchange rate")
                        }
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Color.SecondaryBackground, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(entryCurrency ?? homeCurrency))
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                // income/expense picker
                VStack {
                    if showToast {
                        HStack(spacing: 6.5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(Color.AlertRed)

                            Text(toastTitle)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                                .foregroundColor(Color.AlertRed)
                        }
                        .padding(8)
                        .dimeGlass(
                            RoundedRectangle(cornerRadius: 9, style: .continuous),
                            fallback: Color.AlertRed.opacity(0.23),
                            tint: Color.AlertRed.opacity(0.18)
                        )
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: dynamicTypeSize > .xLarge ? 250 : 200)
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.SecondaryBackground)
                                .frame(width: capsuleWidth)
                                .offset(x: swipingOffset)

                            HStack(spacing: 0) {
                                Text("Expense")
                                    .font(.system(.body, design: .rounded).weight(.semibold))

                                    .lineLimit(1)
                                    .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                                    .padding(6)
                                    .frame(width: capsuleWidth)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        DispatchQueue.main.async {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                income = false
                                                swipingOffset = 0
                                            }
                                        }
                                    }

                                Text("transaction-view-income-picker")
                                    .font(.system(.body, design: .rounded).weight(.semibold))

                                    .lineLimit(1)
                                    .foregroundColor(income == true ? Color.PrimaryText : Color.SubtitleText)
                                    .padding(6)
                                    .frame(width: capsuleWidth)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        DispatchQueue.main.async {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                income = true
                                                swipingOffset = capsuleWidth
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(3)
                        .fixedSize(horizontal: true, vertical: true)
                        .overlay(Capsule().stroke(Color.Outline.opacity(0.4), lineWidth: 1.3))
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                .foregroundColor(Color.SubtitleText)
                                .padding(7)
                                .background(Color.SecondaryBackground, in: Circle())
                                .contentShape(Circle())
                        }

                        Spacer()

                        if toEdit != nil {
                            Button {
                                toDelete = toEdit
                                deleteMode = true
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                    .foregroundColor(Color.AlertRed)
                                    .padding(7)
                                    .background(Color.AlertRed.opacity(0.23), in: Circle())
                                    .contentShape(Circle())
                            }
                            .accessibilityLabel("delete transaction")
                        }

                        Menu {
                            RecurringMenuItems(repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
                        } label: {
                            if repeatType > 0 {
                                Image(systemName: "repeat")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                    .overlay(alignment: .topTrailing) {
                                        Text(repeatOverlays[repeatType - 1])
                                            .font(.system(size: 6, weight: .black, design: .rounded))
                                            .foregroundColor(Color.IncomeGreen)
                                            .frame(width: 10, alignment: .leading)
                                            .offset(x: 5.7, y: 1.5)
                                    }
                                    .foregroundColor(Color.IncomeGreen)
                                    .padding(7)
                                    .background(Color.IncomeGreen.opacity(0.23), in: Circle())
                                    .contentShape(Circle())
                            } else {
                                Image(systemName: "repeat")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.SubtitleText)
                                    .padding(7)
                                    .background(Color.SecondaryBackground, in: Circle())
                                    .contentShape(Circle())
                            }
                        }
                        .accessibilityLabel(repeatButtonAccessibility)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, topEdge)

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
                        NumberPadTextView(price: $price, isEditingDecimal: $isEditingDecimal, decimalValuesAssigned: $decimalValuesAssigned, entryCurrency: isForeignEntry ? entryCurrency : nil)
                        currencyChip
                        NoteView(note: $note, focused: $textFieldFocused)
                        TagsRow(tags: $tags, suggestions: tagSuggestions)
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
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Group {
                                if date < Date.now {
                                    Image(systemName: "calendar")
                                } else {
                                    if #available(iOS 17.0, *) {
                                        Image(systemName: "rays")
                                            .symbolEffect(
                                                .variableColor.iterative.dimInactiveLayers.nonReversing,
                                                options: .repeating, value: animateIcon)
                                    } else {
                                        Image(systemName: "slowmo")
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                }
                            }
                            .foregroundColor(Color.SubtitleText)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))

                            Group {
                                if isDateToday(date: date) {
                                    Text("Today, \(getDateString(date: date))")
                                        .lineLimit(1)
                                } else {
                                    Text(getDateString(date: date))
                                        .lineLimit(1)
                                }
                            }
                            .font(.system(.body, design: .rounded).weight(.semibold))

                            if showTime {
                                Spacer()

                                Text(getTimeString(date: date))
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                        .foregroundColor(Color.PrimaryText)
                        .padding(.vertical, 8.5)
                        .padding(.horizontal, 10)
                        .animation(.default, value: isDateToday(date: date))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                .strokeBorder(Color.Outline, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.endEditing()
                            showingDatePicker = true
                        }

                        if (expenseCategories.count == 0 && !income) || (incomeCategories.count == 0 && income) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))

                                Text("Category")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8.5)
                            .padding(.horizontal, 10)
                            .foregroundColor(categoryButtonTextColor)
                            .background(
                                categoryButtonBackgroundColor,
                                in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    .strokeBorder(categoryButtonOutlineColor, lineWidth: 1.5)
                            )
                            .drawingGroup()
                            .offset(x: shake ? -5 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showCategorySheet = true
                            }
                        } else {
                            Group {
                                if showCategoryPicker {
                                    HStack(spacing: 10) {
                                        Text("Close")
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 8.5)
                                    .padding(.horizontal, 10)
                                    .frame(width: widthOfCategoryButton)
                                    .foregroundColor(Color.AlertRed)
                                    .background(Color.AlertRed.opacity(0.23),
                                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    )
                                } else {
                                    if let unwrappedCategory = category {
                                        HStack(spacing: 5) {
                                            CategoryIcon(unwrappedCategory.wrappedIcon)
                                                .font(.system(.footnote, design: .rounded).weight(.semibold))

                                            Text(unwrappedCategory.wrappedName)
                                                .font(.system(.body, design: .rounded).weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, 8.5)
                                        .padding(.horizontal, 10)
                                        .foregroundColor(Color(hex: unwrappedCategory.wrappedColour))
                                        .background(
                                            Color(hex: unwrappedCategory.wrappedColour).opacity(0.35),
                                            in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                        )
                                    } else {
                                        HStack(spacing: 5.5) {
                                            if #available(iOS 17.0, *) {
                                                Image(systemName: "circle.grid.2x2")
                                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                                    .symbolEffect(
                                                        .bounce.up.byLayer, options: .repeating.speed(0.5),
                                                        value: showCategoryPicker)
                                            } else {
                                                Image(systemName: "circle.grid.2x2")
                                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            }

                                            Text("Category")
                                                .font(.system(.body, design: .rounded).weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, 8.5)
                                        .padding(.horizontal, 10)
                                        .frame(width: widthOfCategoryButton)
                                        .foregroundColor(categoryButtonTextColor)
                                        .background(
                                            categoryButtonBackgroundColor,
                                            in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                                .strokeBorder(categoryButtonOutlineColor, lineWidth: 1.5)
                                        )
                                        .drawingGroup()
                                        .offset(x: shake ? -5 : 0)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut) {
                                    showCategoryPicker.toggle()
                                }
                            }
                        }
                    }
                    .padding(.bottom, 5)
                }

                // date and category picker

                if showCategoryPicker {
                    NewCategoryPickerView(
                        category: $category, showPicker: $showCategoryPicker,
                        showSheet: $showCategorySheet, income: income
                    )
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                } else {
                    NumberPad(
                        price: $price,
                        category: $category,
                        isEditingDecimal: $isEditingDecimal,
                        decimalValuesAssigned: $decimalValuesAssigned,
                        showingNotePicker: showingNotePicker,
                        entryCurrency: isForeignEntry ? entryCurrency : nil
                    ) {
                        submit()
                    }
                    .transition(AnyTransition.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(17)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.PrimaryBackground)
            .onTapGesture {
                self.hideKeyboard()
            }
            .fullScreenCover(isPresented: $deleteMode) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            deleteMode = false
                            toDelete = nil
                        }

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("Delete Expense?")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.PrimaryText)

                        Text("This action cannot be undone.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.SubtitleText)
                            .padding(.bottom, 15)

                        Button {
                            deleteMode = false

                            withAnimation {
                                if let itemToDelete = toDelete {
                                    moc.delete(itemToDelete)
                                }
                                dataController.save()
                            }

                            dismiss()
                        } label: {
                            Text("Delete")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: 45)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .padding(.bottom, 8)

                        Button {
                            withAnimation(.easeOut(duration: 0.7)) {
                                deleteMode = false
                                toDelete = nil
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.PrimaryText.opacity(0.9))
                                .frame(height: 45)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color.SecondaryBackground,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(13)
                    .background(
                        RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(
                            color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13).stroke(
                            systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3)
                    )
                    .offset(y: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if gesture.translation.height < 0 {
                                    offset = gesture.translation.height / 3
                                } else {
                                    offset = gesture.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 20 {
                                    deleteMode = false
                                    toDelete = nil
                                } else {
                                    withAnimation {
                                        offset = 0
                                    }
                                }
                            }
                    )
                    .padding(.horizontal, 17)
                    .padding(.bottom, bottomEdge == 0 ? 12 : bottomEdge - 3)
                }
                .edgesIgnoringSafeArea(.all)
                .background(BackgroundBlurView())
            }
            .overlay {
                ZStack(alignment: .bottom) {
                    GeometryReader { _ in
                        EmptyView()
                    }
                    .background(Color.black)
                    .opacity(showingDatePicker ? 0.3 : 0)
                    .onTapGesture {
                        showingDatePicker = false
                    }

                    VStack(spacing: 4) {
                        DatePicker("Date", selection: $date)
                            .datePickerStyle(.graphical)

                        // stays open after picking a day, so the time can be changed too
                        Button {
                            showingDatePicker = false
                        } label: {
                            Text("Done")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundColor(Color.LightIcon)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 7)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                    .padding(17)
                        .onChange(of: date) { _ in
                            if date > Date.now {
                                animateIcon = true
                            } else {
                                animateIcon = false
                            }
                        }
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(showingDatePicker ? 1 : 0)
                .allowsHitTesting(showingDatePicker)
                .animation(.easeOut(duration: 0.25), value: showingDatePicker)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .ignoresSafeArea(.keyboard, edges: .all)
        .frame(maxHeight: .infinity)
        .background(Color.PrimaryBackground)
        .edgesIgnoringSafeArea(.all)
        .onChange(of: showToast) { newValue in
            if newValue {
                UIAccessibility.post(notification: .announcement, argument: NSLocalizedString(toastTitle, comment: ""))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: income) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = nil
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
            tagSuggestions = dataController.getAllTags()
            DispatchQueue.main.async {
                if let transaction = toEdit {
                    repeatType = Int(transaction.recurringType)
                    repeatCoefficient = Int(transaction.recurringCoefficient)
                    price = transaction.wrappedAmount

                    tags = transaction.wrappedTags

                    if let original = transaction.originalCurrency, original != homeCurrency, transaction.exchangeRate > 0 {
                        entryCurrency = original
                        exchangeRate = transaction.exchangeRate
                        price = transaction.originalAmount
                    }

                    if price.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 {
                        isEditingDecimal = true
                        decimalValuesAssigned = .second
                    }

                    if transaction.wrappedDate > Date.now {
                        animateIcon = true
                    }
                }
            }
        }
        .onChange(of: entryCurrency) { newValue in
            if let newValue, newValue != homeCurrency {
                ExchangeRates.markRecent(newValue)
            }
            // snap the typed amount to the new currency's minor units (e.g. no cents for JPY)
            let factor = pow(10, Double(ExchangeRates.fractionDigits(for: newValue ?? homeCurrency)))
            price = (price * factor).rounded() / factor
            if factor == 1 {
                isEditingDecimal = false
                decimalValuesAssigned = .none
            }
            loadRate()
        }
        .onChange(of: date) { _ in
            // keep a stored rate when editing; refetch only for new entries
            if toEdit == nil {
                loadRate()
            }
        }
        .sheet(isPresented: $showCurrencyPicker) {
            EntryCurrencyPicker(selection: $entryCurrency)
        }
        .alert(Text("Exchange Rate"), isPresented: $showManualRate) {
            TextField("Rate", text: $manualRateText)
                .keyboardType(.decimalPad)
            Button("Save") {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                if let value = formatter.number(from: manualRateText)?.doubleValue ?? Double(manualRateText), value > 0 {
                    exchangeRate = value
                    if let from = entryCurrency {
                        ExchangeRates.cache(rate: value, from: from, to: homeCurrency)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1 \(entryCurrency ?? "") = ? \(homeCurrency)")
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryView(mode: .transaction, income: income)
        }
        .sheet(isPresented: $showPicker) {
            if #available(iOS 16.0, *) {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker
                )
                .presentationDetents([.height(230)])
            } else {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
            }
        }
        .onChange(of: dynamicTypeSize) { _ in
            if income {
                swipingOffset = capsuleWidth
            }
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
        let formatter = DateFormatter()

        formatter.dateFormat = "HH:mm"

        return formatter.string(from: date)
    }

    func toggleFieldColors() {
        if categoryButtonTextColor == Color.AlertRed
            || categoryButtonBackgroundColor == Color.AlertRed.opacity(0.23) {
            withAnimation(.linear) {
                categoryButtonTextColor = Color.SubtitleText
                categoryButtonBackgroundColor = Color.clear
                categoryButtonOutlineColor = Color.Outline
            }
        } else {
            withAnimation(.easeOut(duration: 1.0)) {
                categoryButtonTextColor = Color.AlertRed
                categoryButtonBackgroundColor = Color.AlertRed.opacity(0.23)
                categoryButtonOutlineColor = Color.AlertRed
            }
            withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    shake = false
                }
                withAnimation(.easeOut(duration: 0.6)) {
                    categoryButtonTextColor = Color.SubtitleText
                    categoryButtonBackgroundColor = Color.clear
                    categoryButtonOutlineColor = Color.Outline
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
        } else if isForeignEntry && exchangeRate == nil {
            toastImage = "arrow.left.arrow.right"
            toastTitle = "Missing Exchange Rate"
            showToast = true
            generator.notificationOccurred(.error)
            manualRateText = ""
            showManualRate = true
            return
        }

        generator.notificationOccurred(.success)

        // amounts are always stored in the home currency; the original entry is kept alongside
        let storedAmount = convertedPrice ?? price
        let originalCurrency = isForeignEntry ? entryCurrency : nil
        let originalAmount = isForeignEntry ? price : 0
        let storedRate = isForeignEntry ? (exchangeRate ?? 0) : 0

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
                    editedTransaction.amount = storedAmount
                    editedTransaction.originalAmount = originalAmount
                    editedTransaction.originalCurrency = originalCurrency
                    editedTransaction.exchangeRate = storedRate
                    editedTransaction.wrappedTags = tags
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

        transaction.amount = storedAmount
        transaction.originalAmount = originalAmount
        transaction.originalCurrency = originalCurrency
        transaction.exchangeRate = storedRate
        transaction.wrappedTags = tags
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

        try? moc.save()

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
}

struct NumPadButton: ButtonStyle {
    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.3), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

func getDollarOffset(big: CGFloat, small: CGFloat) -> CGFloat {
    let bigFont = UIFont.rounded(ofSize: big, weight: .regular)
    let smallFont = UIFont.rounded(ofSize: small, weight: .light)

    return bigFont.capHeight - smallFont.capHeight - 1
}

struct NoteView: View {
    @Binding var note: String
    @Binding var focused: Bool

    @FocusState private var textFocused: Bool
    let characterLimit = 50

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var noteWidth: CGFloat {
        let fontSize: CGFloat = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let roundedFont: UIFont
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            roundedFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            roundedFont = systemFont
        }

        let attributes = [NSAttributedString.Key.font: roundedFont]

        let size = (note as NSString).size(withAttributes: attributes)

        let placeholder = String(localized: "Add Note")
        let placeholderSize = (placeholder as NSString).size(withAttributes: attributes)

        if !note.isEmpty {
            return size.width + 2
        } else {
            return placeholderSize.width
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.alignleft")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)

            ZStack(alignment: .leading) {
                TextField("", text: $note)
                    .onReceive(Just(note)) { _ in limitText(characterLimit) }
                    .focused($textFocused)
                    .foregroundColor(Color.PrimaryText)

                if note.isEmpty {
                    Text("Add Note")
                        .foregroundColor(Color.SubtitleText)
                }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: min(noteWidth, UIScreen.main.bounds.width / 1.5), alignment: .center)
        }
        .onTapGesture {
            textFocused = true
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .stroke(Color.Outline, lineWidth: 1.5)
        )
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

struct CustomRecurringView: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool

    @Environment(\.colorScheme) var systemColorScheme
    var stringArray: [String] {
        return [
            "", "\(holdingCoefficient) days", "\(holdingCoefficient) weeks",
            "\(holdingCoefficient) months"
        ]
    }

    @Environment(\.dismiss) var dismiss

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    var body: some View {
        VStack(spacing: 35) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(Color.SubtitleText)
                        .padding(7)
                        .background(Color.SecondaryBackground, in: Circle())
                        .contentShape(Circle())
                }

                Spacer()

                Text("Custom Interval")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Spacer()

                Button {
                    repeatType = holdingType
                    repeatCoefficient = holdingCoefficient

                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(Color.IncomeGreen)
                        .padding(7)
                        .background(Color.IncomeGreen.opacity(0.23), in: Circle())
                        .contentShape(Circle())
                }
            }

            HStack(spacing: 10) {
                Text("Repeats every")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .padding(.trailing, 3)

                VStack {
                    Button {
                        holdingCoefficient += 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 30 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 30)

                    Text("\(holdingCoefficient)")
                        .font(.system(size: 23, weight: .medium, design: .rounded))
                        .padding(7)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(width: 40, height: 40)
                        }

                    Button {
                        holdingCoefficient -= 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 2 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 2)
                }

                VStack {
                    Button {
                        holdingType -= 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 1 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 1)

                    Group {
                        if holdingType == 1 {
                            Text("\(holdingCoefficient) days")
                        } else if holdingType == 2 {
                            Text("\(holdingCoefficient) weeks")
                        } else if holdingType == 3 {
                            Text("\(holdingCoefficient) months")
                        }
                    }
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .padding(7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(height: 40)
                    }

                    Button {
                        holdingType += 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 3 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 3)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(13)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            holdingType = repeatType
            holdingCoefficient = repeatCoefficient
        }
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

struct EntryCurrencyPicker: View {
    @Binding var selection: String?
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    private var currencies: [Currency] {
        let all = Currency.allCurrencies
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.code.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List(currencies, id: \.self) { currency in
                Button {
                    selection = currency.code
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text(currency.code)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                            .frame(minWidth: 45, alignment: .leading)
                        Text(currency.name)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(Color.PrimaryText)
                            .lineLimit(1)
                        Spacer()
                        if currency.code == selection {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color.DarkIcon)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query)
            .navigationTitle(Text("Currencies"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Free-form tags under the note: chips you can remove, "+ Tag" to add, suggestions from earlier tags.
struct TagsRow: View {
    @Binding var tags: [String]
    var suggestions: [String]

    @State private var adding = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var matchingSuggestions: [String] {
        let used = Set(tags.map { $0.lowercased() })
        let query = Transaction.cleanTag(draft).lowercased()
        return suggestions
            .filter { !used.contains($0.lowercased()) }
            .filter { query.isEmpty || $0.lowercased().hasPrefix(query) }
            .prefix(6)
            .map { $0 }
    }

    private func add(_ raw: String) {
        let tag = Transaction.cleanTag(raw)
        guard !tag.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
            draft = ""
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            tags.append(tag)
        }
        draft = ""
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                tags.removeAll { $0 == tag }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                Image(systemName: "xmark")
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundColor(Color.SubtitleText)
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.PrimaryText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Color.SecondaryBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove tag \(tag)"))
                    }

                    if adding {
                        TextField("Tag", text: $draft)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($fieldFocused)
                            .frame(minWidth: 70, maxWidth: 140)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Color.SecondaryBackground, in: Capsule())
                            .onSubmit {
                                add(draft)
                                adding = false
                            }
                            .onChange(of: draft) { newValue in
                                // typing a comma or space finishes a tag
                                if let last = newValue.last, last == "," || last == " " {
                                    add(String(newValue.dropLast()))
                                }
                            }
                            .onAppear { fieldFocused = true }
                    } else {
                        Button {
                            adding = true
                        } label: {
                            Label {
                                Text("Tag")
                            } icon: {
                                Image(systemName: "number")
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(
                                Capsule().strokeBorder(Color.Outline, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add tag"))
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)

            if adding && fieldFocused && !matchingSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matchingSuggestions, id: \.self) { suggestion in
                            Button {
                                add(suggestion)
                            } label: {
                                Text("#\(suggestion)")
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundColor(Color.SubtitleText)
                                    .padding(.horizontal, 9)
                                    .frame(minHeight: 28)
                                    .background(Color.SecondaryBackground.opacity(0.6), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onChange(of: fieldFocused) { focused in
            if !focused {
                add(draft)
                adding = false
            }
        }
    }
}

/// Native (glass on iOS 26) repeat menu: none / daily / weekly / monthly, plus a custom interval.
struct RecurringMenuItems: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool

    private let names = ["none", "daily", "weekly", "monthly"]

    private var simpleSelection: Binding<Int> {
        Binding(
            get: { repeatCoefficient == 1 || repeatType == 0 ? repeatType : -1 },
            set: { newValue in
                withAnimation(.easeOut(duration: 0.2)) {
                    repeatType = newValue
                    repeatCoefficient = 1
                }
            }
        )
    }

    var body: some View {
        Picker("Repeat", selection: simpleSelection) {
            ForEach(names.indices, id: \.self) { index in
                Text(LocalizedStringKey(names[index])).tag(index)
            }
        }

        Button {
            showPicker = true
        } label: {
            if repeatCoefficient > 1 && repeatType > 0 {
                Label {
                    Text(customDescription)
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                Label {
                    Text("custom")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
    }

    private var customDescription: String {
        switch repeatType {
        case 1: return String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) days")
        case 2: return String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) weeks")
        default: return String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) months")
        }
    }
}
