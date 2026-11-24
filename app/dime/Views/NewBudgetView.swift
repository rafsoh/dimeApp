//
//  NewBudgetView.swift
//  dime
//
//  Created by Rafael Soh on 15/7/23.
//

import CoreData
import Popovers
import SwiftUI

struct InstructionHeadings {
    let title: String
    let subtitle: String
}

private enum BudgetSentenceToken: Hashable {
    case amount, category, period, start
}

private enum BudgetEditor: Hashable {
    case amount, category, start
}

struct BrandNewBudgetView: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1
    @AppStorage("keyboard", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var savedKeyboardHeight: Double = .init(UIScreen.main.bounds.height / 2.5)

    let overallBudgetCreated: Bool
    let toEditBudget: Budget?
    let toEditMainBudget: MainBudget?

    @State private var price: Double
    @State private var isEditingDecimal: Bool
    @State private var decimalValuesAssigned: AssignedDecimal

    @State private var isOverall: Bool
    @State private var selectedCategory: Category?
    @State private var timeFrame: BudgetTimeFrame
    @State private var chosenDayWeek: Int
    @State private var chosenDayMonth: Int
    @State private var chosenDayYear: Date

    @State private var activeEditor: BudgetEditor?
    @State private var showPeriodMenu = false
    @State private var showWeekdayMenu = false
    @State private var showStartDateSheet = false

    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastImage = ""
    @State private var errorTokens: Set<BudgetSentenceToken> = []
    @State private var shake = false

    @ScaledMetric(relativeTo: .title) private var sentenceSize: CGFloat = 27

    private var sentenceFont: Font {
        .system(size: min(sentenceSize, 33), weight: .semibold, design: .rounded)
    }

    private let editorAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var editMode: Bool {
        toEditBudget != nil || toEditMainBudget != nil
    }

    var canChooseOverall: Bool {
        !editMode && !overallBudgetCreated
    }

    var canChooseCategory: Bool {
        toEditMainBudget == nil
    }

    var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? "$"
    }

    var oneYearAgo: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Date.now)!
    }

    var editorHeight: CGFloat {
        CGFloat(savedKeyboardHeight)
    }

    /// Small phones open the yearly calendar in a sheet instead of inline.
    var yearCalendarFitsInline: Bool {
        UIScreen.main.bounds.height >= 750
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sentence

                    if let perDayHint {
                        Text(perDayHint)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
                .frame(minHeight: proxy.size.height)
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
                if let activeEditor {
                    editor(activeEditor)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    primaryButton
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
        .animation(editorAnimation, value: activeEditor)
        .animation(.easeInOut(duration: 0.2), value: timeFrame)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .sheet(isPresented: $showStartDateSheet) {
            BudgetStartDateSheet(date: $chosenDayYear, range: oneYearAgo ... Date.now)
        }
    }

    var header: some View {
        HStack {
            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }

            Spacer()
        }
        .frame(height: 44)
        .overlay {
            if showToast {
                GlassToast(title: toastTitle, systemImage: toastImage, color: Color.AlertRed)
            }
        }
    }

    var primaryButton: some View {
        Button {
            submit()
        } label: {
            Text(editMode ? "Save" : "Create Budget")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Capsule())
        }
        .whiteGlassButtonStyle()
    }

    // MARK: - Bottom editors

    private func editor(_ editor: BudgetEditor) -> some View {
        ZStack {
            switch editor {
            case .amount:
                NumberPad(
                    price: $price,
                    category: $selectedCategory,
                    isEditingDecimal: $isEditingDecimal,
                    decimalValuesAssigned: $decimalValuesAssigned
                ) {
                    commitAmount()
                }
                .transition(.opacity)
            case .category:
                BudgetCategoryGrid(
                    category: $selectedCategory,
                    overall: canChooseOverall ? $isOverall : nil,
                    editing: toEditBudget
                ) {
                    advance(from: .category)
                }
                .padding(.top, 8)
                .padding(.bottom, 15)
                .transition(.opacity)
            case .start:
                startEditor
                    .transition(.opacity)
            }
        }
        .frame(height: fixedEditorHeight(editor))
    }

    /// The keypad keeps the keyboard's height; the category row, the day grid and the calendar size themselves.
    private func fixedEditorHeight(_ editor: BudgetEditor) -> CGFloat? {
        switch editor {
        case .amount:
            return editorHeight
        case .category, .start:
            return nil
        }
    }

    /// Weekly budgets pick their day from a menu on the token, so only monthly and yearly budgets have an editor here.
    @ViewBuilder var startEditor: some View {
        switch timeFrame {
        case .month:
            BudgetDayGrid(selection: $chosenDayMonth, title: ordinal, onPick: finishStartEditorSoon)
                .padding(.top, 8)
                .padding(.bottom, 15)
        case .year:
            GlassDatePicker(selection: $chosenDayYear, in: oneYearAgo ... Date.now, visibleWeeks: 5, onPick: finishStartEditorSoon)
                .padding(.top, 4)
                .padding(.bottom, 15)
        case .day, .week:
            EmptyView()
        }
    }

    /// Leaves the choice on screen for a moment before the editor closes.
    func finishStartEditorSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard activeEditor == .start else { return }
            finishStartEditor()
        }
    }

    // MARK: - Sentence

    @ViewBuilder var sentence: some View {
        Group {
            if #available(iOS 16.0, *) {
                SentenceFlowLayout(spacing: 10, lineSpacing: 6) {
                    lead("Spend at most").layoutValue(key: KeepWithNext.self, value: true)
                    amountToken

                    lead("on").layoutValue(key: KeepWithNext.self, value: true)
                    categoryToken

                    lead("every").layoutValue(key: KeepWithNext.self, value: true)
                    periodClauseEnd

                    if timeFrame != .day {
                        lead("starting").layoutValue(key: KeepWithNext.self, value: true)
                        endOfSentence(startToken)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    clause("Spend at most") { amountToken }
                    clause("on") { categoryToken }
                    clause("every") { periodClauseEnd }

                    if timeFrame != .day {
                        clause("starting") { endOfSentence(startToken) }
                    }
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

    func endOfSentence<Token: View>(_ token: Token) -> some View {
        HStack(spacing: 0) {
            token

            Text(".")
                .font(sentenceFont)
                .foregroundColor(Color.PrimaryText)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder var periodClauseEnd: some View {
        if timeFrame == .day {
            endOfSentence(periodToken)
        } else {
            periodToken
        }
    }

    var amountToken: some View {
        let isFocused = activeEditor == .amount

        return SentenceTokenButton(
            text: amountText,
            font: sentenceFont,
            foreground: price == 0 && !isFocused ? Color.SubtitleText : Color.PrimaryText,
            tint: nil,
            isFocused: isFocused,
            isError: errorTokens.contains(.amount),
            shake: shake && errorTokens.contains(.amount),
            accessibilityLabel: Text("Amount") + Text(", ") + Text(amountText),
            clear: isFocused && (price != 0 || isEditingDecimal) ? clearAmount : nil
        ) {
            toggleEditor(.amount)
        }
    }

    var categoryToken: some View {
        let colour: Color? = isOverall ? nil : selectedCategory.map { Color(hex: $0.wrappedColour) }
        let text: String
        if isOverall {
            text = String(localized: "everything")
        } else if let selectedCategory {
            text = selectedCategory.wrappedEmoji + " " + selectedCategory.wrappedName
        } else {
            text = String(localized: "a category")
        }

        return SentenceTokenButton(
            text: text,
            font: sentenceFont,
            foreground: colour ?? (isOverall ? Color.PrimaryText : Color.SubtitleText),
            tint: colour,
            isFocused: activeEditor == .category,
            isError: errorTokens.contains(.category),
            shake: shake && errorTokens.contains(.category),
            accessibilityLabel: Text("Category") + Text(", ") + Text(text)
        ) {
            toggleEditor(.category)
        }
        .disabled(!canChooseCategory)
        .opacity(canChooseCategory ? 1 : 0.6)
    }

    var periodToken: some View {
        SentenceTokenButton(
            text: periodText,
            font: sentenceFont,
            foreground: Color.PrimaryText,
            tint: nil,
            isFocused: false,
            isError: false,
            shake: false,
            accessibilityLabel: Text("Repeats every") + Text(" ") + Text(periodText)
        ) {
            closeEditor {
                showPeriodMenu = true
            }
        }
        .popover(present: $showPeriodMenu, attributes: popoverAttributes) {
            GlassPopoverMenu {
                ForEach(BudgetTimeFrame.allCases, id: \.self) { frame in
                    GlassPopoverRow(LocalizedStringKey(frame.rawValue), isSelected: frame == timeFrame) {
                        selectTimeFrame(frame)
                    }
                }
            }
        }
    }

    var startToken: some View {
        SentenceTokenButton(
            text: startText,
            font: sentenceFont,
            foreground: Color.PrimaryText,
            tint: nil,
            isFocused: activeEditor == .start,
            isError: false,
            shake: false,
            accessibilityLabel: Text("Starting") + Text(" ") + Text(startText)
        ) {
            if timeFrame == .week {
                closeEditor {
                    showWeekdayMenu = true
                }
            } else if timeFrame == .year && !yearCalendarFitsInline {
                closeEditor {
                    showStartDateSheet = true
                }
            } else {
                toggleEditor(.start)
            }
        }
        .popover(present: $showWeekdayMenu, attributes: weekdayMenuAttributes) {
            GlassPopoverMenu {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    GlassPopoverRow(LocalizedStringKey(weekdaySymbol(weekday)), isSelected: weekday == chosenDayWeek) {
                        selectWeekday(weekday)
                    }
                }
            }
        }
    }

    func popoverAttributes(_ attributes: inout Popover.Attributes) {
        attributes.position = .absolute(originAnchor: .bottom, popoverAnchor: .top)
        attributes.rubberBandingMode = .none
        attributes.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -8, right: 0)
        attributes.presentation.animation = .easeInOut(duration: 0.2)
        attributes.dismissal.animation = .easeInOut(duration: 0.3)
    }

    /// Seven rows don't fit under the last line of the sentence, so the weekday menu opens above its token.
    func weekdayMenuAttributes(_ attributes: inout Popover.Attributes) {
        popoverAttributes(&attributes)
        attributes.position = .absolute(originAnchor: .top, popoverAnchor: .bottom)
        attributes.sourceFrameInset = UIEdgeInsets(top: -8, left: 0, bottom: 0, right: 0)
    }

    // MARK: - Token text

    var amountText: String {
        if activeEditor == .amount || price == 0 {
            return currencySymbol + typedAmount
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let fractionDigits = price.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: price)) ?? currencySymbol + typedAmount
    }

    var typedAmount: String {
        if numberEntryType == 1 {
            return String(format: "%.2f", price)
        }
        if isEditingDecimal {
            switch decimalValuesAssigned {
            case .none:
                return String(format: "%.0f", price) + "."
            case .first:
                return String(format: "%.1f", price)
            case .second:
                return String(format: "%.2f", price)
            }
        }
        return String(format: "%.0f", price)
    }

    var periodText: String {
        switch timeFrame {
        case .day:
            return String(localized: "day")
        case .week:
            return String(localized: "weekNewBudget")
        case .month:
            return String(localized: "monthNewBudget")
        case .year:
            return String(localized: "yearNewBudget")
        }
    }

    var startText: String {
        switch timeFrame {
        case .day:
            return ""
        case .week:
            return weekdaySymbol(chosenDayWeek)
        case .month:
            return String(format: NSLocalizedString("the %@", comment: "Budget start day of month, e.g. the 1st"), ordinal(chosenDayMonth))
        case .year:
            return chosenDayYear.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    var orderedWeekdays: [Int] {
        let setting = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
        let first = (1 ... 7).contains(setting) ? setting : Calendar.current.firstWeekday
        return (0 ..< 7).map { (first - 1 + $0) % 7 + 1 }
    }

    func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1 + symbols.count) % symbols.count]
    }

    func ordinal(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }

    var perDayHint: String? {
        guard timeFrame != .day, price > 0 else { return nil }

        let average: Double
        switch timeFrame {
        case .day:
            return nil
        case .week:
            average = price / 7
        case .month:
            average = price / 30
        case .year:
            average = price / 365
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = average < 10 ? 2 : 0
        formatter.minimumFractionDigits = 0

        let value = formatter.string(from: NSNumber(value: average)) ?? ""
        return String(format: NSLocalizedString("≈ %@ a day", comment: "Budget per-day hint"), value)
    }

    // MARK: - Actions

    private func toggleEditor(_ editor: BudgetEditor) {
        withAnimation(editorAnimation) {
            activeEditor = activeEditor == editor ? nil : editor
        }
    }

    func closeEditor(then action: @escaping () -> Void) {
        if activeEditor != nil {
            withAnimation(editorAnimation) {
                activeEditor = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
        } else {
            action()
        }
    }

    private func advance(from editor: BudgetEditor) {
        let next: BudgetEditor?
        if price == 0 && editor != .amount {
            next = .amount
        } else if !isOverall && selectedCategory == nil && canChooseCategory && editor != .category {
            next = .category
        } else {
            next = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (editor == .amount ? 0 : 0.25)) {
            guard activeEditor == editor else { return }
            withAnimation(editorAnimation) {
                activeEditor = next
            }
        }
    }

    func selectTimeFrame(_ frame: BudgetTimeFrame) {
        guard frame != timeFrame else {
            showPeriodMenu = false
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        timeFrame = frame

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showPeriodMenu = false
        }
    }

    func selectWeekday(_ weekday: Int) {
        guard weekday != chosenDayWeek else {
            showWeekdayMenu = false
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chosenDayWeek = weekday

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showWeekdayMenu = false
        }
    }

    func finishStartEditor() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(editorAnimation) {
            activeEditor = nil
        }
    }

    func commitAmount() {
        if price == 0 {
            flagError(title: "Missing Amount", image: "centsign.circle", tokens: [.amount])
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        advance(from: .amount)
    }

    func clearAmount() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        price = 0
        isEditingDecimal = false
        decimalValuesAssigned = .none
    }

    private func flagError(title: String, image: String, tokens: Set<BudgetSentenceToken>) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        toastTitle = title
        toastImage = image
        showToast = true

        withAnimation(.easeOut(duration: 0.2)) {
            errorTokens = tokens
        }
        withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.1)) {
                shake = false
            }
            withAnimation(.easeOut(duration: 0.6)) {
                errorTokens = []
            }
        }
    }

    func submit() {
        let missingCategory = !isOverall && selectedCategory == nil

        if price == 0 && missingCategory {
            flagError(title: "Incomplete Entry", image: "questionmark.app", tokens: [.amount, .category])
            return
        } else if price == 0 {
            flagError(title: "Missing Amount", image: "centsign.circle", tokens: [.amount])
            withAnimation(editorAnimation) {
                activeEditor = .amount
            }
            return
        } else if missingCategory {
            flagError(title: "Missing Category", image: "tray", tokens: [.category])
            withAnimation(editorAnimation) {
                activeEditor = .category
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let budgetType = Int16(budgetTypeInteger(timeFrame))
        let startDate = computedStartDate()

        if let budget = toEditBudget {
            budget.category = selectedCategory
            budget.startDate = startDate
            budget.amount = price
            budget.type = budgetType
        } else if let budget = toEditMainBudget {
            budget.startDate = startDate
            budget.amount = price
            budget.type = budgetType
        } else if isOverall {
            guard !overallBudgetCreated else {
                dismiss()
                return
            }

            let budget = MainBudget(context: moc)
            budget.startDate = startDate
            budget.amount = price
            budget.type = budgetType
        } else if let category = selectedCategory, category.budget == nil {
            let budget = Budget(context: moc)
            budget.category = category
            budget.startDate = startDate
            budget.amount = price
            budget.dateCreated = Date.now
            budget.type = budgetType
            budget.id = UUID()
        }

        dataController.save()
        dismiss()
    }

    func computedStartDate() -> Date {
        let today = Calendar.current.startOfDay(for: Date.now)

        switch timeFrame {
        case .day:
            return today
        case .week:
            let calendar = Calendar.current
            let daysSinceStart = (calendar.component(.weekday, from: today) - chosenDayWeek + 7) % 7
            return calendar.date(byAdding: .day, value: -daysSinceStart, to: today)!
        case .month:
            let calendar = Calendar.current
            let dateComponents = calendar.dateComponents([.month, .year], from: today)
            let startOfMonth = calendar.date(from: dateComponents)!
            let holdingDate = calendar.date(byAdding: .day, value: chosenDayMonth - 1, to: startOfMonth)!

            if holdingDate > today {
                return calendar.date(byAdding: .month, value: -1, to: holdingDate)!
            }
            return holdingDate
        case .year:
            return Calendar.current.startOfDay(for: chosenDayYear)
        }
    }

    func budgetTypeInteger(_ frame: BudgetTimeFrame) -> Int {
        switch frame {
        case .day:
            return 1
        case .week:
            return 2
        case .month:
            return 3
        case .year:
            return 4
        }
    }

    // MARK: - Init

    init(overallBudgetCreated: Bool, toEditBudget: Budget? = nil, toEditMainBudget: MainBudget? = nil) {
        self.overallBudgetCreated = overallBudgetCreated
        self.toEditBudget = toEditBudget
        self.toEditMainBudget = toEditMainBudget

        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let firstWeekday = defaults?.integer(forKey: "firstWeekday") ?? 0
        let firstDayOfMonth = defaults?.integer(forKey: "firstDayOfMonth") ?? 0
        let numberEntryType = defaults?.object(forKey: "numberEntryType") as? Int ?? 1

        var amount: Double = 0
        var frame = BudgetTimeFrame.month
        var weekday = (1 ... 7).contains(firstWeekday) ? firstWeekday : 1
        var monthDay = min(max(firstDayOfMonth, 1), 28)
        var yearDate = Date.now
        var storedType: Int16?
        var storedStart: Date?

        if let budget = toEditBudget {
            amount = budget.amount
            storedType = budget.type
            storedStart = budget.startDate
        } else if let budget = toEditMainBudget {
            amount = budget.amount
            storedType = budget.type
            storedStart = budget.startDate
        }

        if let storedType {
            switch storedType {
            case 1:
                frame = .day
            case 2:
                frame = .week
            case 4:
                frame = .year
            default:
                frame = .month
            }

            if let storedStart {
                switch frame {
                case .week:
                    weekday = Calendar.current.component(.weekday, from: storedStart)
                case .month:
                    monthDay = min(Calendar.current.component(.day, from: storedStart), 28)
                case .year:
                    yearDate = storedStart
                case .day:
                    break
                }
            }
        }

        let hasDecimals = amount.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2

        _price = State(initialValue: amount)
        _isEditingDecimal = State(initialValue: hasDecimals)
        _decimalValuesAssigned = State(initialValue: hasDecimals ? .second : .none)
        _isOverall = State(initialValue: toEditMainBudget != nil)
        _selectedCategory = State(initialValue: toEditBudget?.category)
        _timeFrame = State(initialValue: frame)
        _chosenDayWeek = State(initialValue: weekday)
        _chosenDayMonth = State(initialValue: monthDay)
        _chosenDayYear = State(initialValue: yearDate)
        _activeEditor = State(initialValue: toEditBudget == nil && toEditMainBudget == nil ? .amount : nil)
    }
}

// MARK: - Sentence token

private struct SentenceTokenButton: View {
    let text: String
    let font: Font
    let foreground: Color
    let tint: Color?
    let isFocused: Bool
    let isError: Bool
    let shake: Bool
    let accessibilityLabel: Text
    var clear: (() -> Void)?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = Capsule()
        let accent = isError ? Color.AlertRed : tint

        HStack(spacing: 0) {
            Button(action: action) {
                Text(text)
                    .font(font)
                    .foregroundColor(isError ? Color.AlertRed : foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 14)
                    .padding(.trailing, clear == nil ? 14 : 6)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isFocused ? .isSelected : [])

            if let clear {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .frame(width: 38)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .accessibilityLabel("Clear Amount")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(shape.fill((accent ?? .clear).opacity(isFocused ? 0.22 : 0.12)))
        .glassBackground(
            in: shape,
            tint: accent?.opacity(isFocused ? 0.35 : 0.25) ?? Color.glassTint,
            interactive: isEnabled,
            fallback: accent?.opacity(0.25) ?? Color.SecondaryBackground
        )
        .overlay(shape.strokeBorder(accent ?? Color.SubtitleText, lineWidth: 2).opacity(isFocused ? 1 : 0))
        .padding(.vertical, 2)
        .offset(x: shake ? -5 : 0)
    }
}

// MARK: - Wrapping sentence layout

@available(iOS 16.0, *)
private struct KeepWithNext: LayoutValueKey {
    static let defaultValue = false
}

/// Lays out words and tokens like wrapping text. A subview marked `KeepWithNext` moves to the next line
/// together with the following subview, so a lead word ("on", "every") never ends a line without its token.
@available(iOS 16.0, *)
private struct SentenceFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Line {
        var items: [(index: Int, width: CGFloat)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let lines = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = proposal.width ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY

        for line in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX

            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + line.height / 2),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: item.width, height: nil)
                )
                x += item.width + spacing
            }

            y += line.height + lineSpacing
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        let sizes: [CGSize] = subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            return ideal.width <= maxWidth ? ideal : subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }

        var groups: [[Int]] = []
        var pending: [Int] = []
        for index in subviews.indices {
            pending.append(index)
            if !subviews[index][KeepWithNext.self] {
                groups.append(pending)
                pending = []
            }
        }
        if !pending.isEmpty {
            groups.append(pending)
        }

        var lines: [Line] = []
        var line = Line()

        func append(_ index: Int) {
            let width = min(sizes[index].width, maxWidth)
            if !line.items.isEmpty && line.width + spacing + width > maxWidth {
                lines.append(line)
                line = Line()
            }
            line.width += (line.items.isEmpty ? 0 : spacing) + width
            line.height = max(line.height, sizes[index].height)
            line.items.append((index, width))
        }

        for group in groups {
            let groupWidth = group.reduce(0) { $0 + min(sizes[$1].width, maxWidth) } + spacing * CGFloat(group.count - 1)
            if !line.items.isEmpty && groupWidth <= maxWidth && line.width + spacing + groupWidth > maxWidth {
                lines.append(line)
                line = Line()
            }
            group.forEach(append)
        }

        if !line.items.isEmpty {
            lines.append(line)
        }

        return lines
    }
}

