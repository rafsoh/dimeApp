//
//  TemplateTransactionView.swift
//  dime
//
//  Created by Rafael Soh on 4/9/23.
//

import Combine
import Foundation
import SwiftUI
import WidgetKit

struct TemplateTransactionView: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1

    @Environment(\.colorScheme) var colorScheme

    @State private var note = ""
    @State var category: Category?
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

    @State private var numbers: [Int] = [0, 0, 0]
    @State private var numbers1: [String] = []
    private var amount: String {
        var string = ""

        if numberEntryType == 1 {
            for i in numbers.indices {
                if i == (numbers.count - 2) {
                    string += ".\(numbers[i])"
                } else {
                    string += "\(numbers[i])"
                }
            }

            return string
        } else {
            if numbers1.isEmpty {
                return "0"
            }
            for i in numbers1 {
                string = string + i
            }

            return string
        }
    }

    var transactionValue: Double {
        return (amount as NSString).doubleValue
    }

    var hasUnsavedInput: Bool {
        if let transaction = toEdit {
            return transactionValue != transaction.wrappedAmount
                || note != transaction.wrappedNote
                || category != transaction.category
                || income != transaction.income
                || repeatType != Int(transaction.recurringType)
                || repeatCoefficient != Int(transaction.recurringCoefficient)
        } else {
            return transactionValue > 0 || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @State var showCategorySheet = false

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    // toasts
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    @ObservedObject var keyboardHeightHelper = KeyboardHeightHelper()

    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstLaunch: Bool = true

    // edit mode
    let toEdit: TemplateTransaction?

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    var showsIncomeControls: Bool {
        incomeTracking || toEdit?.income == true
    }

    // delete mode

    @State var toDelete: TemplateTransaction?
    @State var deleteMode = false

    let numberArray = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    var numberArrayCount: Int {
        if numberEntryType == 1 {
            return numbers.count
        } else {
            return numbers1.count
        }
    }

    var amountFontSize: CGFloat {
        let amountText: String
        let size = UIScreen.main.bounds.width - 105

        if numberEntryType == 2 {
            amountText = amount
        } else {
            amountText = String(format: "%.2f", transactionValue)
        }

        if ((amountText + currencySymbol).widthOfRoundedString(size: 32, weight: .regular) + 4) > size {
            return 24
        } else if ((amountText + currencySymbol).widthOfRoundedString(size: 44, weight: .regular) + 4) > size {
            return 32
        } else if ((amountText + currencySymbol).widthOfRoundedString(size: 56, weight: .regular) + 4) > size {
            return 44
        } else {
            return 56
        }
    }

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

    @State var showPicker = false
    @State private var isDismissDragging = false
    @State var animateIcon = false

    let order: Int

    var body: some View {
//        ScrollView {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                // income/expense picker
                HStack(spacing: 10) {
                    GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                        dismiss()
                    }

                    Spacer()

                    RecurringMenu(repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker, accessibilityLabel: repeatButtonAccessibility)
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
                    if toEdit != nil {
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

                // number display and note view
                VStack(spacing: 8) {
                    if numberEntryType == 1 {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(currencySymbol)
                                .font(.system(size: amountFontSize, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                            Text("\(transactionValue, specifier: "%.2f")")
                                .font(.system(size: amountFontSize, weight: .regular, design: .rounded))
                                .foregroundColor(Color.PrimaryText)
                        }
                    } else {
                        if numbers1.isEmpty {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(currencySymbol)
                                    .font(.system(size: 56, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)
                                Text("0")
                                    .font(.system(size: 56, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.PrimaryText)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(currencySymbol)
                                    .font(.system(size: amountFontSize, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)
                                Text(amount)
                                    .font(.system(size: amountFontSize, weight: .regular, design: .rounded))
                                    .foregroundColor(Color.PrimaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .trailing) {
                                DeleteButton()
                            }
                        }
                    }

                    NoteView(note: $note, focused: Binding.constant(false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CategoryToken(category: category, isError: false, shake: false) {
                    UIApplication.shared.endEditing()
                    showCategorySheet = true
                }
                .disabled(isDismissDragging)
                .padding(.bottom, 4)

                // num pad
                GeometryReader { proxy in
                    VStack(spacing: proxy.size.height * 0.04) {
                        ForEach(numberArray, id: \.self) { array in
                            HStack(spacing: proxy.size.width * 0.05) {
                                ForEach(array, id: \.self) { singleNumber in
                                    NumberButton(number: singleNumber, size: proxy.size)
                                }
                            }
                        }

                        HStack(spacing: proxy.size.width * 0.05) {
                            if numberEntryType == 1 {
                                Button {
                                    if numbers.count == 3 {
                                        numbers.remove(at: numbers.count - 1)
                                        numbers.insert(0, at: 0)
                                    } else {
                                        numbers.remove(at: numbers.count - 1)
                                    }
                                } label: {
                                    Image("tag-cross")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .frame(width: proxy.size.width * 0.3, height: proxy.size.height * 0.22)
                                        .background(Color.DarkBackground)
                                        .foregroundColor(Color.LightIcon)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(NumPadButton())
                            } else {
                                Button {
                                    if numbers1.isEmpty {
                                        numbers1.append("0")
                                        numbers1.append(".")
                                    } else if numbers1.contains(".") {
                                        return
                                    } else {
                                        numbers1.append(".")
                                    }
                                } label: {
                                    Text(".")
                                        .font(.system(size: 34, weight: .regular, design: .rounded))
                                        .frame(width: proxy.size.width * 0.3, height: proxy.size.height * 0.22)
                                        .background(Color.SecondaryBackground)
                                        .foregroundColor(Color.PrimaryText)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .opacity(numbers1.contains(".") ? 0.6 : 1)
                                }
                                .disabled(numbers1.contains("."))
                                .buttonStyle(NumPadButton())
                            }

                            NumberButton(number: 0, size: proxy.size)

                            Button {
                                submit()
                            } label: {
                                Group {
                                    if #available(iOS 17.0, *) {
                                        Image(systemName: "checkmark.square.fill")
                                            .font(.system(size: 30, weight: .medium, design: .rounded))
                                            .symbolEffect(.bounce.up.byLayer, value: transactionValue != 0 && category != nil)
//                                            .symbolEffectsRemoved()
                                    } else {
                                        Image(systemName: "checkmark.square.fill")
                                            .font(.system(size: 30, weight: .medium, design: .rounded))
                                    }
                                }
                                .frame(width: proxy.size.width * 0.3, height: proxy.size.height * 0.22)
                                .foregroundColor(Color.LightIcon)
                                .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(NumPadButton())
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .disabled(isDismissDragging)
                .padding(.bottom, 15)
//                .keyboardAwareHeight()
            }
            .padding(17)
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
        .onChange(of: income) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = nil
        }
        .onAppear {
            DispatchQueue.main.async {
                if let transaction = toEdit {
                    let string = String(format: "%.2f", transaction.wrappedAmount)

                    var stringArray = string.compactMap { String($0) }

                    numbers = stringArray.compactMap { Int($0) }

                    if round(transaction.wrappedAmount) == transaction.wrappedAmount {
                        stringArray.removeLast()
                        stringArray.removeLast()
                        stringArray.removeLast()
                        numbers1 = stringArray
                    } else {
                        numbers1 = stringArray
                    }
                }
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryPickerSheet(category: $category, income: income)
        }
        .sheet(isPresented: $showPicker) {
            if #available(iOS 16.0, *) {
                CustomRecurringView(repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
                    .presentationDetents([.height(210)])
                    .presentationDragIndicator(.hidden)
            } else {
                CustomRecurringView(repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
            }
        }
    }

    @ViewBuilder
    func DeleteButton() -> some View {
        GlassIconButton(systemName: "delete.left.fill", accessibilityLabel: "Delete last digit", foreground: Color.PrimaryText) {
            if !numbers1.isEmpty {
                if numbers1.count == 2 && numbers1[0] == "0" && numbers1[1] == "." {
                    numbers1.removeAll()
                } else {
                    numbers1.removeLast()
                }
            }
        }
        .disabled(numbers1.isEmpty)
        .opacity(numbers1.isEmpty ? 0.4 : 1)
    }

    @ViewBuilder
    func NumberButton(number: Int, size: CGSize) -> some View {
        Button {
            if numberEntryType == 1 {
                if numbers[0] == 0 {
                    numbers.append(number)
                    numbers.remove(at: 0)
                } else {
                    numbers.append(number)
                }
            } else {
                if number == 0 && numbers1.isEmpty {
                    return
                } else {
                    if numbers1.contains(".") {
                        if numbers1.count - numbers1.firstIndex(of: ".")! < 3 {
                            numbers1.append(String(number))
                        } else {
                            return
                        }
                    } else {
                        numbers1.append(String(number))
                    }
                }
            }
        } label: {
            Text("\(number)")
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .frame(width: size.width * 0.3, height: size.height * 0.22)
                .background(Color.SecondaryBackground)
                .foregroundColor(Color.PrimaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(numberArrayCount == 9 ? 0.6 : 1)
        }
        .disabled(numberArrayCount == 9)
        .buttonStyle(NumPadButton())
    }

    func submit() {
        let generator = UINotificationFeedbackGenerator()

        if transactionValue == 0 && category == nil {
            toastImage = "questionmark.app"
            toastTitle = "Incomplete Entry"
            showToast = true
            generator.notificationOccurred(.error)

            return
        } else if transactionValue == 0 {
            toastImage = "centsign.circle"
            toastTitle = "Missing Amount"
            showToast = true
            generator.notificationOccurred(.error)
            return
        } else if category == nil {
            toastImage = "tray"
            toastTitle = "Missing Category"
            showToast = true
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

            editedTransaction.amount = transactionValue
            editedTransaction.income = income

            editedTransaction.recurringType = Int16(repeatType)
            editedTransaction.recurringCoefficient = Int16(repeatCoefficient)

            dataController.save()

            dismiss()

        } else {
            let transaction = TemplateTransaction(context: moc)
            if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                transaction.note = category?.wrappedName ?? ""
            } else {
                transaction.note = note.trimmingCharacters(in: .whitespaces)
            }

            transaction.income = income

            if let unwrappedCategory = category {
                transaction.category = unwrappedCategory
            }

            transaction.amount = transactionValue
            transaction.id = UUID()
            transaction.order = Int16(order)

            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)

            dataController.save()

            dismiss()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    init(order: Int) {

        let dataController = DataController.shared

        let toEdit = dataController.getTemplateTransaction(order: order)

        if let transaction = toEdit {
            _note = State(initialValue: transaction.wrappedNote)

            if let unwrappedCategory = transaction.category {
                _category = State(initialValue: unwrappedCategory)
                print(unwrappedCategory.wrappedName)
                print("FOUND IT")
            } else {
                print("CANNOT FIND")
            }

            _income = State(initialValue: transaction.income)

            _repeatType = State(initialValue: Int(transaction.recurringType))
            _repeatCoefficient = State(initialValue: Int(transaction.recurringCoefficient))

            print("IM HERE")
        }

        self.order = order
        self.toEdit = toEdit
    }
}

struct SettingsQuickAddWidgetView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var body: some View {
        VStack(spacing: 10) {
            Text("Quick Add Widget")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        self.presentationMode.wrappedValue.dismiss()
                    } label: {
                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.SubtitleText)
                            }
                    }
                }
                .padding(.bottom, 40)

            SettingsQuickAddWidgetDraggingView()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitle("")
        .navigationBarHidden(true)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
    }
}

struct SettingsQuickAddWidgetDraggingView: View {
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!

    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @StateObject var gridData = GridViewModel()
    @State var selectedItem: Grid?
    @State var lastSelectedIndex: Int = 0

    @State var refreshID = UUID()

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.order)
    ]) private var transactions: FetchedResults<TemplateTransaction>

    let columns = Array(repeating: GridItem(.fixed(100), spacing: 15), count: 2)

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: 15, content: {
                ForEach(0 ..< 4) { index in

                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.SubtitleText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 15).fill(Color.SecondaryBackground).shadow(color: gridData.gridItems[index].transaction == nil ? Color.gray.opacity(0.25) : Color.clear, radius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.Outline, lineWidth: 1.3))
                        .frame(height: 100)
                }
            })

            LazyVGrid(columns: columns, spacing: 15, content: {
                ForEach(gridData.gridItems) { grid in

                    Group {
                        if let transaction = grid.transaction {
                            if grid.id == gridData.currentGrid?.id && gridData.dragging {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(blend(over: Color(hex: transaction.wrappedColour), withAlpha: 0.7))

                                    RoundedRectangle(cornerRadius: 15)
                                        .strokeBorder(Color.DarkIcon, lineWidth: 2)
                                }
                            } else {
                                SingleTemplateButton(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol)
                            }
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                    }
                    .frame(height: 100)
                    .transition(.opacity)
                    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 15))
                    .onDrag({
                        gridData.currentGrid = grid
                        return NSItemProvider(object: String(grid.index) as NSString)
                    }, preview: {
                        if let transaction = grid.transaction {
                            SingleTemplateButton(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol)
                                .frame(width: 100, height: 100)
                                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 15))
                        }
                    })
                    .onDrop(of: [.text], delegate: DropViewDelegate(grid: grid, gridData: gridData))
                    .onTapGesture {
                        selectedItem = grid
                        print(grid.index)
                        lastSelectedIndex = grid.index
                    }
                }
            })
            .id(refreshID)
//
//            VStack {
//                ForEach(transactions) { transaction in
//                    Text(transaction.category?.wrappedName ?? "")
//                }
//            }
        }
        .padding(15)
        .frame(width: 245)
        .background(RoundedRectangle(cornerRadius: 25).fill(Color.PrimaryBackground).shadow(color: Color.gray.opacity(0.2), radius: 12))
        .sheet(item: $selectedItem, onDismiss: {
            gridData.reset()
            refreshID = UUID()
        }) { grid in
            TemplateTransactionView(order: grid.index)
        }
    }
}

