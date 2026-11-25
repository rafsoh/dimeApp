//
//  CSVImport.swift
//  dime
//

import Foundation

enum CSVExport {
    // Columns added later go last, so the earlier ones stay where older exports had them.
    static let header = "Date,Note,Amount,Category,Type,Currency,Account\n"

    /// A transfer's legs have their own types, so importing an export recreates the transfer rather than
    /// counting it as an expense and an income.
    static let transferOutType = "Transfer Out"
    static let transferInType = "Transfer In"

    /// Two decimals as before, or three for currencies like KWD so no digit is lost.
    static func amount(_ amount: Double, currencyCode: String) -> String {
        String(format: "%.\(max(2, CurrencyDigits.fractionDigits(for: currencyCode)))f", amount)
    }
}

struct CSVTable {
    let headers: [String]
    let hasHeaderRow: Bool
    /// Every row is padded to `headers.count`.
    let rows: [[String]]

    var columnCount: Int { headers.count }

    func column(_ index: Int) -> [String] {
        rows.map { $0[index] }
    }

    /// Reads comma, semicolon or tab separated text, with quoted fields that may hold separators, quotes and line breaks.
    static func parse(_ text: String) -> CSVTable? {
        var text = text
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        let delimiter = detectDelimiter(text)
        var records = parseRecords(text, delimiter: delimiter)
            .map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { record in record.contains { !$0.isEmpty } }

        guard let first = records.first else { return nil }

        let width = records.map(\.count).max() ?? 0
        guard width >= 2 else { return nil }

        // A header row names its columns; data rows hold at least one amount or date.
        let hasHeaderRow = records.count > 1 && !first.contains { ImportParsing.amount($0) != nil || ImportParsing.looksLikeDate($0) }

        var headers: [String] = []
        if hasHeaderRow {
            headers = records.removeFirst()
        }

        guard !records.isEmpty else { return nil }

        headers = (0 ..< width).map { index in
            let name = index < headers.count ? headers[index] : ""
            return name.isEmpty ? String(format: NSLocalizedString("Column %lld", comment: "an unnamed column in an imported file"), index + 1) : name
        }

        let rows = records.map { record in
            record.count < width ? record + Array(repeating: "", count: width - record.count) : record
        }

        return CSVTable(headers: headers, hasHeaderRow: hasHeaderRow, rows: rows)
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false

        for character in firstLine {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes, counts[character] != nil {
                counts[character, default: 0] += 1
            }
        }

        let best = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key != ",") }
        return (best?.value ?? 0) > 0 ? best!.key : ","
    }

    private static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var characters = text.makeIterator()
        var pending: Character? = characters.next()

        while let character = pending {
            pending = characters.next()

            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"" where field.trimmingCharacters(in: .whitespaces).isEmpty:
                field = ""
                inQuotes = true
            case delimiter:
                record.append(field)
                field = ""
            // "\r\n" is a single Character in Swift.
            case "\n", "\r\n", "\r":
                record.append(field)
                records.append(record)
                record = []
                field = ""
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }

        return records
    }
}

enum ImportField: CaseIterable, Hashable {
    case date, amount, category, note, type, currency, account

    var title: String {
        switch self {
        case .date: return "Date"
        case .amount: return "Amount"
        case .category: return "Category"
        case .note: return "Note"
        case .type: return "Type"
        case .currency: return "Currency"
        case .account: return "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .amount: return "dollarsign.circle.fill"
        case .category: return "square.grid.2x2.fill"
        case .note: return "doc.plaintext.fill"
        case .type: return "plusminus"
        case .currency: return "coloncurrencysign.circle.fill"
        case .account: return "creditcard.fill"
        }
    }

    var isRequired: Bool {
        switch self {
        case .date, .amount: return true
        case .category, .note, .type, .currency, .account: return false
        }
    }

    var headerKeywords: [String] {
        switch self {
        case .date: return ["date", "time", "day", "when", "posted"]
        case .amount: return ["amount", "value", "price", "cost", "sum", "total", "spent"]
        case .category: return ["category", "categories", "tag", "group"]
        case .note: return ["note", "description", "memo", "title", "name", "payee", "merchant", "details", "subtitle"]
        case .type: return ["type", "kind", "direction", "income/expense", "flow"]
        case .currency: return ["currency", "ccy", "currency code", "iso currency"]
        case .account: return ["account", "wallet", "account name"]
        }
    }
}

