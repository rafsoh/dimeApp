//
//  ExportPeriodSheet.swift
//  dime
//

import Foundation
import SwiftUI

/// A calendar month that has at least one transaction.
struct ExportYearMonth: Hashable, Comparable {
    var year: Int
    var month: Int

    static func < (lhs: ExportYearMonth, rhs: ExportYearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    static func of(_ date: Date, calendar: Calendar) -> ExportYearMonth? {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month, (1 ... 12).contains(month) else { return nil }
        return ExportYearMonth(year: year, month: month)
    }
}

/// Months and years that actually contain transactions, newest first, with counts.
struct ExportCatalog {
    struct Month: Identifiable {
        var period: ExportYearMonth
        var count: Int
        var id: ExportYearMonth { period }
    }

    struct Year: Identifiable {
        var year: Int
        var months: [Month]
        var count: Int
        var id: Int { year }
    }

    var years: [Year]
    var total: Int

    var allMonths: Set<ExportYearMonth> {
        Set(years.flatMap { $0.months.map(\.period) })
    }

    func count(in selected: Set<ExportYearMonth>) -> Int {
        years.reduce(0) { total, year in
            total + year.months.reduce(0) { count, month in
                count + (selected.contains(month.period) ? month.count : 0)
            }
        }
    }

    static func build(dates: [Date], calendar: Calendar = .current) -> ExportCatalog {
        var counts: [ExportYearMonth: Int] = [:]
        for date in dates {
            guard let period = ExportYearMonth.of(date, calendar: calendar) else { continue }
            counts[period, default: 0] += 1
        }

        let byYear = Dictionary(grouping: counts.keys, by: \.year)
        let years = byYear.keys.sorted(by: >).map { year in
            let months = (byYear[year] ?? []).sorted(by: >).map { period in
                Month(period: period, count: counts[period] ?? 0)
            }
            return Year(year: year, months: months, count: months.reduce(0) { $0 + $1.count })
        }
        return ExportCatalog(years: years, total: counts.values.reduce(0, +))
    }
}

/// CSV the importer already knows how to read. Dates use a fixed numeric
/// format (`yyyy-MM-dd HH:mm:ss Z`) so a later import can recover the same instant.
enum ExportCSV {
    static let dateFormat = "yyyy-MM-dd HH:mm:ss Z"

    static func text(for transactions: [Transaction]) -> String {
        let dates = makeFormatter(dateFormat)
        var csv = "Date,Note,Amount,Category,Type\n"
        let ordered = transactions.sorted { $0.wrappedDate > $1.wrappedDate }
        for transaction in ordered {
            let note = field(transaction.wrappedNote)
            let category = field(transaction.category?.wrappedName ?? "")
            let type = transaction.income ? "Income" : "Expense"
            let amount = String(format: "%.2f", transaction.wrappedAmount)
            csv += "\(dates.string(from: transaction.wrappedDate)),\(note),\(amount),\(category),\(type)\n"
        }
        return csv
    }

    static func writeTemporaryFile(_ csv: String) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// True when `format` parses the whole string and nothing after it.
    /// A shorter pattern such as `yyyy-MM-dd` must not claim a timestamped export.
    static func formatConsumesEntireString(_ format: String, _ dateString: String) -> Bool {
        let length = (dateString as NSString).length
        guard length > 0 else { return false }
        let formatter = makeFormatter(format)
        var range = NSRange(location: 0, length: length)
        var object: AnyObject?
        do {
            try formatter.getObjectValue(&object, for: dateString, range: &range)
        } catch {
            return false
        }
        return object != nil && range.location == 0 && range.length == length
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }

    private static func field(_ value: String) -> String {
        value.filter { $0 != "," && !$0.isNewline }
    }
}

/// Picks the months, years, or all of the history to export, then hands the file to the share sheet.
struct ExportPeriodSheet: View {
    let onShare: (URL) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var catalog = ExportCatalog(years: [], total: 0)
    @State private var selected: Set<ExportYearMonth> = []
    @State private var transactions: [Transaction] = []

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()

