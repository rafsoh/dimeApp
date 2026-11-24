//
//  CategoryView.swift
//  xpenz
//
//  Created by Rafael Soh on 10/5/22.
//

import Combine
import CoreHaptics
import Popovers
import SwiftUI
import UIKit

enum CategoryViewMode {
    case welcome, settings, transaction
}

struct CategoryView: View {
    var mode: CategoryViewMode
//    @Environment(\.colorScheme) var colorScheme
    @State var income = false
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    @State var newCategory = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>

    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var disabled: Bool {
        income == false && expenseCategories.count >= 24
    }

    var body: some View {
        switch mode {
        case .settings:
            content
        case .welcome, .transaction:
            if #available(iOS 16.0, *) {
                NavigationStack { content }
            } else {
                NavigationView { content }
                    .navigationViewStyle(.stack)
            }
        }
    }

    private var content: some View {
        CategoryListView(income: $income, mode: mode, showToast: $showToast, toastTitle: $toastTitle, toastImage: $toastImage, positive: $positive)
            .bottomBar {
                HStack(spacing: 12) {
                    if incomeTracking {
                        GlassSegmentedPicker(selection: $income, options: [
                            (value: false, title: "Expense"),
                            (value: true, title: "Income")
                        ])
                    }

                    Spacer(minLength: 0)

                    Button {
                        if disabled {
                            showToast = true
                            toastImage = "exclamationmark.triangle.fill"
                            toastTitle = "Limit Exceeded"
                            positive = false
                        } else {
                            newCategory = true
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .lineLimit(1)
                            .foregroundColor(Color.PrimaryText)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassBackground(in: Capsule(), tint: .glassTint)
                    .opacity(disabled ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        .sheet(isPresented: $newCategory) {
            if #available(iOS 16.0, *) {
                NewCategoryAlert(income: $income, bottomSpacers: false)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.hidden)
            } else {
                NewCategoryAlert(income: $income, bottomSpacers: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .all)
        .background(Color.PrimaryBackground)
    }
}

struct CategoryListView: View {
    @Binding var income: Bool
    var mode: CategoryViewMode

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @AppStorage("categorySuggestions", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showSuggestions: Bool = true
    @State var suggestionsToast = false

    @FetchRequest private var categories: FetchedResults<Category>

    @State var isEditing = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var allCategories: FetchedResults<Category>

    // delete mode
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    // edit mode
    @State private var toEdit: Category?

    // toasts
    @Binding var showToast: Bool
    @Binding var toastTitle: String
    @Binding var toastImage: String
    @Binding var positive: Bool

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    var sectionHeader: LocalizedStringKey {
        if income {
            return "Income Categories"
        } else {
            return "Expense Categories"
        }
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    private var categoriesHeader: some View {
        HStack {
            Text(sectionHeader)

            Spacer()

            if categories.count > 1 {
                SectionHeaderButton(
                    title: isEditing ? "Done" : "Reorder",
                    systemImage: isEditing ? "checkmark" : "arrow.up.arrow.down",
                    color: isEditing ? Color.IncomeGreen : Color.SubtitleText
                ) {
                    withAnimation {
                        isEditing.toggle()
                    }
                }
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .frame(height: 32)
        .foregroundColor(Color.SubtitleText)
        .textCase(.uppercase)
        .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
    }

    private var emptyState: some View {
        EmptyStateView(systemImage: "square.grid.2x2", title: LocalizedStringKey(income ? "no_income_categories" : "no_expense_categories"))
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            switch mode {
            case .transaction:
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            case .welcome, .settings:
                EmptyView()
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            switch mode {
            case .welcome:
                Button {
                    dismiss()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .prominentToolbarButton(tint: Color.IncomeGreen, isProminent: !allCategories.isEmpty)
                .disabled(allCategories.isEmpty)
            case .settings, .transaction:
                EmptyView()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                if #available(iOS 16.0, *) {
                    List {
                        Section(header: categoriesHeader) {
                            if categories.isEmpty {
                                if showSuggestions {
                                    emptyState
                                        .listRowBackground(Color.SettingsBackground)
                                }
                            } else {
                                ForEach(categories) { category in
                                    HStack(spacing: 10) {
                                        Text(category.wrappedEmoji)
                                            .font(.system(.subheadline, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 15))
                                        Text(category.wrappedName)
                                            .font(.system(.body, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundColor(toDelete == category ? Color.AlertRed : Color.PrimaryText)

                                        Spacer()

                                        if !income {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(Color(hex: category.wrappedColour))
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .frame(minHeight: .settingsRowHeight)
                                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }

//                                .onDelete(perform: deleteItem)
                        }

                        SuggestedCategoriesView(income: income)
                    }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                    .environment(\.defaultMinListRowHeight, .settingsRowHeight)
                } else {
                    List {
                        Section(header: categoriesHeader) {
                            if categories.isEmpty {
                                if showSuggestions {
                                    emptyState
                                        .listRowBackground(Color.SettingsBackground)
                                }
                            } else {
                                ForEach(categories) { category in
                                    HStack(spacing: 10) {
                                        Text(category.wrappedEmoji)
                                            .font(.system(.subheadline, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 15))
                                        Text(category.wrappedName)
                                            .font(.system(.body, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundColor(toDelete == category ? Color.AlertRed : Color.PrimaryText)

                                        Spacer()

                                        if !income {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(Color(hex: category.wrappedColour))
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .frame(minHeight: .settingsRowHeight)
                                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }

//                                .onDelete(perform: deleteItem)
                        }

                        SuggestedCategoriesView(income: income)
                    }
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                    .environment(\.defaultMinListRowHeight, .settingsRowHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if categories.isEmpty && !showSuggestions {
                emptyState
                    .allowsHitTesting(false)
            }
        }
        .background(Color.PrimaryBackground)
        .overlay(alignment: .top) {
            if showToast {
                GlassToast(title: toastTitle, systemImage: toastImage, color: toastColor)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(Color.PrimaryText)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .confirmationSheet(
            item: $toDelete,
            title: { "Delete '\($0.wrappedName)'?" },
            message: { "This action cannot be undone, and all \($0.wrappedName) transactions would be deleted." }
        ) { category in
            withAnimation {
                moc.delete(category)
                dataController.save()
            }
        }
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
        }) { category in
            if #available(iOS 16.0, *) {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: false)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.hidden)
            } else {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: true)
            }
        }
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: showSuggestions) { newValue in
            if !newValue {
                toastTitle = "Suggestions Hidden"
                toastImage = "eye.slash"
                showToast = true
                positive = true
            }
        }
    }

    private func moveItem(at sets: IndexSet, destination: Int) {
        let itemToMove = sets.first!

        if itemToMove < destination {
            var startIndex = itemToMove + 1
            let endIndex = destination - 1
            var startOrder = categories[itemToMove].order
            while startIndex <= endIndex {
                categories[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            categories[itemToMove].order = startOrder
        } else if destination < itemToMove {
            var startIndex = destination
            let endIndex = itemToMove - 1
            var startOrder = categories[destination].order + 1
            let newOrder = categories[destination].order
            while startIndex <= endIndex {
                categories[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            categories[itemToMove].order = newOrder
        }

        do {
            dataController.save()
        } catch {
            print(error.localizedDescription)
        }
    }

    init(income: Binding<Bool>, mode: CategoryViewMode, showToast: Binding<Bool>, toastTitle: Binding<String>, toastImage: Binding<String>, positive: Binding<Bool>) {
        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: NSPredicate(format: "income = %d", income.wrappedValue))

        _income = income
        _showToast = showToast
        _toastTitle = toastTitle
        _toastImage = toastImage
        _positive = positive
        self.mode = mode
    }
}

struct NewCategoryAlert: View {
    @Binding var income: Bool
    let budgetMode: Bool
    let bottomSpacers: Bool

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var incomeTracking: Bool = true

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    // existing categories

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", true)) private var incomeCategories: FetchedResults<Category>
    @State private var availableColours: [String] = Color.colorArray

    // state
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    // toasts
    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    var addButtonDisabled: Bool {
        return newName.trimmingCharacters(in: .whitespacesAndNewlines) == "" || newEmoji == ""
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

//    @State var isFetching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()
            }
            .frame(height: 44)
            .overlay {
                if showToast {
                    GlassToast(title: toastTitle, systemImage: toastImage, color: toastColor)
                } else if expenseCategories.count == 24 {
                    CategoryEditorTitle(title: "Income Category")
                } else if budgetMode {
                    CategoryEditorTitle(title: "Expense Category")
                } else if !incomeTracking {
                    CategoryEditorTitle(title: income ? "Income Category" : "Expense Category")
                } else {
                    GlassSegmentedPicker(selection: $income, options: [
                        (value: false, title: "Expense"),
                        (value: true, title: "Income")
                    ])
                }
            }

            Spacer(minLength: 16)

            ZStack {
                EmojiTextField(text: $newEmoji)
                    .focused($focusedField, equals: .emoji)
                    .onReceive(Just(newEmoji), perform: { _ in
                        if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                            self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                        } else {
                            self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                        }
                    })
                    .font(.system(size: 160))
                    .padding(8)
                    .frame(width: 96, height: 96, alignment: .center)

                if newEmoji == "" {
                    Image("emoji-happy")
                        .resizable()
                        .foregroundColor(Color.PrimaryText)
                        .frame(width: 38, height: 38, alignment: .center)
                        .allowsHitTesting(false)
                }
            }
            .glassField(in: RoundedRectangle(cornerRadius: 28, style: .continuous), isFocused: focusedField == .emoji && !showingColourPicker)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                    if !income {
                        Button {
                            showingColourPicker = true
                        } label: {
                            CategoryColourSwatch(colour: selectedColour, isActive: showingColourPicker)
                        }
                        .buttonStyle(.plain)
                        .popover(present: $showingColourPicker, attributes: {
                            $0.position = .absolute(
                                originAnchor: .topLeft,
                                popoverAnchor: .bottomLeft
                            )
                            $0.rubberBandingMode = .none
                            $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                            $0.presentation.animation = .easeInOut(duration: 0.2)
                            $0.dismissal.animation = .easeInOut(duration: 0.3)
                        }) {
                            ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker)
                                .environment(\.managedObjectContext, self.moc)

                        } background: {
                            Color.PrimaryBackground.opacity(0.3)
                        }
                    }

                    NormalTextField(text: $newName, placeholder: "Category Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .foregroundColor(Color.PrimaryText)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .glassField(in: Capsule(), isFocused: focusedField == .name && !showingColourPicker)

                    CategoryConfirmButton(systemImage: "plus", accessibilityLabel: "Add Category", action: verification)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: bottomSpacers ? 350 : .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetBackground()
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: expenseCategories.count) { _ in
            if expenseCategories.count == 24 {
                dismiss()
            }
        }
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: customSelectedColor) { _ in
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onAppear {
            if expenseCategories.count == 24 {
                income = true
            }

            if !income {
                expenseCategories.forEach { category in
                    if availableColours.contains(category.wrappedColour) {
                        availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                    }
                }

                if availableColours.isEmpty {
                    selectedColour = "#FFFFFF"
                } else {
                    selectedColour = availableColours[0]
                }
            }
        }
    }

    func verification() {
        let results = dataController.categoryCheck(name: newName, emoji: newEmoji, income: income)

        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"

                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"

                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            default:
                return
            }

            positive = false
            showToast = true

        } else {
            toastTitle = "Added \(newName)"

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            if income {
                let category = Category(context: moc)
                category.name = newName.trimmingCharacters(in: .whitespaces).capitalized
                category.emoji = newEmoji
                category.dateCreated = Date.now
                category.id = UUID()
                category.colour = "IncomeGreen"
                category.order = results.order
                category.income = true
                dataController.save()

                newName = ""
                newEmoji = ""
            } else {
                let category = Category(context: moc)
                category.name = newName.trimmingCharacters(in: .whitespaces).capitalized
                category.emoji = newEmoji
                category.dateCreated = Date.now
                category.id = UUID()
                category.income = false

                category.colour = selectedColour
                category.order = results.order

                dataController.save()

                newName = ""
                newEmoji = ""

                availableColours = Color.colorArray
                expenseCategories.forEach { category in
                    if availableColours.contains(category.wrappedColour) {
                        availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                    }
                }

                if availableColours.isEmpty {
                    selectedColour = "#FFFFFF"
                } else {
                    selectedColour = availableColours[0]
                }
            }

            if budgetMode {
                dismiss()
                return
            } else {
                focusedField = .emoji
                toastImage = "checkmark.circle.fill"
                positive = true
                showToast = true
            }
        }
    }

//    func GPTRecommendations(emoji: String, income: Bool) {
//        guard let url = URL(string: "https://api.openai.com/v1/completions") else {
//            return
//        }
//
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//
//        let parameters: [String:Any] = ["model":"text-davinci-003", "prompt":"What is the likely transaction category name for a \(income ? "income" : "expense") category with the emoji \(emoji)?", "temperature":0.9]
//
//        // Convert parameters into JSON data
//        let postData = try? JSONSerialization.data(withJSONObject: parameters)
//
//        request.httpBody = postData
//        request.addValue("Bearer \(Constants.openAPIKey)", forHTTPHeaderField: "Authorization")
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        isFetching = true
//
//        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
//            DispatchQueue.main.async {
//
//                if let data = data {
//                    let decoder = JSONDecoder()
//
//                    do {
//                        // Decode data using your model structure
//                        let result = try decoder.decode(OpenAICompletionsResponse.self, from: data)
//                        self.newName = result.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
//                        isFetching = false
//                    } catch {
//                        print("Failed to decode JSON")
//                        isFetching = false
//                    }
//                } else if let error = error {
//                    print("HTTP Request Failed \(error.localizedDescription)")
//                    isFetching = false
//                }
//            }
//        }
//
//        task.resume()
//    }

    init(income: Binding<Bool>, bottomSpacers: Bool, budgetMode: Bool = false) {
        _income = income
        self.budgetMode = budgetMode
        self.bottomSpacers = bottomSpacers
    }
}

struct EditCategoryAlert: View {
    let toEdit: Category
    @Binding var showRootToast: Bool
    @Binding var rootToastTitle: String
    @Binding var rootToastImage: String
    @Binding var positive: Bool

    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @Namespace var animation

    // existing categories

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>

    // state
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    // toasts
    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // delete mode
    @State private var deleteMode = false
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()

                GlassIconButton(
                    systemName: "trash.fill",
                    accessibilityLabel: "Delete",
                    foreground: Color.AlertRed,
                    tint: Color.AlertRed.opacity(0.2),
                    fallback: Color.AlertRed.opacity(0.23)
                ) {
                    toDelete = toEdit
                }
            }
            .frame(height: 44)
            .overlay {
                if showToast {
                    GlassToast(title: toastTitle, systemImage: toastImage, color: Color.AlertRed)
                } else {
                    CategoryEditorTitle(title: toEdit.income ? "Income" : "Expense")
                }
            }

            Spacer(minLength: 16)

            ZStack {
                EmojiTextField(text: $newEmoji)
                    .focused($focusedField, equals: .emoji)
                    .onReceive(Just(newEmoji), perform: { _ in
                        if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                            self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                        } else {
                            self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                        }
                    })
                    .font(.system(size: 160))
                    .padding(8)
                    .frame(width: 96, height: 96, alignment: .center)

                if newEmoji == "" {
                    Image("emoji-happy")
                        .resizable()
                        .foregroundColor(Color.PrimaryText)
                        .frame(width: 38, height: 38, alignment: .center)
                        .allowsHitTesting(false)
                }
            }
            .glassField(in: RoundedRectangle(cornerRadius: 28, style: .continuous), isFocused: focusedField == .emoji && !showingColourPicker)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                    if !toEdit.income {
                        Button {
                            showingColourPicker = true
                        } label: {
                            CategoryColourSwatch(colour: selectedColour, isActive: showingColourPicker)
                        }
                        .buttonStyle(.plain)
                        .popover(present: $showingColourPicker, attributes: {
                            $0.position = .absolute(
                                originAnchor: .topLeft,
                                popoverAnchor: .bottomLeft
                            )
                            $0.rubberBandingMode = .none
                            $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                            $0.presentation.animation = .easeInOut(duration: 0.2)
                            $0.dismissal.animation = .easeInOut(duration: 0.3)
                        }) {
                            ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker, toEdit: toEdit)
                                .environment(\.managedObjectContext, self.moc)

                        } background: {
                            Color.PrimaryBackground.opacity(0.3)
                        }
                    }

                    NormalTextField(text: $newName, placeholder: "Category Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .foregroundColor(Color.PrimaryText)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .glassField(in: Capsule(), isFocused: focusedField == .name && !showingColourPicker)

                    CategoryConfirmButton(systemImage: "checkmark", accessibilityLabel: "Save Category", action: verification)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: bottomSpacers ? 350 : .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetBackground()
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .sheet(item: $toDelete, onDismiss: {
            toDelete = nil
        }) { category in
            DeleteCategoryAlert(toDelete: category, deleted: $deleteMode)
        }
        .onChange(of: expenseCategories.count) { _ in
            if expenseCategories.count == 24 {
                dismiss()
            }
        }
        .onChange(of: customSelectedColor) { _ in
            print("changed")
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onChange(of: deleteMode) { _ in
            dismiss()
        }
        .onAppear {
            newName = toEdit.wrappedName
            newEmoji = toEdit.wrappedEmoji
            selectedColour = toEdit.wrappedColour
        }
    }

    func verification() {
        let results = dataController.categoryCheckEdit(name: newName, emoji: newEmoji, toEdit: toEdit)

        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"

                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"

                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            default:
                return
            }

            showToast = true
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            if toEdit.income {
                toEdit.name = newName.trimmingCharacters(in: .whitespaces).capitalized
                toEdit.emoji = newEmoji

                dataController.save()
            } else {
                toEdit.name = newName.trimmingCharacters(in: .whitespaces).capitalized
                toEdit.emoji = newEmoji
                toEdit.colour = selectedColour

                dataController.save()
            }

            rootToastTitle = "Edited \(newName)"
            rootToastImage = "checkmark.circle.fill"
            positive = true
            showRootToast = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                dismiss()
            }
        }
    }
}

struct DeleteCategoryAlert: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss
    let toDelete: Category
    @Binding var deleted: Bool

    var body: some View {
        ConfirmationSheet(
            title: "Delete '\(toDelete.wrappedName)'?",
            message: "This action cannot be undone, and all \(toDelete.wrappedName) transactions would be deleted."
        ) {
            ConfirmationDestructiveButton {
                deleted = true
                dismiss()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        moc.delete(toDelete)
                        dataController.save()
                    }
                }
            }

            ConfirmationCancelButton {
                dismiss()
            }
        }
    }
}

struct SuggestedCategoriesView: View {
    let income: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    @AppStorage("categorySuggestions", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showSuggestions: Bool = true

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    var nameArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedName)
        }

        return emptyArray
    }

    var emojiArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedEmoji)
        }

        return emptyArray
    }

    var suggestions: [SuggestedCategory] {
        var holding = [SuggestedCategory]()

        if income {
            SuggestedCategory.incomes.forEach { category in
                if !nameArray.contains(category.name) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        } else {
            SuggestedCategory.expenses.forEach { category in
                if !nameArray.contains(category.name) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        }

        return holding
    }

    @State private var availableColours: [String] = Color.colorArray
    @State private var selectedColour = "1"

    var body: some View {
        if !suggestions.isEmpty {
            Section(header: suggestionsHeader) {
                if showSuggestions {
                    suggestionRows
                }
            }
            .onAppear {
                if !income {
                    categories.forEach { category in
                        if availableColours.contains(category.wrappedColour) {
                            availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                        }
                    }

                    if availableColours.isEmpty {
                        selectedColour = "#FFFFFF"
                    } else {
                        selectedColour = availableColours[0]
                    }
                }
            }
        }
    }

    private var suggestionsHeader: some View {
        HStack {
            Text("Suggested")

            Spacer()

            SectionHeaderButton(
                title: showSuggestions ? "Hide Suggestions" : "Show Suggestions",
                systemImage: showSuggestions ? "eye.slash" : "eye"
            ) {
                withAnimation {
                    showSuggestions.toggle()
                }
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .frame(height: 32)
        .foregroundColor(Color.SubtitleText)
        .textCase(.uppercase)
        .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
    }

    private var suggestionRows: some View {
                ForEach(suggestions, id: \.self) { category in
                    HStack(spacing: 8) {
                        Text(category.emoji)
//                            .font(.system(size: 15))
                            .font(.system(.subheadline, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Text(LocalizedStringKey(category.name))
                            .font(.system(.body, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "plus")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .accessibilityLabel("Add")
                    }
                    .foregroundColor(Color.PrimaryText)
                    .frame(minHeight: .settingsRowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
                    .listRowBackground(Color.SettingsBackground)
                    .listRowSeparatorTint(Color.Outline)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // double check

                        let (outcome, _) = dataController.categoryCheck(name: category.name, emoji: category.emoji, income: income)

                        if outcome != .none {
                            return
                        }

                        let impactMed = UIImpactFeedbackGenerator(style: .light)
                        impactMed.impactOccurred()

                        if !income {
                            let suggestedCategory = Category(context: moc)
                            suggestedCategory.name = NSLocalizedString(category.name, comment: "category name")
                            suggestedCategory.emoji = category.emoji
                            suggestedCategory.dateCreated = Date.now
                            suggestedCategory.id = UUID()
                            suggestedCategory.colour = selectedColour
                            suggestedCategory.order = (categories.last?.order ?? 0) + 1
                            suggestedCategory.income = false
                            dataController.save()

                            availableColours = Color.colorArray
                            categories.forEach { category in
                                if availableColours.contains(category.wrappedColour) {
                                    availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                                }
                            }

                            if availableColours.isEmpty {
                                selectedColour = "#FFFFFF"
                            } else {
                                selectedColour = availableColours[0]
                            }
                        } else {
                            let suggestedCategory = Category(context: moc)
                            suggestedCategory.name = NSLocalizedString(category.name, comment: "category name")
                            suggestedCategory.emoji = category.emoji
                            suggestedCategory.dateCreated = Date.now
                            suggestedCategory.id = UUID()
                            suggestedCategory.colour = "#76FBB0"
                            suggestedCategory.order = (categories.last?.order ?? 0) + 1
                            suggestedCategory.income = true
                            dataController.save()
                        }
                    }
                }
    }

    init(income: Bool) {
        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: NSPredicate(format: "income = %d", income))

        self.income = income
    }
}

struct CategoryEditorTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundColor(Color.PrimaryText)
    }
}

struct CategoryColourSwatch: View {
    let colour: String
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: colour))
            .frame(width: 28, height: 28)
            .frame(width: 50, height: 50)
            .glassField(in: Circle(), isFocused: isActive)
            .contentShape(Circle())
            .accessibilityLabel("Colour")
    }
}

struct CategoryConfirmButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.LightIcon)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Circle(), tint: Color.DarkBackground, fallback: Color.DarkBackground)
        .accessibilityLabel(accessibilityLabel)
    }
}

class UIEmojiTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        .activeInputModes.first(where: { $0.primaryLanguage == "emoji" })
    }

    override func caretRect(for _: UITextPosition) -> CGRect {
        return CGRect.zero
    }
}

struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeUIView(context: Context) -> UIEmojiTextField {
        let emojiTextField = UIEmojiTextField()
        emojiTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        emojiTextField.placeholder = placeholder
        emojiTextField.text = text
        emojiTextField.delegate = context.coordinator
        emojiTextField.font = UIFont(name: "HelveticaNeue", size: 50)
        emojiTextField.textAlignment = .center
        emojiTextField.endFloatingCursor()
        emojiTextField.becomeFirstResponder()
        return emojiTextField
    }

    func updateUIView(_ uiView: UIEmojiTextField, context _: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField

        init(parent: EmojiTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = textField.text ?? ""
            }
        }
    }
}

struct NormalTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var action: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.placeholder = placeholder
        textField.autocapitalizationType = .words
        textField.text = text
        textField.delegate = context.coordinator

        textField.font = UIFont.roundedSpecial(ofStyle: .title2, weight: .medium, size: 17)
//
//        UIFont.rounded(ofSize: 20, weight: .medium)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NormalTextField

        init(parent: NormalTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = textField.text ?? ""
            }
        }

        func textFieldShouldReturn(_: UITextField) -> Bool {
            parent.action()

            return true
        }
    }
}