enum ImportParsing {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "yyyy.MM.dd", "yyyyMMdd",
        "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd.MM.yyyy",
        "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy h:mm a", "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "MM/dd/yy", "MM-dd-yyyy",
        "d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "MMMM d, yyyy", "dd-MMM-yyyy", "d-MMM-yy"
    ]

    private static var formatters: [String: DateFormatter] = [:]

    static func formatter(for format: String) -> DateFormatter {
        // The built-in patterns are English, so they stay on a POSIX calendar.
        // A format typed by hand that names a month or weekday follows the device locale.
        let named = !dateFormats.contains(format) && (format.contains("MMM") || format.contains("E"))
        let key = (named ? "local:" : "posix:") + format
        if let formatter = formatters[key] {
            return formatter
        }
        let formatter = DateFormatter()
        if named {
            formatter.locale = .current
        } else {
            formatter.locale = posix
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.isLenient = false
        }
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }

    static func date(_ raw: String, format: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, separatorsMatch(value, format: format) else { return nil }
        return formatter(for: format).date(from: value)
    }

    /// DateFormatter accepts any separator in place of the format's, so "03.01.2024" would read as "dd/MM/yyyy".
    private static func separatorsMatch(_ value: String, format: String) -> Bool {
        let isSeparator: (Character) -> Bool = { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "'" }
        var valueSeparators = value.filter(isSeparator)
        let formatSeparators = format.filter(isSeparator)

        // The time zone's sign and colon, as in "+0000" or "-05:00", aren't separators in the format.
        if format.hasSuffix("Z"), let sign = valueSeparators.lastIndex(where: { $0 == "+" || $0 == "-" }), valueSeparators.count > formatSeparators.count {
            valueSeparators = String(valueSeparators[..<sign])
        }
        return valueSeparators == formatSeparators
    }

    static func looksLikeDate(_ raw: String) -> Bool {
        dateFormats.contains { date(raw, format: $0) != nil }
    }

    /// The formats that read at least `threshold` of the non-empty samples, those reading the most first. Day-first and
    /// month-first formats that read as many are ordered by the device's region.
    static func dateFormats(fitting samples: [String], threshold: Double = 0.8) -> [String] {
        let values = samples.filter { !$0.isEmpty }
        guard !values.isEmpty else { return [] }

        let localTemplate = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: .current) ?? ""
        let regionIsDayFirst = (localTemplate.firstIndex(of: "d") ?? localTemplate.endIndex) < (localTemplate.firstIndex(of: "M") ?? localTemplate.endIndex)

        let fitting = dateFormats.enumerated().compactMap { offset, format -> (format: String, count: Int, offset: Int)? in
            let count = values.filter { date($0, format: format) != nil }.count
            return Double(count) >= Double(values.count) * threshold ? (format, count, offset) : nil
        }

        let ranked = fitting.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let lhsRank = regionRank(lhs.format, dayFirst: regionIsDayFirst)
            let rhsRank = regionRank(rhs.format, dayFirst: regionIsDayFirst)
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.format)

        // "dd/MM/yy" also reads "21/11/2026", so only keep formats that read the samples differently.
        var seenReadings: Set<[Date?]> = []
        return ranked.filter { format in
            seenReadings.insert(values.map { date($0, format: format) }).inserted
        }
    }

    private static func regionRank(_ format: String, dayFirst: Bool) -> Int {
        let isDayFirst = format.hasPrefix("d")
        let isMonthFirst = format.hasPrefix("M")
        guard isDayFirst || isMonthFirst else { return 0 }
        return isDayFirst == dayFirst ? 0 : 1
    }

    /// Reads amounts like "1,234.50", "1.234,50", "-$12", "(12.00)", "12.00-", "€ 9" and "1'000".
    static func amount(_ raw: String) -> Double? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        var negative = false
        if value.hasPrefix("("), value.hasSuffix(")") {
            negative = true
            value = String(value.dropFirst().dropLast())
        }

        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        guard var first = value.firstIndex(where: isDigit), let last = value.lastIndex(where: isDigit) else { return nil }

        // Keeps the separator in amounts like ".50".
        if first > value.startIndex, [",", "."].contains(value[value.index(before: first)]) {
            first = value.index(before: first)
        }

        // Signs, currency symbols and codes may only sit around the number.
        let affixes = value[..<first] + value[value.index(after: last)...]
        guard affixes.filter(\.isLetter).count <= 3 else { return nil }
        for character in affixes {
            if character == "-" || character == "−" {
                negative = true
            } else if !(character.isLetter || character.isCurrencySymbol || character.isWhitespace || character == "+") {
                return nil
            }
        }

        var digits = ""
        for character in value[first ... last] {
            if isDigit(character) || character == "," || character == "." {
                digits.append(character)
            } else if !(character == "'" || character.isWhitespace) {
                return nil
            }
        }

        let lastComma = digits.lastIndex(of: ",")
        let lastDot = digits.lastIndex(of: ".")
        let decimalSeparator: Character?

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            decimalSeparator = comma > dot ? "," : "."
        case let (comma?, nil):
            let commas = digits.filter { $0 == "," }.count
            let fraction = digits.distance(from: comma, to: digits.endIndex) - 1
            decimalSeparator = commas == 1 && fraction <= 2 ? "," : nil
        case (nil, _?):
            decimalSeparator = digits.filter { $0 == "." }.count == 1 ? "." : nil
        case (nil, nil):
            decimalSeparator = nil
        }

        var normalised = ""
        for character in digits {
            if character == decimalSeparator {
                normalised.append(".")
            } else if character.isNumber {
                normalised.append(character)
            }
        }

        guard let number = Double(normalised) else { return nil }
        return negative ? -number : number
    }

    private static let incomeWords: Set<String> = ["income", "credit", "cr", "in", "deposit", "revenue", "earning", "earnings", "+", "transfer in"]
    private static let expenseWords: Set<String> = ["expense", "expenses", "debit", "dr", "out", "withdrawal", "payment", "spending", "-", "transfer out"]

    /// True for the two legs of a transfer, as Dime exports them.
    static func isTransfer(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return value == CSVExport.transferOutType.lowercased() || value == CSVExport.transferInType.lowercased()
    }

    /// True for income, false for an expense, nil when the value says neither.
    static func isIncome(_ raw: String) -> Bool? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if incomeWords.contains(value) {
            return true
        } else if expenseWords.contains(value) {
            return false
        }
        return nil
    }
}

