//
//  ExportPeriodSheet.swift
//  dime
//

import Foundation
import SwiftUI

/// The span of history an export covers.
enum ExportPeriod: Hashable {
    case all
    case year(Int)
    case month(year: Int, month: Int)

    var year: Int? {
        switch self {
        case .all:
            return nil
        case let .year(year), let .month(year, _):
            return year
        }
    }

    func contains(year: Int, month: Int) -> Bool {
        switch self {
        case .all:
            return true
        case let .year(selected):
            return selected == year
        case let .month(selectedYear, selectedMonth):
            return selectedYear == year && selectedMonth == month
        }
    }
}

/// How many transactions fall in each month, grouped on the Gregorian calendar so every year has 12 months.
struct ExportCatalog {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        return calendar
    }()

    private var counts: [Int: [Int: Int]] = [:]

    init(dates: [Date] = []) {
        for date in dates {
            let parts = Self.calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { continue }
            counts[year, default: [:]][month, default: 0] += 1
        }
    }

    var isEmpty: Bool {
        counts.isEmpty
    }

    /// Newest first.
    var years: [Int] {
        counts.keys.sorted(by: >)
    }

    func count(year: Int, month: Int) -> Int {
        counts[year]?[month] ?? 0
    }

    func count(in period: ExportPeriod) -> Int {
        switch period {
        case .all:
            return counts.values.reduce(0) { $0 + $1.values.reduce(0, +) }
        case let .year(year):
            return counts[year]?.values.reduce(0, +) ?? 0
        case let .month(year, month):
            return count(year: year, month: month)
        }
    }

    /// The first day of the earliest and latest months in `period` that have transactions.
    func span(in period: ExportPeriod) -> (first: Date, last: Date)? {
        let months = counts.flatMap { year, months in
            months.keys.filter { period.contains(year: year, month: $0) }.map { year * 12 + $0 - 1 }
        }
        guard let first = months.min(), let last = months.max() else { return nil }
        let date = { (index: Int) in
            Self.calendar.date(from: DateComponents(year: index / 12, month: index % 12 + 1, day: 1)) ?? .now
        }
        return (date(first), date(last))
    }

    static func includes(_ date: Date, in period: ExportPeriod) -> Bool {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return false }
        return period.contains(year: year, month: month)
    }
}

/// CSV the importer already knows how to read. Dates use a fixed numeric
/// format (`yyyy-MM-dd HH:mm:ss Z`) so a later import can recover the same instant.
enum ExportCSV {
    static let dateFormat = "yyyy-MM-dd HH:mm:ss Z"

    static func text(for transactions: [Transaction], mainCurrency: String = CurrencyConverter.current().mainCurrency) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = dateFormat