struct ColourPickerView: View {
    var selectedColours: [String]

    @Binding var showMenu: Bool
    @Binding var selectedColour: String

    @Binding var showNativePicker: Bool

    @State var customMode: Bool = false
    @State var customSelectedColor = Color.white

    @State var testing = false
    let columns = [
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40))
    ]

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Color.colorArray, id: \.self) { suggestedColor in
                if suggestedColor == "#" {
                    ZStack {
                        Circle()
                            .fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .pink]), center: .center))

                        Circle()
                            .fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground"))
                            .padding(4)

                        Circle()
                            .fill(customSelectedColor)
                            .padding(8)

                        if customMode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(customSelectedColor.luminance() > 0.5 ? Color.black : Color.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.black)
                        }
                    }
                    .frame(width: 40, height: 40, alignment: .center)
                    .onTapGesture {
                        showMenu = false
                        showNativePicker = true
                    }
                } else {
                    Circle()
                        .fill(Color(hex: suggestedColor))
                        .frame(height: 40)
                        .opacity(selectedColours.contains(suggestedColor) ? 0.2 : 1)
                        .onTapGesture {
                            if !selectedColours.contains(suggestedColor) {
                                withAnimation {
                                    selectedColour = suggestedColor
                                    customMode = false
                                    showMenu = false
                                }
                            }
                        }
                        .overlay {
                            if selectedColour == suggestedColor && !customMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color.black)
                            }
                        }
                }
            }
        }
        .padding(10)
        .frame(width: 290)
        .glassPopoverBackground(cornerRadius: 26)
    }

    init(selectedColor: Binding<String>, showMenu: Binding<Bool>, showNativePicker: Binding<Bool>, toEdit: Category? = nil) {
        _selectedColour = selectedColor
        _showMenu = showMenu
        _showNativePicker = showNativePicker

        if !Color.colorArray.contains(selectedColor.wrappedValue) {
            _customMode = State(initialValue: true)
            _customSelectedColor = State(initialValue: Color(hex: selectedColor.wrappedValue))
        }

        var selectedColours = [String]()

        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false)

        categories.forEach { category in
            selectedColours.append(category.wrappedColour)
        }

        if let editted = toEdit {
            if !selectedColours.isEmpty {
                selectedColours.remove(at: selectedColours.firstIndex(of: editted.wrappedColour) ?? 0)
            }
        }

        self.selectedColours = selectedColours
    }
}

struct OpenAICompletionsResponse: Decodable {
    let id: String
    let choices: [OpenAICompletionsOptions]
}

struct OpenAICompletionsOptions: Decodable {
    let text: String
}
