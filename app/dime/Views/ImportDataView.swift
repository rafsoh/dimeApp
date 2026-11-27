//
//  ImportDataView.swift
//  dime
//
//  Created by Rafael Soh on 21/8/23.
//

import ConfettiSwiftUI
import CoreData
import SwiftUI
import UniformTypeIdentifiers

private enum ImportStep: Int, Comparable {
    case start, columns, categories, review, finished

    static func < (lhs: ImportStep, rhs: ImportStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private enum ImportCategoryChoice: Hashable {
    case create
    case existing(Category)
    /// Imported without a category.
    case uncategorised
}

struct ImportDataView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var dataController = DataController.shared

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"

    @State private var step = ImportStep.start
    @State private var movingForward = true

    @State private var fileName = ""
    @State private var table: CSVTable?
    @State private var mapping = ColumnMapping()
    @State private var dateFormat = ""
    @State private var dateFormatOptions: [String] = []
    @State private var customDateFormat = ""
    @State private var editingCustomFormat = false
    @State private var parsed = ImportParseResult(rows: [], skipped: [:])

    @State private var categories: [Category] = []
    @State private var choices: [ImportCategoryKey: ImportCategoryChoice] = [:]
    @State private var incomeOverrides: [ImportCategoryKey: Bool] = [:]

    @State private var duplicateRows: Set<Int> = []
    @State private var skipDuplicates = true

    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var confetti = 0

    @State private var choosingFile = false
    @State private var sharingSample = false

    @State private var showToast = false
    @State private var toastTitle = ""

    @FocusState private var customFormatFocused: Bool

    private let stepAnimation = Animation.spring(response: 0.42, dampingFraction: 0.88)

    var body: some View {
        ZStack {
            stepContent
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tabHeader {
            header
                .padding(.top, 20)
                .padding(.bottom, 8)
                .padding(.horizontal, .settingsPageInset)
        }
        .bottomBar {
            bottomButtons
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, .settingsPageInset)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color.PrimaryBackground)
        .modifier(TransactionSheetPresentation())
        .interactiveDismissDisabled((step != .start && step != .finished) || isImporting)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            switch result {
            case let .success(url):
                load(url)
            case .failure:
                toast("Couldn't Open File")
            }
        }
        .sheet(isPresented: $sharingSample) {
            if let url = Bundle.main.url(forResource: "sample", withExtension: "csv") {
                ActivityViewController(activityItems: [url])
            }
        }
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .confettiCannon(counter: $confetti, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .sideBarSheet {
            SideBarCloseItem(isBack: step != .start && step != .finished, isShown: !isImporting) { goBack() }
        }
    }

    // MARK: - Chrome

    var header: some View {
        HStack {
            if !isImporting {
                GlassIconButton(systemName: step == .start || step == .finished ? "xmark" : "chevron.left", accessibilityLabel: step == .start || step == .finished ? "Close" : "Back") {
                    goBack()
                }
                .hiddenInSideBar()
            }

            Spacer()

            if step > .start, step < .finished {
                StepLabel(current: step.rawValue, total: 3)
            }
        }
        .frame(height: 44)
        .overlay {
            if showToast {
                GlassToast(title: toastTitle, systemImage: "exclamationmark.triangle.fill", color: Color.AlertRed)
            }
        }
    }

    @ViewBuilder var bottomButtons: some View {
        switch step {
        case .start:
            VStack(spacing: 10) {
                PrimaryImportButton(title: "Choose CSV File") {
                    choosingFile = true
                }

                ConfirmationCancelButton("Get a Sample File") {
                    sharingSample = true
                }
            }
        case .columns:
            PrimaryImportButton(title: "Continue") {
                confirmColumns()
            }
        case .categories:
            PrimaryImportButton(title: "Continue") {
                findDuplicates()
                advance(to: .review)
            }
        case .review:
            let count = rowsToImport.count
            PrimaryImportButton(title: count == 1 ? "Import 1 Transaction" : "Import \(count) Transactions", enabled: count > 0) {
                runImport()
            }
        case .finished:
            if !isImporting {
                PrimaryImportButton(title: "Done") {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder var stepContent: some View {
        switch step {
        case .start:
            startStep
        case .columns:
            columnsStep
        case .categories:
            categoriesStep
        case .review:
            reviewStep
        case .finished:
            finishedStep
        }
    }

    // MARK: - Start

    var startStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                StepTitle(title: "Import Transactions", subtitle: "Bring in your history from a spreadsheet or another app. Dime reads CSV files and works out the columns for you.")

                VStack(alignment: .leading, spacing: 18) {
                    RequirementRow(systemImage: ImportField.date.systemImage, title: "Date", subtitle: "Any common format, with or without a time.")
                    RequirementRow(systemImage: ImportField.amount.systemImage, title: "Amount", subtitle: "Currency symbols, separators and negative amounts are fine.")
                    RequirementRow(systemImage: ImportField.category.systemImage, title: "Category", subtitle: "Matched to your categories, or created for you.")
                    RequirementRow(systemImage: ImportField.note.systemImage, title: "Note", subtitle: "Optional.")
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            .padding(.horizontal, .settingsPageInset)
        }
    }

    // MARK: - Columns

    var columnsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                StepTitle(title: "Match Columns", subtitle: "Dime matched the columns in \(fileName). Tap a column to change it.")

                VStack(spacing: 0) {
                    ForEach(ImportField.allCases, id: \.self) { field in
                        columnRow(field)

                        if field != ImportField.allCases.last {
                            Divider()
                        }
                    }
                }
                .settingsSectionRows()

                if mapping[.date] != nil {
                    dateFormatSection
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            .padding(.horizontal, .settingsPageInset)
        }
        .scrollDismissesKeyboardInteractively()
    }

    func columnRow(_ field: ImportField) -> some View {
        let selection = Binding<Int?>(
            get: { mapping[field] },
            set: { newValue in
                mapping[field] = newValue
                columnsChanged(dateColumnChanged: field == .date)
            }
        )

        return HStack(spacing: 12) {
            FieldIcon(systemImage: field.systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(field.title))
                    .font(.app(.body, weight: .medium))
                    .foregroundColor(Color.PrimaryText)

                if let column = selection.wrappedValue, let sample = sampleValue(in: column) {
                    Text(sample)
                        .font(.app(.footnote))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                } else {
                    Text(field.isRequired ? "Required" : "Optional")
                        .font(.app(.footnote))
                        .foregroundColor(field.isRequired ? Color.AlertRed : Color.SubtitleText)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Picker(selection: selection) {
                    if !field.isRequired {
                        Text("None").tag(Int?.none)
                    }

                    if let table {
                        ForEach(0 ..< table.columnCount, id: \.self) { column in
                            Text(columnMenuTitle(column)).tag(Int?.some(column))
                        }
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                MenuChip(title: selection.wrappedValue.map { table?.headers[$0] ?? "" } ?? (field.isRequired ? NSLocalizedString("Choose", comment: "pick a column") : NSLocalizedString("None", comment: "no column picked")), dimmed: selection.wrappedValue == nil)
            }
        }
        .importRowHeight()
    }

    var dateFormatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Date Format")
                            .font(.app(.body, weight: .medium))
                            .foregroundColor(Color.PrimaryText)

                        if let sample = dateSample {
                            if let reading = ImportParsing.date(sample, format: dateFormat) {
                                Text("Reads as \(reading.formatted(.dateTime.day().month(.abbreviated).year()))")
                                    .font(.app(.footnote))
                                    .foregroundColor(Color.SubtitleText)
                                    .lineLimit(1)
                            } else {
                                Text("Dime can't read \(sample)")
                                    .font(.app(.footnote))
                                    .foregroundColor(Color.AlertRed)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Menu {
                        ForEach(dateFormatOptions, id: \.self) { format in
                            Button {
                                editingCustomFormat = false
                                setDateFormat(format)
                            } label: {
                                if format == dateFormat && !editingCustomFormat {
                                    Label(dateFormatMenuTitle(format), systemImage: "checkmark")
                                } else {
                                    Text(dateFormatMenuTitle(format))
                                }
                            }
                        }

                        Button {
                            customDateFormat = dateFormat
                            editingCustomFormat = true
                            customFormatFocused = true
                        } label: {
                            Label("Custom Format", systemImage: "pencil")
                        }
                    } label: {
                        MenuChip(title: editingCustomFormat ? NSLocalizedString("Custom", comment: "a custom date format") : dateFormat, dimmed: false)
                    }
                }
                .importRowHeight()

                if editingCustomFormat || dateFormatOptions.isEmpty {
                    Divider()

                    TextField("e.g. dd/MM/yyyy HH:mm", text: $customDateFormat)
                        .font(.app(.body, weight: .medium))
                        .foregroundColor(Color.PrimaryText)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .focused($customFormatFocused)
                        .importRowHeight()
                        .onChange(of: customDateFormat) { newValue in
                            setDateFormat(newValue.trimmingCharacters(in: .whitespaces))
                        }
                }
            }
            .settingsSectionRows()

            if editingCustomFormat || dateFormatOptions.isEmpty {
                Text("Use d for day, M for month, y for year, H for hour and m for minute, with the same separators as the file.")
                    .font(.app(.footnote))
                    .foregroundColor(Color.SubtitleText)
                    .padding(.horizontal, .settingsRowInset)
            }
        }
    }

    // MARK: - Categories

    var categoriesStep: some View {
        let keys = parsed.categoryKeys

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                StepTitle(title: "Link Categories", subtitle: "Each category in your file is linked to one in Dime. Anything new is created for you, and you can edit it later.")

                VStack(spacing: 0) {
                    ForEach(keys.indices, id: \.self) { index in
                        categoryRow(keys[index].key, count: keys[index].count)

                        if index < keys.count - 1 {
                            Divider()
                        }
                    }
                }
                .settingsSectionRows()
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            .padding(.horizontal, .settingsPageInset)
        }
    }

    func categoryRow(_ key: ImportCategoryKey, count: Int) -> some View {
        let income = income(for: key)
        let current = choice(for: key)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name.isEmpty ? Uncategorised.name : key.name)
                    .font(.app(.body, weight: .medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(count == 1 ? "1 transaction" : "\(count) transactions")

                    Text("·")

                    if key.income == nil {
                        Menu {
                            Picker(selection: Binding(get: { income }, set: { incomeOverrides[key] = $0 })) {
                                Text("Expense").tag(false)
                                Text("Income").tag(true)
                            } label: {
                                EmptyView()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(income ? "Income" : "Expense")
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.app(.caption2, weight: .semibold))
                            }
                            .foregroundColor(Color.PrimaryText)
                        }
                    } else {
                        Text(income ? "Income" : "Expense")
                    }
                }
                .font(.app(.footnote))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                if !key.name.isEmpty {
                    Button {
                        choices[key] = .create
                    } label: {
                        if current == .create {
                            Label("New Category", systemImage: "checkmark")
                        } else {
                            Label("New Category", systemImage: "plus")
                        }
                    }
                }

                Button {
                    choices[key] = .uncategorised
                } label: {
                    if current == .uncategorised {
                        Label("No Category", systemImage: "checkmark")
                    } else {
                        Label("No Category", systemImage: Uncategorised.symbol(income: income))
                    }
                }

                Section(income ? "Income Categories" : "Expense Categories") {
                    ForEach(categories.filter { $0.income == income }, id: \.self) { category in
                        Button {
                            choices[key] = .existing(category)
                        } label: {
                            if current == .existing(category) {
                                Label(category.fullName, systemImage: "checkmark")
                            } else {
                                Text(category.fullName)
                            }
                        }
                    }
                }
            } label: {
                CategoryChip(choice: current, name: key.name, income: income)
            }
        }
        .importRowHeight()
    }

    // MARK: - Review

    var reviewStep: some View {
        let rows = rowsToImport
        let converter = CurrencyConverter.current()
        let expenseTotal = converter.total(of: rows.filter { !income(for: $0) }.map { $0.money(income: false) })
        let incomeTotal = converter.total(of: rows.filter { income(for: $0) }.map { $0.money(income: true) })
        let expenses = expenseTotal.value
        let incomes = incomeTotal.value
        let newCategories = parsed.categoryKeys.filter { choice(for: $0.key) == .create }.count

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                StepTitle(title: "Review Import", subtitle: "Here's what will be added to Dime.")

                VStack(spacing: 0) {
                    SummaryRow(title: "Transactions", value: "\(rows.count)", color: Color.PrimaryText)

                    if let first = rows.map(\.date).min(), let last = rows.map(\.date).max() {
                        Divider()
                        SummaryRow(title: "Dates", value: dateRange(first, last), color: Color.PrimaryText)
                    }

                    Divider()
                    SummaryRow(title: "Expenses", value: expenseTotal.report.marking(formatted(expenses, income: nil)), color: Color.PrimaryText)
                    Divider()
                    SummaryRow(title: "Income", value: incomeTotal.report.marking(formatted(incomes, income: nil)), color: Color.IncomeGreen)
                    Divider()
                    SummaryRow(title: "New Categories", value: "\(newCategories)", color: Color.PrimaryText)

                    if !duplicateRows.isEmpty {
                        Divider()

                        Toggle(isOn: $skipDuplicates.animation()) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Skip Duplicates")
                                    .font(.app(.body, weight: .medium))
                                    .foregroundColor(Color.PrimaryText)

                                Text(duplicateRows.count == 1 ? "1 transaction is already in Dime" : "\(duplicateRows.count) transactions are already in Dime")
                                    .font(.app(.footnote))
                                    .foregroundColor(Color.SubtitleText)
                            }
                        }
                        .tint(.green)
                        .importRowHeight()
                    }
                }
                .settingsSectionRows()

                if parsed.skippedCount > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ImportSkipReason.allCases.filter { (parsed.skipped[$0] ?? 0) > 0 }, id: \.self) { reason in
                            let count = parsed.skipped[reason] ?? 0
                            Text(count == 1 ? "1 row \(NSLocalizedString(reason.description, comment: "")) will be skipped." : "\(count) rows \(NSLocalizedString(reason.description, comment: "")) will be skipped.")
                        }
                    }
                    .font(.app(.footnote))
                    .foregroundColor(Color.SubtitleText)
                    .padding(.horizontal, .settingsRowInset)
                    .padding(.top, -16)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            .padding(.horizontal, .settingsPageInset)
        }
    }

    // MARK: - Finished

    var finishedStep: some View {
        VStack(spacing: 16) {
            if isImporting {
                ProgressView()
                    .controlSize(.large)

                Text("Importing")
                    .font(.app(.title2, weight: .semibold))
                    .foregroundColor(Color.SubtitleText)
            } else {
                Image(systemName: "checkmark")
                    .font(.app(size: 30, weight: .semibold))
                    .foregroundColor(Color.IncomeGreen)
                    .frame(width: 72, height: 72)
                    .glassBackground(in: Circle(), tint: Color.IncomeGreen.opacity(0.25), interactive: false, fallback: Color.IncomeGreen.opacity(0.23))

                VStack(spacing: 6) {
                    Text("Import Complete")
                        .font(.app(.title2, weight: .semibold))
                        .foregroundColor(Color.PrimaryText)

                    Text(importedCount == 1 ? "1 transaction was added to Dime." : "\(importedCount) transactions were added to Dime.")
                        .font(.app(.body))
                        .foregroundColor(Color.SubtitleText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, .settingsPageInset)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Navigation

    private func advance(to next: ImportStep) {
        hideKeyboard()
        movingForward = true
        withAnimation(stepAnimation) {
            step = next
        }
    }

    func goBack() {
        hideKeyboard()
        switch step {
        case .start, .finished:
            dismiss()
        case .columns:
            movingForward = false
            withAnimation(stepAnimation) {
                step = .start
            }
        case .categories:
            movingForward = false
            withAnimation(stepAnimation) {
                step = .columns
            }
        case .review:
            movingForward = false
            withAnimation(stepAnimation) {
                step = .categories
            }
        }
    }

    func toast(_ title: String) {
        toastTitle = title
        showToast = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Loading

    func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            toast("Couldn't Open File")
            return
        }

        // Spreadsheet apps often save CSVs in a legacy encoding.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) else {
            toast("Couldn't Read File")
            return
        }

        guard let table = CSVTable.parse(text) else {
            toast("No Transactions Found")
            return
        }

        self.table = table
        fileName = url.lastPathComponent
        mapping = ColumnMapping.detect(in: table)
        categories = dataController.getAllCategories(income: false) + dataController.getAllCategories(income: true)
        choices = [:]
        incomeOverrides = [:]
        editingCustomFormat = false
        detectDateFormat()
        reparse()

        advance(to: .columns)
    }

    func columnsChanged(dateColumnChanged: Bool) {
        if dateColumnChanged {
            editingCustomFormat = false
            detectDateFormat()
        }
        reparse()
    }

    func detectDateFormat() {
        guard let table, let column = mapping[.date] else {
            dateFormatOptions = []
            dateFormat = ""
            return
        }
        dateFormatOptions = ImportParsing.dateFormats(fitting: Array(table.column(column).prefix(200)))
        dateFormat = dateFormatOptions.first ?? ""
    }

    func setDateFormat(_ format: String) {
        guard format != dateFormat else { return }
        dateFormat = format
        reparse()
    }

    func reparse() {
        guard let table, mapping.isComplete, !dateFormat.isEmpty else {
            parsed = ImportParseResult(rows: [], skipped: [:])
            return
        }
        parsed = ImportParseResult.build(table: table, mapping: mapping, dateFormat: dateFormat)
    }

    func confirmColumns() {
        if let missing = ImportField.allCases.first(where: { $0.isRequired && mapping[$0] == nil }) {
            toast(String(format: NSLocalizedString("Choose a %@ Column", comment: "a column must be picked for a field"), NSLocalizedString(missing.title, comment: "")))
        } else if parsed.rows.isEmpty {
            toast(dateFormat.isEmpty || parsed.skipped[.date] != nil ? "Check the Date Format" : "No Readable Rows")
        } else {
            advance(to: .categories)
        }
    }

    // MARK: - Categories

    func income(for key: ImportCategoryKey) -> Bool {
        key.income ?? incomeOverrides[key] ?? false
    }

    func income(for row: ImportedRow) -> Bool {
        income(for: ImportCategoryKey(name: row.categoryName, income: row.income))
    }

    /// The user's choice while it still fits the category's type, otherwise a category with the same name, otherwise a new one.
    private func choice(for key: ImportCategoryKey) -> ImportCategoryChoice {
        let income = income(for: key)

        switch choices[key] {
        case let .existing(category) where category.income == income:
            return .existing(category)
        case .create where !key.name.isEmpty:
            return .create
        case .uncategorised:
            return .uncategorised
        case .existing, .create, nil:
            break
        }

        // A row without a category name can't name a new category.
        if key.name.isEmpty {
            return .uncategorised
        }

        if let match = categories.first(where: { $0.income == income && $0.wrappedName.compare(key.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return .existing(match)
        }
        return .create
    }

    // MARK: - Duplicates

    var rowsToImport: [ImportedRow] {
        guard skipDuplicates, !duplicateRows.isEmpty else { return parsed.rows }
        return parsed.rows.enumerated().filter { !duplicateRows.contains($0.offset) }.map(\.element)
    }

    func duplicateKey(date: Date, amount: Double, note: String, income: Bool, currencyCode: String?) -> String {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate
        let cents = Int((amount * 100).rounded())
        return "\(day)|\(cents)|\(note.trimmingCharacters(in: .whitespaces).lowercased())|\(income)|\((currencyCode ?? currency).uppercased())"
    }

    /// Rows that match a transaction already in Dime by day, amount, note and type. Each existing transaction matches
    /// one row, so repeated purchases in the file beyond what Dime has are still imported.
    func findDuplicates() {
        let dates = parsed.rows.map(\.date)
        guard let first = dates.min(), let last = dates.max(),
              let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: last))
        else {
            duplicateRows = []
            return
        }

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", Calendar.current.startOfDay(for: first) as NSDate, end as NSDate)

        var existing: [String: Int] = [:]
        for transaction in dataController.results(for: request) {
            existing[duplicateKey(date: transaction.wrappedDate, amount: transaction.amount, note: transaction.wrappedNote, income: transaction.income, currencyCode: transaction.currencyCode), default: 0] += 1
        }

        var duplicates = Set<Int>()
        for (index, row) in parsed.rows.enumerated() {
            // Notes left empty are saved as the category's name.
            let savedNote = row.note.isEmpty ? row.categoryName : row.note
            let key = duplicateKey(date: row.date, amount: row.amount, note: savedNote, income: income(for: row), currencyCode: row.currencyCode)
            if let count = existing[key], count > 0 {
                existing[key] = count - 1
                duplicates.insert(index)
            }
        }
        duplicateRows = duplicates
    }

    // MARK: - Import

    func runImport() {
        let rows = rowsToImport
        guard !rows.isEmpty else { return }

        isImporting = true
        advance(to: .finished)
        let transactionsBefore = dataController.transactionCount()

        // Lets the progress view appear before the main thread is busy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var created: [String: Category] = [:]
            var nextOrder: [Bool: Int64] = [
                false: (categories.filter { !$0.income }.map(\.order).max() ?? -1) + 1,
                true: (categories.filter { $0.income }.map(\.order).max() ?? -1) + 1
            ]
            var unusedColours = Color.colorArray.filter { colour in !categories.contains { $0.wrappedColour == colour } }

            for row in rows {
                let key = ImportCategoryKey(name: row.categoryName, income: row.income)
                let income = income(for: key)
                let category: Category?

                switch choice(for: key) {
                case let .existing(existing):
                    category = existing
                case .uncategorised:
                    category = nil
                case .create:
                    let createdKey = "\(row.categoryName.lowercased())|\(income)"
                    if let match = created[createdKey] {
                        category = match
                    } else {
                        let new = Category(context: dataController.container.viewContext)
                        new.id = UUID()
                        new.name = row.categoryName
                        new.emoji = ImportCategoryDefaults.emoji(for: row.categoryName, income: income)
                        new.dateCreated = Date.now
                        new.income = income
                        new.order = nextOrder[income] ?? 0
                        nextOrder[income] = new.order + 1
                        if income {
                            new.colour = "#76FBB1"
                        } else {
                            new.colour = unusedColours.isEmpty ? Color.colorArray[created.count % Color.colorArray.count] : unusedColours.removeFirst()
                        }
                        created[createdKey] = new
                        category = new
                    }
                }

                _ = dataController.insertTransaction(note: row.note, category: category, income: income, amount: row.amount, currencyCode: row.currencyCode ?? currency.uppercased(), date: row.date)
            }

            dataController.save()
            dataController.refreshExchangeRates()
            DataIntegrityLog.breadcrumb(
                "csv import finished",
                numbers: [
                    "rows": rows.count,
                    "categoriesCreated": created.count,
                    "transactionsBefore": transactionsBefore,
                    "transactionsAfter": dataController.transactionCount()
                ]
            )

            importedCount = rows.count
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(stepAnimation) {
                isImporting = false
            }
            confetti += 1
        }
    }

    // MARK: - Formatting

    func sampleValue(in column: Int) -> String? {
        table?.column(column).first { !$0.isEmpty }
    }

    var dateSample: String? {
        mapping[.date].flatMap { sampleValue(in: $0) }
    }

    func columnMenuTitle(_ column: Int) -> String {
        guard let table else { return "" }
        let header = table.headers[column]
        guard !table.hasHeaderRow, let sample = sampleValue(in: column) else { return header }
        return "\(header) · \(sample)"
    }

    /// Shows how a format reads the sample date, so formats like dd/MM and MM/dd can be told apart.
    func dateFormatMenuTitle(_ format: String) -> String {
        guard let sample = dateSample, let date = ImportParsing.date(sample, format: format) else { return format }
        return "\(date.formatted(.dateTime.day().month(.wide).year())) (\(format))"
    }

    func dateRange(_ first: Date, _ last: Date) -> String {
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        return (first ..< last).formatted(.interval.day().month(.abbreviated).year())
    }

    func formatted(_ amount: Double, income: Bool?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let text = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        switch income {
        case true?:
            return "+" + text
        case false?:
            return "-" + text
        case nil:
            return text
        }
    }
}