struct ColumnMapping: Equatable {
    var columns: [ImportField: Int] = [:]

    subscript(field: ImportField) -> Int? {
        get { columns[field] }
        set {
            if let newValue {
                // A column can only fill one field.
                for (other, column) in columns where column == newValue && other != field {
                    columns[other] = nil
                }
            }
            columns[field] = newValue
        }
    }

    var isComplete: Bool {
        ImportField.allCases.filter(\.isRequired).allSatisfy { columns[$0] != nil }
    }

    /// Matches columns by their header names first, then by what they hold.
    static func detect(in table: CSVTable) -> ColumnMapping {
        var mapping = ColumnMapping()
        var free = Set(0 ..< table.columnCount)

        // Only a column of known currency codes counts, whatever its header says, so one isn't taken for a category.
        let currencyColumns = free.sorted().filter { column in
            let values = table.rows.prefix(50).map { $0[column] }.filter { !$0.isEmpty }
            return !values.isEmpty && values.allSatisfy { Currency.knownCode($0) != nil }
        }
        let currencyHeader = { (column: Int) in
            ImportField.currency.headerKeywords.contains { table.headers[column].lowercased().contains($0) }
        }
        if let column = currencyColumns.first(where: { table.hasHeaderRow && currencyHeader($0) }) ?? (table.hasHeaderRow ? nil : currencyColumns.first) {
            mapping.columns[.currency] = column
            free.remove(column)
        }

        if table.hasHeaderRow {
            for field in [ImportField.type, .category, .account, .amount, .date, .note] {
                let candidates = free.sorted()
                let header = { (column: Int) in table.headers[column].lowercased().trimmingCharacters(in: .whitespaces) }
                let match = candidates.first { field.headerKeywords.contains(header($0)) }
                    ?? candidates.first { column in field.headerKeywords.contains { header(column).contains($0) } }
                if let match {
                    mapping.columns[field] = match
                    free.remove(match)
                }
            }
        }

        let samples = table.rows.prefix(50)
        func values(_ column: Int) -> [String] {
            samples.map { $0[column] }.filter { !$0.isEmpty }
        }
        // A few unreadable rows shouldn't hide a column; they're skipped at import instead.
        func mostly(_ column: Int, _ predicate: (String) -> Bool) -> Bool {
            let values = values(column)
            return !values.isEmpty && Double(values.filter(predicate).count) >= Double(values.count) * 0.8
        }

        if mapping[.date] == nil, let column = free.sorted().first(where: { !ImportParsing.dateFormats(fitting: values($0)).isEmpty }) {
            mapping.columns[.date] = column
            free.remove(column)
        }

        if mapping[.amount] == nil {
            let numeric = free.sorted().filter { column in
                mostly(column) { ImportParsing.amount($0) != nil }
            }
            // Prefer a column with decimals over one that's only whole numbers, like an ID.
            if let column = numeric.first(where: { column in values(column).contains { $0.contains(".") || $0.contains(",") } }) ?? numeric.first {
                mapping.columns[.amount] = column
                free.remove(column)
            }
        }

        if mapping[.type] == nil, let column = free.sorted().first(where: { column in
            mostly(column) { ImportParsing.isIncome($0) != nil }
        }) {
            mapping.columns[.type] = column
            free.remove(column)
        }

        let textColumns = free.sorted().filter { column in
            values(column).contains { ImportParsing.amount($0) == nil }
        }
        let uniqueCounts = Dictionary(uniqueKeysWithValues: textColumns.map { ($0, Set(table.column($0)).count) })

        if mapping[.category] == nil, let column = textColumns.min(by: { uniqueCounts[$0]! < uniqueCounts[$1]! }) {
            mapping.columns[.category] = column
            free.remove(column)
        }

        if mapping[.note] == nil, let column = textColumns.filter({ free.contains($0) }).max(by: { uniqueCounts[$0]! < uniqueCounts[$1]! }) {
            mapping.columns[.note] = column
        }

        return mapping
    }
}