                GlassIconButton(
                    systemName: "checkmark",
                    accessibilityLabel: "Export",
                    foreground: Color.LightIcon,
                    tint: Color.DarkBackground,
                    fallback: Color.DarkBackground
                ) {
                    confirm()
                }
                .disabled(!canExport)
                .opacity(canExport ? 1 : 0.3)
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: "Export")
            }

            Text(summary)
                .font(.system(.body, design: .rounded).weight(.medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .padding(.leading, 4)

            if catalog.total == 0 {
                Text("No transactions to export")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(Color.SubtitleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView(showsIndicators: false) {
                    periodList
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .onAppear(perform: load)
    }

    private var periodList: some View {
        VStack(spacing: 0) {
            row(
                title: String(localized: "All time"),
                count: catalog.total,
                mark: selected == catalog.allMonths && !selected.isEmpty ? .on : .off,
                indented: false,
                showsDivider: true
            ) {
                toggleAll()
            }

            ForEach(catalog.years) { year in
                row(
                    title: yearTitle(year.year),
                    count: year.count,
                    mark: mark(for: year),
                    indented: false,
                    showsDivider: true
                ) {
                    toggle(year)
                }

                ForEach(year.months) { month in
                    row(
                        title: monthTitle(month.period),
                        count: month.count,
                        mark: selected.contains(month.period) ? .on : .off,
                        indented: true,
                        showsDivider: month.id != catalog.years.last?.months.last?.id
                    ) {
                        toggle(month.period)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.PrimaryText.opacity(0.06))
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Color.glassTint, interactive: false)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.PrimaryText.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private enum Mark {
        case off, partial, on
    }

    private func row(title: String, count: Int, mark: Mark, indented: Bool, showsDivider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(indented ? .regular : .medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(transactionCount(count))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)

                Image(systemName: mark == .partial ? "minus" : "checkmark")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)
                    .opacity(mark == .off ? 0 : 1)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            .padding(.leading, indented ? 28 : 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title) + Text(", ") + Text(transactionCount(count)))
        .accessibilityAddTraits(mark == .on ? .isSelected : [])
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, indented ? 28 : 16)
            }
        }
    }

    private var canExport: Bool {
        catalog.total > 0 && !selected.isEmpty
    }

    private var summary: String {
        if catalog.total == 0 {
            return String(localized: "No transactions to export")
        }
        let count = catalog.count(in: selected)
        if count == 0 {
            return String(localized: "Nothing selected")
        }
        return transactionCount(count)
    }

    private func transactionCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld transactions", comment: "How many transactions an export period contains"),
            count
        )
    }

    private func mark(for year: ExportCatalog.Year) -> Mark {
        let months = Set(year.months.map(\.period))
        let chosen = months.intersection(selected).count
        if chosen == 0 { return .off }
        if chosen == months.count { return .on }
        return .partial
    }

    private func toggleAll() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeIn(duration: 0.15)) {
            if selected == catalog.allMonths {
                selected = []
            } else {
                selected = catalog.allMonths
            }
        }
    }

    private func toggle(_ year: ExportCatalog.Year) {
        UISelectionFeedbackGenerator().selectionChanged()
        let months = Set(year.months.map(\.period))
        withAnimation(.easeIn(duration: 0.15)) {
            if months.isSubset(of: selected) {
                selected.subtract(months)
            } else {
                selected.formUnion(months)
            }
        }
    }

    private func toggle(_ month: ExportYearMonth) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeIn(duration: 0.15)) {
            if selected.contains(month) {
                selected.remove(month)
            } else {
                selected.insert(month)
            }
        }
    }

    private func yearTitle(_ year: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yyyy")
        return formatter.string(from: date)
    }

    private func monthTitle(_ period: ExportYearMonth) -> String {
        var components = DateComponents()
        components.year = period.year
        components.month = period.month
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    private func load() {
        guard transactions.isEmpty && catalog.total == 0 else { return }
        let fetched = dataController.results(for: dataController.fetchRequestForExport())
        transactions = fetched
        let built = ExportCatalog.build(dates: fetched.map(\.wrappedDate))
        catalog = built
        selected = built.allMonths
    }

    private func confirm() {
        guard canExport else { return }
        let included = transactions.filter { transaction in
            guard let period = ExportYearMonth.of(transaction.wrappedDate, calendar: .current) else { return false }
            return selected.contains(period)
        }
        guard !included.isEmpty, let url = ExportCSV.writeTemporaryFile(ExportCSV.text(for: included)) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onShare(url)
        dismiss()
    }
}