// MARK: - Components

private struct PrimaryImportButton: View {
    let title: LocalizedStringKey
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(.headline))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Capsule())
        }
        .whiteGlassButtonStyle()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct StepTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.app(.title, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.app(.body))
                .foregroundColor(Color.SubtitleText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StepLabel: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("Step \(current)/\(total)")
            .font(.app(.subheadline, weight: .semibold))
            .foregroundColor(Color.PrimaryText)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassBackground(in: Capsule(), tint: .glassTint, interactive: false)
            .accessibilityLabel(Text("Step \(current) of \(total)"))
    }
}

private struct FieldIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.app(.body, weight: .medium))
            .foregroundColor(Color.PrimaryText)
            .frame(width: 30, height: 30)
            .glassBackground(in: RoundedRectangle(cornerRadius: 8, style: .continuous), tint: .glassTint, interactive: false)
            .accessibilityHidden(true)
    }
}

private struct RequirementRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Color.PrimaryText)
                .frame(width: 44, height: 44)
                .glassBackground(in: RoundedRectangle(cornerRadius: 13, style: .continuous), interactive: false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)

                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundColor(Color.SubtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MenuChip: View {
    let title: String
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundColor(dimmed ? Color.SubtitleText : Color.PrimaryText)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.app(.caption, weight: .semibold))
                .foregroundColor(Color.SubtitleText)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .glassBackground(in: Capsule(), tint: .glassTint)
        .contentShape(Capsule())
        .frame(maxWidth: 170, alignment: .trailing)
    }
}