enum ImportSkipReason: CaseIterable, Hashable {
    case date, amount, currency

    var description: String {
        switch self {
        case .date: return "without a readable date"
        case .amount: return "without a readable amount"
        case .currency: return "with an unknown currency"
        }
    }
}

struct ImportedRow {
    let date: Date
    /// Always positive; whether it's income comes from `income` or the category.
    let amount: Double
    let note: String
    /// Empty when the row has no category.
    let categoryName: String
    /// Set when the file says whether the row is income, through a type column or signed amounts.
    let income: Bool?
    /// From the file's currency column; nil means the main currency.
    var currencyCode: String?
    /// From the file's account column; empty means Main.
    var accountName = ""
    /// A leg of a transfer Dime exported. Legs with a matching other leg are imported as a transfer.
    var isTransferLeg = false

    func money(income: Bool) -> MoneyEntry {
        MoneyEntry(id: nil, amount: amount, currencyCode: currencyCode, date: date, income: income)
    }

    /// The transfers in an import, as indices of their outgoing and incoming legs. Each outgoing leg pairs with
    /// the first unpaired incoming leg of the same date, amount and currency.
    static func transferPairs(in rows: [ImportedRow]) -> [(outgoing: Int, incoming: Int)] {
        let legs = rows.indices.filter { rows[$0].isTransferLeg }
        var paired = Set<Int>()
        var pairs: [(outgoing: Int, incoming: Int)] = []

        for outIndex in legs where rows[outIndex].income == false {
            let out = rows[outIndex]
            guard let inIndex = legs.first(where: { index in
                !paired.contains(index) && rows[index].income == true && rows[index].date == out.date
                    && rows[index].amount == out.amount && rows[index].currencyCode == out.currencyCode
            }) else { continue }

            paired.insert(inIndex)
            pairs.append((outIndex, inIndex))
        }

        return pairs
    }
}

/// One category name from the file, split by income where the file says so.
struct ImportCategoryKey: Hashable {
    let name: String
    let income: Bool?
}

struct ImportParseResult {
    let rows: [ImportedRow]
    let skipped: [ImportSkipReason: Int]

    var skippedCount: Int { skipped.values.reduce(0, +) }