struct SingleTemplateButton: View {
    let transaction: TemplateTransaction
    let showCents: Bool
    let currencySymbol: String
    var dollarOffset: CGFloat {
        let bigFont = UIFont.rounded(ofSize: 21, weight: .semibold)
        let smallFont = UIFont.rounded(ofSize: 15, weight: .medium)

        return bigFont.capHeight - smallFont.capHeight
    }

    var downsize: (big: CGFloat, small: CGFloat, amountText: String) {
        let amountText: String
        let size: CGFloat = 80

        if showCents && transaction.amount < 100 {
            amountText = String(format: "%.2f", transaction.amount)
        } else {
            amountText = String(format: "%.0f", transaction.amount)
        }

        if amountText.widthOfRoundedString(size: 16, weight: .semibold) + currencySymbol.widthOfRoundedString(size: 13, weight: .medium) + 2 > size {
            return (12, 9, amountText)
        } else if amountText.widthOfRoundedString(size: 21, weight: .semibold) + currencySymbol.widthOfRoundedString(size: 18, weight: .medium) + 2 > size {
            return (16, 13, amountText)
        } else {
            return (21, 18, amountText)
        }
    }

    var transactionColor: Color {
        if transaction.category?.income ?? false {
            return Color.IncomeGreen
        } else {
            return Color(hex: transaction.wrappedColour)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(transaction.wrappedEmoji)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(5)
                .background(blend(over: transactionColor, withAlpha: 0.3), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Text(transaction.wrappedNote)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.PrimaryText)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 1.3) {
                Text(currencySymbol)
                    .font(.system(size: downsize.small, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .baselineOffset(getDollarOffset(big: downsize.big, small: downsize.small))

                Text(downsize.amountText)
                    .font(.system(size: downsize.big, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(blend(over: transactionColor, withAlpha: 0.8), in: RoundedRectangle(cornerRadius: 15))
        .shadow(color: transactionColor.opacity(0.8), radius: 6)
    }

    func getDollarOffset(big: CGFloat, small: CGFloat) -> CGFloat {
        let bigFont = UIFont.rounded(ofSize: big, weight: .semibold)
        let smallFont = UIFont.rounded(ofSize: small, weight: .medium)

        return bigFont.capHeight - smallFont.capHeight
    }
}

struct Grid: Identifiable {
    var id: UUID
    var index: Int
    var transaction: TemplateTransaction?

    init(index: Int) {
        id = UUID()

        let dataController = DataController.shared

        transaction = dataController.getTemplateTransaction(order: index)
        self.index = index
    }
}

class GridViewModel: ObservableObject {
    @Published var currentGrid: Grid?
    @Published var dragging = false

    @Published var gridItems = [
        Grid(index: 0),
        Grid(index: 1),
        Grid(index: 2),
        Grid(index: 3)
    ]

    func reset() {
        withAnimation {
            gridItems = [
                Grid(index: 0),
                Grid(index: 1),
                Grid(index: 2),
                Grid(index: 3)
            ]
        }
    }

    func updateIndices() {
//        let dataController = DataController()
        let dataController = DataController.shared
        for (index, element) in gridItems.enumerated() {
            if let transaction = element.transaction {
                transaction.order = Int16(index)
            }
        }
        dataController.save()
    }
}

struct DropViewDelegate: DropDelegate {
    var grid: Grid
    var gridData: GridViewModel

    func performDrop(info _: DropInfo) -> Bool {
        gridData.updateIndices()
        gridData.currentGrid = nil
        gridData.dragging = false
        return true
    }

    func dropEntered(info _: DropInfo) {
        gridData.dragging = true

        if let unwrapped = gridData.currentGrid {
            if unwrapped.transaction == nil {
                return
            }
        }

        let fromIndex = gridData.gridItems.firstIndex { grid -> Bool in
            grid.id == gridData.currentGrid?.id
        } ?? 0

        let toIndex = gridData.gridItems.firstIndex { grid -> Bool in
            grid.id == self.grid.id
        } ?? 0

        if fromIndex != toIndex {
            withAnimation(.easeIn(duration: 0.2)) {
                let fromGrid = gridData.gridItems[fromIndex]
                gridData.gridItems[fromIndex] = gridData.gridItems[toIndex]
                gridData.gridItems[toIndex] = fromGrid
            }
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