// MARK: - Bottom editors

private struct BudgetCategoryGrid: View {
    @Binding var category: Category?
    let overall: Binding<Bool>?
    let onSelect: () -> Void

    @FetchRequest private var categories: FetchedResults<Category>
    @State private var showNewCategory = false

    var body: some View {
        Group {
            if categories.isEmpty && overall == nil {
                VStack(spacing: 16) {
                    Text("no_expense_categories")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .multilineTextAlignment(.center)

                    NewCategoryCapsule {
                        showNewCategory = true
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                let rows = CategoryTileGrid<FetchedResults<Category>>.scrollingRows(selectableCount: categories.count + (overall == nil ? 0 : 1))

                ScrollView(.horizontal, showsIndicators: false) {
                    CategoryTileGrid(categories: categories, category: $category, overall: overall, rows: rows, onAdd: {
                        showNewCategory = true
                    }, onSelect: onSelect)
                        .padding(.horizontal, 20)
                }
                .frame(height: CategoryTileGrid<FetchedResults<Category>>.scrollingHeight(rows: rows))
                .padding(.horizontal, -20)
            }
        }
        .sheet(isPresented: $showNewCategory) {
            CategoryView(mode: .transaction, income: false)
        }
    }

    init(category: Binding<Category?>, overall: Binding<Bool>?, editing budget: Budget?, onSelect: @escaping () -> Void) {
        _category = category
        self.overall = overall
        self.onSelect = onSelect
        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order)],
            predicate: Category.budgetablePredicate(editing: budget)
        )
    }
}

/// The start-day editor for monthly budgets: the days 1 to 28 as plain numerals, with one filled circle on the chosen day.
/// It stops at the 28th because not every month has later days.
private struct BudgetDayGrid: View {
    @Binding var selection: Int
    let title: (Int) -> String
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(1 ... 7, id: \.self) { column in
                        cell(row * 7 + column)
                    }
                }
            }
        }
    }

    func cell(_ day: Int) -> some View {
        let isSelected = day == selection

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = day
            onPick()
        } label: {
            Text("\(day)")
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundColor(isSelected ? Color.LightIcon : Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    Circle()
                        .fill(Color.DarkBackground)
                        .frame(width: 42, height: 42)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BudgetStartDateSheet: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

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
                CategoryEditorTitle(title: "Start Date")
            }

            GlassDatePicker(selection: $date, in: range) {
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
                Color.clear.preference(key: BudgetStartDateSheetHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(BudgetStartDateSheetHeightKey.self) { height in
            contentHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetBackground()
    }
}

private struct BudgetStartDateSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    @ViewBuilder func budgetScrollBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