private struct CategoryChip: View {
    let choice: ImportCategoryChoice
    let name: String
    let income: Bool

    var body: some View {
        HStack(spacing: 6) {
            switch choice {
            case let .existing(category):
                let colour = Color(hex: category.wrappedColour)
                Text(category.wrappedEmoji)
                    .font(.app(.footnote))

                Text(category.wrappedName)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(colour)
                    .lineLimit(1)
            case .create:
                Text(ImportCategoryDefaults.emoji(for: name, income: income))
                    .font(.app(.footnote))

                Text("New")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
            case .uncategorised:
                Image(systemName: Uncategorised.symbol(income: income))
                    .font(.app(.footnote, weight: .bold))
                    .foregroundColor(Color(hex: Uncategorised.colour))

                Text("None")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.app(.caption, weight: .semibold))
                .foregroundColor(Color.SubtitleText)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            if case let .existing(category) = choice {
                Capsule().fill(Color(hex: category.wrappedColour).opacity(0.18))
            }
        }
        .glassBackground(in: Capsule(), tint: .glassTint)
        .contentShape(Capsule())
        .frame(maxWidth: 170, alignment: .trailing)
    }
}

private struct SummaryRow: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.app(.body, weight: .medium))
                .foregroundColor(Color.PrimaryText)

            Spacer(minLength: 8)

            Text(value)
                .font(.app(.body, weight: .semibold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
        }
        .importRowHeight()
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Settings' row height, with room for rows whose subtitle makes them taller at large text sizes.
    func importRowHeight() -> some View {
        padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]?

    func makeUIViewController(context _: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: UIViewControllerRepresentableContext<ActivityViewController>) {}
}