    static func build(table: CSVTable, mapping: ColumnMapping, dateFormat: String) -> ImportParseResult {
        guard let dateColumn = mapping[.date], let amountColumn = mapping[.amount] else {
            return ImportParseResult(rows: [], skipped: [:])
        }

        let amounts = table.rows.map { ImportParsing.amount($0[amountColumn]) }
        // When a file has both signs, negative amounts are expenses and positive ones are income.
        let signsSayIncome = amounts.contains { ($0 ?? 0) < 0 } && amounts.contains { ($0 ?? 0) > 0 }

        var rows: [ImportedRow] = []
        var skipped: [ImportSkipReason: Int] = [:]

        for (index, row) in table.rows.enumerated() {
            guard let date = ImportParsing.date(row[dateColumn], format: dateFormat) else {
                skipped[.date, default: 0] += 1
                continue
            }
            guard let amount = amounts[index] else {
                skipped[.amount, default: 0] += 1
                continue
            }
            // Rows without a category are imported without one.
            let categoryName = mapping[.category].map { row[$0].trimmingCharacters(in: .whitespaces) } ?? ""

            // An unrecognised code is skipped rather than read as the main currency.
            var currencyCode: String?
            if let currencyColumn = mapping[.currency], !row[currencyColumn].trimmingCharacters(in: .whitespaces).isEmpty {
                guard let code = Currency.knownCode(row[currencyColumn]) else {
                    skipped[.currency, default: 0] += 1
                    continue
                }
                currencyCode = code
            }

            var income = mapping[.type].flatMap { ImportParsing.isIncome(row[$0]) }
            if income == nil, signsSayIncome, amount != 0 {
                income = amount > 0
            }

            rows.append(ImportedRow(
                date: date,
                amount: abs(amount),
                note: mapping[.note].map { row[$0] } ?? "",
                categoryName: categoryName,
                income: income,
                currencyCode: currencyCode,
                accountName: mapping[.account].map { row[$0].trimmingCharacters(in: .whitespaces) } ?? "",
                isTransferLeg: mapping[.type].map { ImportParsing.isTransfer(row[$0]) } ?? false
            ))
        }

        return ImportParseResult(rows: rows, skipped: skipped)
    }

    /// The file's categories, most used first.
    var categoryKeys: [(key: ImportCategoryKey, count: Int)] {
        var counts: [ImportCategoryKey: Int] = [:]
        var order: [ImportCategoryKey] = []
        for row in rows {
            let key = ImportCategoryKey(name: row.categoryName, income: row.income)
            if counts[key] == nil {
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { ($0, counts[$0]!) }.enumerated().sorted { lhs, rhs in
            lhs.element.1 == rhs.element.1 ? lhs.offset < rhs.offset : lhs.element.1 > rhs.element.1
        }.map(\.element)
    }
}

enum ImportCategoryDefaults {
    private static let emojis: [(keywords: [String], emoji: String)] = [
        (["grocer", "supermarket"], "🛒"),
        (["food", "dining", "restaurant", "meal", "lunch", "dinner"], "🍜"),
        (["coffee", "cafe"], "☕️"),
        (["transport", "taxi", "uber", "grab", "bus", "train", "fuel", "gas", "petrol", "car", "parking"], "🚕"),
        (["travel", "flight", "hotel", "holiday", "vacation"], "✈️"),
        (["shop", "clothes", "clothing"], "🛍️"),
        (["rent", "housing", "mortgage", "home"], "🏠"),
        (["bill", "utilit", "electric", "water", "internet", "phone"], "🧾"),
        (["subscription", "streaming"], "📺"),
        (["fitness", "gym", "sport"], "🏋️"),
        (["health", "medical", "doctor", "pharmacy"], "🩺"),
        (["entertain", "movie", "game", "fun"], "🎮"),
        (["education", "school", "book", "course"], "📚"),
        (["gift", "donation", "charity"], "🎁"),
        (["pet"], "🐾"),
        (["salary", "pay", "wage"], "💼"),
        (["invest", "dividend", "interest"], "📈")
    ]

    static func emoji(for name: String, income: Bool) -> String {
        let lowercased = name.lowercased()
        return emojis.first { entry in entry.keywords.contains { lowercased.contains($0) } }?.emoji ?? (income ? "💰" : "💸")
    }
}