        var csv = CSVExport.header
        for transaction in transactions.sorted(by: { $0.wrappedDate > $1.wrappedDate }) {
            let date = formatter.string(from: transaction.wrappedDate)
            let note = field(transaction.wrappedNote)
            // A transaction without a currency is in the main currency.
            let currencyCode = (transaction.currencyCode ?? mainCurrency).uppercased()
            let amount = CSVExport.amount(transaction.wrappedAmount, currencyCode: currencyCode)
            let category = field(transaction.category?.wrappedName ?? "")
            let type: String
            if transaction.isTransfer {
                type = transaction.income ? CSVExport.transferInType : CSVExport.transferOutType
            } else {
                type = transaction.income ? "Income" : "Expense"
            }
            let account = field(transaction.accountName)
            csv += "\(date),\(note),\(amount),\(category),\(type),\(currencyCode),\(account)\n"
        }
        return csv
    }

    static func write(_ csv: String, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private struct ExportSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Picks all of the history, a year, or a single month, then hands the CSV to the share sheet.
struct ExportPeriodSheet: View {
    let onExport: (URL) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [Transaction] = []
    @State private var catalog = ExportCatalog()
    @State private var period: ExportPeriod = .all
    @State private var contentHeight: CGFloat = 0

    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

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
    private var detents: Set<PresentationDetent> {
        if contentHeight == 0 {
            return [.height(320)]
        } else if contentHeight > UIScreen.main.bounds.height * 0.9 {
            return [.large]
        } else {
            return [.height(contentHeight)]
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: "Export Data")
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)

            if catalog.isEmpty {
                emptyState
            } else {
                picker
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ExportSheetHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ExportSheetHeightKey.self) { height in
            contentHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .onAppear(perform: load)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .regular))
                .accessibilityHidden(true)

            Text("No transactions to export")
                .font(.system(.title3, design: .rounded).weight(.medium))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(Color.SubtitleText)
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 40)
        .accessibilityElement(children: .combine)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(String(localized: "All time"), isSelected: period == .all) {
                        select(.all)
                    }

                    ForEach(catalog.years, id: \.self) { year in
                        chip(String(year), isSelected: period.year == year) {
                            select(.year(year))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 24)

            if let year = period.year {
                LazyVGrid(columns: monthColumns, spacing: 8) {
                    ForEach(1 ... 12, id: \.self) { month in
                        monthCell(year: year, month: month)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .transition(.opacity)
            }

            Text(summary)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Button(action: export) {
                Text("Export")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.LightIcon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(in: Capsule(), tint: Color.DarkBackground, fallback: Color.DarkBackground)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundColor(isSelected ? Color.LightIcon : Color.PrimaryText)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(isSelected ? Color.DarkBackground : Color.PrimaryText.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(BouncyButton(duration: 0.15, scale: 0.95))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthCell(year: Int, month: Int) -> some View {
        let count = catalog.count(year: year, month: month)
        let isIncluded = count > 0 && period.contains(year: year, month: month)
        let isPicked = period == .month(year: year, month: month)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return Button {
            select(isPicked ? .year(year) : .month(year: year, month: month))
        } label: {
            Text(ExportCatalog.calendar.shortMonthSymbols[month - 1])
                .font(.system(.body, design: .rounded).weight(isIncluded ? .semibold : .regular))
                .foregroundColor(isIncluded ? Color.PrimaryText : Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(shape.fill(Color.PrimaryText.opacity(isIncluded ? 0.16 : 0.05)))
                .overlay {
                    if isPicked {
                        shape.strokeBorder(Color.PrimaryText, lineWidth: 2)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(BouncyButton(duration: 0.15, scale: 0.95))
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
        .accessibilityLabel(Text(monthTitle(ExportCatalog.calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now)) + Text(", ") + Text(transactionCount(count)))
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }

    private var summary: String {
        let count = transactionCount(catalog.count(in: period))
        guard let span = catalog.span(in: period) else { return count }
        if span.first == span.last {
            return "\(count) · \(monthTitle(span.first))"
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = ExportCatalog.calendar
        formatter.locale = .current
        formatter.dateTemplate = "MMMMyyyy"
        return "\(count) · \(formatter.string(from: span.first, to: span.last))"
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = ExportCatalog.calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: date)
    }

    private func transactionCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld transactions", comment: "How many transactions an export period contains"),
            count
        )
    }

    private func fileName(for period: ExportPeriod) -> String {
        switch period {
        case .all:
            return "dime-export"
        case let .year(year):
            return "dime-export-\(year)"
        case let .month(year, month):
            return String(format: "dime-export-%d-%02d", year, month)
        }
    }

    private func select(_ newPeriod: ExportPeriod) {
        guard newPeriod != period else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.2)) {
            period = newPeriod
        }
    }

    private func load() {
        guard transactions.isEmpty else { return }
        transactions = dataController.results(for: dataController.fetchRequestForExport())
        catalog = ExportCatalog(dates: transactions.map(\.wrappedDate))
    }

    private func export() {
        let included = transactions.filter { ExportCatalog.includes($0.wrappedDate, in: period) }
        guard !included.isEmpty, let url = ExportCSV.write(ExportCSV.text(for: included), named: fileName(for: period)) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onExport(url)
        dismiss()
    }
}
