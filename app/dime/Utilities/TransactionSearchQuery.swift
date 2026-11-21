import Foundation

/// A log search that understands dates as well as words.
///
/// A recognised date becomes a half-open range `[start, end)` on `Transaction.date`.
/// Words left over stay in `remainder` so "coffee last week" is coffee inside that week.
/// Weeks follow the app's start-of-week. "This month" and "last month" follow the
/// payday start-of-month. A named month ("March", "March 2024") is the calendar month.
struct TransactionSearchQuery {
    struct Range: Equatable {
        var start: Date
        var end: Date
    }

    struct Result: Equatable {
        var range: Range?
        /// Words that were not part of the date. Empty when the query is only a date,
        /// or when nothing in it was a date.
        var remainder: String
    }

    static func parse(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar? = nil,
        monthStartDay: Int? = nil,
        locale: Locale = .current
    ) -> Result {
        Parser(
            now: now,
            calendar: calendar ?? appCalendar(),
            monthStartDay: monthStartDay ?? appMonthStartDay(),
            locale: locale
        ).parse(raw)
    }

    static func appCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        let setting = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
        calendar.firstWeekday = (1 ... 7).contains(setting) ? setting : Calendar.current.firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func appMonthStartDay() -> Int {
        let day = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstDayOfMonth") ?? 1
        return (1 ... 28).contains(day) ? day : 1
    }
}

private struct Parser {
    let now: Date
    let calendar: Calendar
    let monthStartDay: Int
    let locale: Locale

    private let months: [Named]
    private let weekdays: [Named]
    private let monthPattern: String
    private let weekdayPattern: String
    private let phrases: [(String, Phrase)]

    init(now: Date, calendar: Calendar, monthStartDay: Int, locale: Locale) {
        self.now = now
        self.calendar = calendar
        self.monthStartDay = min(max(monthStartDay, 1), 28)
        self.locale = locale

        let months = Self.monthNames(locale: locale)
        let monthKeys = Set(months.map(\.name))
        self.months = months
        self.weekdays = Self.weekdayNames(locale: locale, reserved: monthKeys)
        self.monthPattern = Self.alternation(months.map(\.name))
        self.weekdayPattern = Self.alternation(weekdays.map(\.name))
        self.phrases = Self.phraseList.map { (Self.fold($0.0, locale: locale), $0.1) }
    }

    func parse(_ raw: String) -> TransactionSearchQuery.Result {
        let text = normalize(raw)
        if text.isEmpty {
            return TransactionSearchQuery.Result(range: nil, remainder: "")
        }
        if let joined = joinRange(text) {
            return joined
        }
        return parseOne(text)
    }

    // MARK: - One date

    private func parseOne(_ text: String) -> TransactionSearchQuery.Result {
        let attempts: [() -> Span?] = [
            { self.matchISO(text) },
            { self.matchNumeric(text) },
            { self.matchDayMonthYear(text) },
            { self.matchMonthDayYear(text) },
            { self.matchMonthYear(text) },
            { self.matchYearMonth(text) },
            { self.matchSlashMonthYear(text) },
            { self.matchDayMonth(text) },
            { self.matchMonthDay(text) },
            { self.matchRelative(text) },
            { self.matchYear(text) },
            { self.matchMonthName(text) },
            { self.matchWeekday(text) },
        ]
        for attempt in attempts {
            if let span = attempt() {
                return TransactionSearchQuery.Result(
                    range: span.range,
                    remainder: cleanRemainder(removing(span.extent, from: text))
                )
            }
        }
        return TransactionSearchQuery.Result(range: nil, remainder: "")
    }

    /// "March to May" and "last week - this week" cover every day from the earlier start through the later end.
    private func joinRange(_ text: String) -> TransactionSearchQuery.Result? {
        let separators = [" through ", " until ", " to ", " - ", " – ", " — "]
        guard let separator = separators.compactMap({ separator -> (Range<String.Index>, String)? in
            guard let found = text.range(of: separator) else { return nil }
            return (found, separator)
        }).min(by: { $0.0.lowerBound < $1.0.lowerBound }) else {
            return nil
        }

        let left = String(text[..<separator.0.lowerBound])
        let right = String(text[separator.0.upperBound...])
        guard !left.isEmpty, !right.isEmpty else { return nil }

        let start = parse(left)
        let end = parse(right)
        guard let leftRange = start.range, let rightRange = end.range,
              start.remainder.isEmpty, end.remainder.isEmpty
        else {
            return nil
        }

        return TransactionSearchQuery.Result(
            range: TransactionSearchQuery.Range(
                start: min(leftRange.start, rightRange.start),
                end: max(leftRange.end, rightRange.end)
            ),
            remainder: ""
        )
    }

    // MARK: - Absolute dates

    private func matchISO(_ text: String) -> Span? {
        guard let hit = first(isoPattern, in: text),
              let year = Int(hit.groups[0]),
              let month = Int(hit.groups[1]),
              let day = Int(hit.groups[2]),
              let range = exactDay(year: year, month: month, day: day)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchNumeric(_ text: String) -> Span? {
        guard let hit = first(numericDatePattern, in: text),
              let firstNumber = Int(hit.groups[0]),
              let secondNumber = Int(hit.groups[1]),
              let year = Int(hit.groups[2])
        else {
            return nil
        }
        let expanded = expandYear(year)
        let month = monthFirst ? firstNumber : secondNumber
        let day = monthFirst ? secondNumber : firstNumber
        guard let range = exactDay(year: expanded, month: month, day: day) else { return nil }
        return Span(range: range, extent: hit.extent)
    }

    private func matchDayMonthYear(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + monthGroup + #"\s+(\d{4})\b"#, in: text),
              let day = Int(hit.groups[0]),
              let month = monthNumber(hit.groups[1]),
              let year = Int(hit.groups[2]),
              let range = exactDay(year: year, month: month, day: day)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchMonthDayYear(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(monthGroup + #"\s+(\d{1,2})(?:st|nd|rd|th)?\s+(\d{4})\b"#, in: text),
              let month = monthNumber(hit.groups[0]),
              let day = Int(hit.groups[1]),
              let year = Int(hit.groups[2]),
              let range = exactDay(year: year, month: month, day: day)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchMonthYear(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(#"\b(?:(?:in|during|for|from|of)\s+)?"# + monthGroup + #"\s+(?:of\s+)?(\d{4})\b"#, in: text),
              let month = monthNumber(hit.groups[0]),
              let year = Int(hit.groups[1]),
              let range = monthRange(year: year, month: month)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchYearMonth(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(#"\b(\d{4})\s+"# + monthGroup + #"\b"#, in: text),
              let year = Int(hit.groups[0]),
              let month = monthNumber(hit.groups[1]),
              let range = monthRange(year: year, month: month)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchSlashMonthYear(_ text: String) -> Span? {
        if let hit = first(#"\b(\d{4})[/.](\d{1,2})\b(?![/.]\d)"#, in: text),
           let year = Int(hit.groups[0]),
           let month = Int(hit.groups[1]),
           let range = monthRange(year: year, month: month) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(\d{1,2})[/.](\d{4})\b"#, in: text),
           let month = Int(hit.groups[0]),
           let year = Int(hit.groups[1]),
           let range = monthRange(year: year, month: month) {
            return Span(range: range, extent: hit.extent)
        }
        return nil
    }

    private func matchDayMonth(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + monthGroup + #"\b"#, in: text),
              let day = Int(hit.groups[0]),
              let month = monthNumber(hit.groups[1]),
              let range = mostRecentDay(month: month, day: day)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchMonthDay(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(monthGroup + #"\s+(\d{1,2})(?:st|nd|rd|th)?\b"#, in: text),
              let month = monthNumber(hit.groups[0]),
              let day = Int(hit.groups[1]),
              let range = mostRecentDay(month: month, day: day)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchYear(_ text: String) -> Span? {
        guard let hit = first(#"\b(?:(?:in|during|for|year)\s+)?((?:19|20)\d{2})\b"#, in: text),
              let year = Int(hit.groups[0]),
              !adjacentToDecimal(hit.extent, in: text),
              let range = yearRange(year)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchMonthName(_ text: String) -> Span? {
        guard !monthPattern.isEmpty,
              let hit = first(#"\b(?:(?:in|during|for|from|of)\s+)?(?:(last|past|previous|this|next)\s+)?"# + monthGroup + #"\b"#, in: text),
              let month = monthNumber(hit.groups[1])
        else {
            return nil
        }
        let range: TransactionSearchQuery.Range?
        switch hit.groups[0] {
        case "last", "past", "previous":
            range = previousNamedMonth(month)
        case "next":
            range = nextNamedMonth(month)
        case "this":
            range = monthRange(year: calendar.component(.year, from: now), month: month)
        default:
            range = mostRecentMonth(month)
        }
        guard let range else { return nil }
        return Span(range: range, extent: hit.extent)
    }

    // MARK: - Relative dates

    private func matchRelative(_ text: String) -> Span? {
        if let span = matchCounted(text) { return span }
        return matchPhrase(text)
    }

    private func matchCounted(_ text: String) -> Span? {
        if let hit = first(#"\b(?:last|past|previous)\s+(\d+)\s+days?\b"#, in: text),
           let count = Int(hit.groups[0]),
           let range = trailingDays(count) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(\d+)\s+days?\s+ago\b"#, in: text),
           let count = Int(hit.groups[0]),
           let range = daysAgo(count) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(?:a|an)\s+day\s+ago\b"#, in: text),
           let range = daysAgo(1) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(\d+)\s+weeks?\s+ago\b"#, in: text),
           let count = Int(hit.groups[0]),
           let range = weeksAgo(count) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(?:a|an)\s+week\s+ago\b"#, in: text),
           let range = weeksAgo(1) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(\d+)\s+months?\s+ago\b"#, in: text),
           let count = Int(hit.groups[0]),
           let range = monthsAgo(count) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(?:a|an)\s+month\s+ago\b"#, in: text),
           let range = monthsAgo(1) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(\d+)\s+years?\s+ago\b"#, in: text),
           let count = Int(hit.groups[0]),
           let range = yearsAgo(count) {
            return Span(range: range, extent: hit.extent)
        }
        if let hit = first(#"\b(?:a|an)\s+year\s+ago\b"#, in: text),
           let range = yearsAgo(1) {
            return Span(range: range, extent: hit.extent)
        }
        return nil
    }

    private func matchPhrase(_ text: String) -> Span? {
        let body = phrases
            .sorted { $0.0.count > $1.0.count }
            .map { NSRegularExpression.escapedPattern(for: $0.0) }
            .joined(separator: "|")
        guard !body.isEmpty,
              let hit = first(#"\b(?:(?:the|on|in|for|during)\s+)?("# + body + #")\b"#, in: text),
              let phrase = phrases.first(where: { $0.0 == hit.groups[0] })?.1,
              let range = resolve(phrase)
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func matchWeekday(_ text: String) -> Span? {
        guard !weekdayPattern.isEmpty,
              let hit = first(#"\b(?:(?:on|the)\s+)?(?:(this|last|past|previous|next)\s+)?"# + weekdayGroup + #"\b"#, in: text),
              let weekday = weekdays.first(where: { $0.name == hit.groups[1] })?.value,
              let range = resolveWeekday(weekday, qualifier: hit.groups[0])
        else {
            return nil
        }
        return Span(range: range, extent: hit.extent)
    }

    private func resolve(_ phrase: Phrase) -> TransactionSearchQuery.Range? {
        switch phrase {
        case .today:
            return dayRange(now)
        case .yesterday:
            return daysAgo(1)
        case .tomorrow:
            return shift(dayRange(now), days: 1)
        case .thisWeek:
            return week(containing: now)
        case .lastWeek:
            return shift(week(containing: now), days: -7)
        case .nextWeek:
            return shift(week(containing: now), days: 7)
        case .thisMonth:
            return customMonth(containing: now)
        case .lastMonth:
            return shiftMonth(customMonth(containing: now), by: -1)
        case .nextMonth:
            return shiftMonth(customMonth(containing: now), by: 1)
        case .thisYear:
            return yearRange(calendar.component(.year, from: now))
        case .lastYear:
            return yearRange(calendar.component(.year, from: now) - 1)
        case .nextYear:
            return yearRange(calendar.component(.year, from: now) + 1)
        case .thisWeekend:
            return weekend(in: week(containing: now))
        case .lastWeekend:
            return weekend(in: shift(week(containing: now), days: -7))
        case .nextWeekend:
            return weekend(in: shift(week(containing: now), days: 7))
        }
    }

    /// A bare weekday is that day in the current week, including a day still ahead.
    private func resolveWeekday(_ weekday: Int, qualifier: String) -> TransactionSearchQuery.Range? {
        let thisWeek = week(containing: now)
        switch qualifier {
        case "last", "past", "previous":
            return dayInWeek(weekday, week: shift(thisWeek, days: -7))
        case "next":
            let upcoming = dayInWeek(weekday, week: thisWeek)
            if upcoming.start <= calendar.startOfDay(for: now) {
                return dayInWeek(weekday, week: shift(thisWeek, days: 7))
            }
            return upcoming
        default:
            return dayInWeek(weekday, week: thisWeek)
        }
    }

    // MARK: - Range maths

    private func dayRange(_ date: Date) -> TransactionSearchQuery.Range {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func exactDay(year: Int, month: Int, day: Int) -> TransactionSearchQuery.Range? {
        guard (1970 ... 2100).contains(year), (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return dayRange(date)
    }

    private func monthRange(year: Int, month: Int) -> TransactionSearchQuery.Range? {
        guard (1970 ... 2100).contains(year), (1 ... 12).contains(month) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start)
        else {
            return nil
        }
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func yearRange(_ year: Int) -> TransactionSearchQuery.Range? {
        guard (1970 ... 2100).contains(year) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .year, value: 1, to: start)
        else {
            return nil
        }
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func mostRecentMonth(_ month: Int) -> TransactionSearchQuery.Range? {
        let year = calendar.component(.year, from: now)
        let current = calendar.component(.month, from: now)
        return monthRange(year: month > current ? year - 1 : year, month: month)
    }

    private func previousNamedMonth(_ month: Int) -> TransactionSearchQuery.Range? {
        let year = calendar.component(.year, from: now)
        let current = calendar.component(.month, from: now)
        return monthRange(year: month < current ? year : year - 1, month: month)
    }

    private func nextNamedMonth(_ month: Int) -> TransactionSearchQuery.Range? {
        let year = calendar.component(.year, from: now)
        let current = calendar.component(.month, from: now)
        return monthRange(year: month > current ? year : year + 1, month: month)
    }

    private func mostRecentDay(month: Int, day: Int) -> TransactionSearchQuery.Range? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = exactDay(year: year, month: month, day: day) else { return nil }
        if thisYear.start > calendar.startOfDay(for: now) {
            return exactDay(year: year - 1, month: month, day: day)
        }
        return thisYear
    }

    private func week(containing date: Date) -> TransactionSearchQuery.Range {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func customMonth(containing date: Date) -> TransactionSearchQuery.Range {
        let dayStart = calendar.startOfDay(for: date)
        var components = calendar.dateComponents([.year, .month], from: dayStart)
        components.day = monthStartDay
        let candidate = calendar.date(from: components) ?? dayStart
        let start = dayStart < candidate
            ? (calendar.date(byAdding: .month, value: -1, to: candidate) ?? candidate)
            : candidate
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func dayInWeek(_ weekday: Int, week: TransactionSearchQuery.Range) -> TransactionSearchQuery.Range {
        let startWeekday = calendar.component(.weekday, from: week.start)
        let delta = (weekday - startWeekday + 7) % 7
        let day = calendar.date(byAdding: .day, value: delta, to: week.start) ?? week.start
        return dayRange(day)
    }

    private func weekend(in week: TransactionSearchQuery.Range) -> TransactionSearchQuery.Range {
        let saturday = dayInWeek(7, week: week)
        let end = calendar.date(byAdding: .day, value: 2, to: saturday.start) ?? saturday.end
        return TransactionSearchQuery.Range(start: saturday.start, end: end)
    }

    private func shift(_ range: TransactionSearchQuery.Range, days: Int) -> TransactionSearchQuery.Range {
        TransactionSearchQuery.Range(
            start: calendar.date(byAdding: .day, value: days, to: range.start) ?? range.start,
            end: calendar.date(byAdding: .day, value: days, to: range.end) ?? range.end
        )
    }

    private func shiftMonth(_ range: TransactionSearchQuery.Range, by months: Int) -> TransactionSearchQuery.Range {
        TransactionSearchQuery.Range(
            start: calendar.date(byAdding: .month, value: months, to: range.start) ?? range.start,
            end: calendar.date(byAdding: .month, value: months, to: range.end) ?? range.end
        )
    }

    private func trailingDays(_ count: Int) -> TransactionSearchQuery.Range? {
        guard (1 ... 3660).contains(count) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today)
        else {
            return nil
        }
        return TransactionSearchQuery.Range(start: start, end: end)
    }

    private func daysAgo(_ count: Int) -> TransactionSearchQuery.Range? {
        guard (0 ... 3660).contains(count),
              let day = calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now))
        else {
            return nil
        }
        return dayRange(day)
    }

    private func weeksAgo(_ count: Int) -> TransactionSearchQuery.Range? {
        guard (1 ... 520).contains(count) else { return nil }
        return shift(week(containing: now), days: -7 * count)
    }

    private func monthsAgo(_ count: Int) -> TransactionSearchQuery.Range? {
        guard (1 ... 240).contains(count) else { return nil }
        return shiftMonth(customMonth(containing: now), by: -count)
    }

    private func yearsAgo(_ count: Int) -> TransactionSearchQuery.Range? {
        guard (1 ... 200).contains(count) else { return nil }
        return yearRange(calendar.component(.year, from: now) - count)
    }

    // MARK: - Words

    private var monthGroup: String {
        "(" + monthPattern + ")"
    }

    private var weekdayGroup: String {
        "(" + weekdayPattern + ")"
    }

    private var monthFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let monthIndex = format.firstIndex(of: "M"), let dayIndex = format.firstIndex(of: "d") else {
            return true
        }
        return monthIndex < dayIndex
    }

    private func monthNumber(_ name: String) -> Int? {
        months.first { $0.name == name }?.value
    }

    private func expandYear(_ year: Int) -> Int {
        guard year < 100 else { return year }
        return year >= 70 ? 1900 + year : 2000 + year
    }

    private func adjacentToDecimal(_ extent: NSRange, in text: String) -> Bool {
        let ns = text as NSString
        if extent.location > 0 {
            let previous = ns.substring(with: NSRange(location: extent.location - 1, length: 1))
            if previous == "." { return true }
        }
        let end = extent.location + extent.length
        if end < ns.length {
            let next = ns.substring(with: NSRange(location: end, length: 1))
            if next == "." { return true }
        }
        return false
    }

    private func normalize(_ raw: String) -> String {
        var text = Self.fold(raw, locale: locale)
        text = text.replacingOccurrences(of: ", ", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removing(_ extent: NSRange, from text: String) -> String {
        guard let range = Range(extent, in: text) else { return text }
        var copy = text
        copy.replaceSubrange(range, with: " ")
        copy = copy.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return copy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanRemainder(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        while let first = words.first, fillers.contains(first) {
            words.removeFirst()
        }
        while let last = words.last, fillers.contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private struct Hit {
        var extent: NSRange
        var groups: [String]
    }

    private func first(_ pattern: String, in text: String) -> Hit? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: full) else { return nil }
        var groups: [String] = []
        for index in 1 ..< match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return Hit(extent: match.range, groups: groups)
    }

    private static func alternation(_ names: [String]) -> String {
        let unique = Array(Set(names)).sorted { $0.count > $1.count }
        return unique.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }

    private static func fold(_ text: String, locale: Locale) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "´", with: "'")
    }

    private static func monthNames(locale: Locale) -> [Named] {
        var seen = Set<String>()
        var names: [Named] = []
        func add(_ raw: String, month: Int) {
            let name = fold(raw, locale: locale)
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 3, seen.insert(name).inserted else { return }
            names.append(Named(name: name, value: month))
        }

        let locales = [locale, Locale(identifier: "en_US"), Locale(identifier: "fr_FR"), Locale(identifier: "ru_RU")]
        for item in locales {
            let formatter = DateFormatter()
            formatter.locale = item
            formatter.calendar = Calendar(identifier: .gregorian)
            for month in 1 ... 12 {
                if let name = formatter.monthSymbols?[month - 1] { add(name, month: month) }
                if let name = formatter.shortMonthSymbols?[month - 1] { add(name, month: month) }
                if let name = formatter.standaloneMonthSymbols?[month - 1] { add(name, month: month) }
                if let name = formatter.shortStandaloneMonthSymbols?[month - 1] { add(name, month: month) }
            }
        }
        add("sept", month: 9)
        return names.sorted { $0.name.count > $1.name.count }
    }

    private static func weekdayNames(locale: Locale, reserved: Set<String>) -> [Named] {
        var seen = Set<String>()
        var names: [Named] = []
        func add(_ raw: String, weekday: Int) {
            let name = fold(raw, locale: locale)
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 3, !reserved.contains(name), seen.insert(name).inserted else { return }
            names.append(Named(name: name, value: weekday))
        }

        for (name, weekday) in englishWeekdays {
            add(name, weekday: weekday)
        }
        for item in [locale, Locale(identifier: "en_US"), Locale(identifier: "fr_FR"), Locale(identifier: "ru_RU")] {
            let formatter = DateFormatter()
            formatter.locale = item
            formatter.calendar = Calendar(identifier: .gregorian)
            for weekday in 1 ... 7 {
                if let name = formatter.weekdaySymbols?[weekday - 1] {
                    add(name, weekday: weekday)
                }
            }
        }
        return names.sorted { $0.name.count > $1.name.count }
    }

    private static let englishWeekdays: [(String, Int)] = [
        ("sunday", 1), ("sun", 1),
        ("monday", 2), ("mon", 2),
        ("tuesday", 3), ("tue", 3), ("tues", 3),
        ("wednesday", 4), ("wed", 4),
        ("thursday", 5), ("thu", 5), ("thur", 5), ("thurs", 5),
        ("friday", 6), ("fri", 6),
        ("saturday", 7), ("sat", 7),
    ]

    private static let phraseList: [(String, Phrase)] = [
        ("today", .today), ("yesterday", .yesterday), ("tomorrow", .tomorrow),
        ("aujourd'hui", .today), ("hier", .yesterday), ("demain", .tomorrow),
        ("сегодня", .today), ("вчера", .yesterday), ("завтра", .tomorrow),

        ("this week", .thisWeek), ("current week", .thisWeek),
        ("last week", .lastWeek), ("past week", .lastWeek), ("previous week", .lastWeek),
        ("next week", .nextWeek),
        ("cette semaine", .thisWeek),
        ("la semaine dernière", .lastWeek), ("semaine dernière", .lastWeek),
        ("la semaine prochaine", .nextWeek), ("semaine prochaine", .nextWeek),
        ("на этой неделе", .thisWeek), ("на прошлой неделе", .lastWeek), ("на следующей неделе", .nextWeek),

        ("this month", .thisMonth), ("current month", .thisMonth),
        ("last month", .lastMonth), ("past month", .lastMonth), ("previous month", .lastMonth),
        ("next month", .nextMonth),
        ("ce mois", .thisMonth), ("ce mois-ci", .thisMonth), ("ce mois ci", .thisMonth),
        ("le mois dernier", .lastMonth), ("mois dernier", .lastMonth),
        ("le mois prochain", .nextMonth), ("mois prochain", .nextMonth),
        ("в этом месяце", .thisMonth), ("в прошлом месяце", .lastMonth), ("в следующем месяце", .nextMonth),

        ("this year", .thisYear), ("current year", .thisYear),
        ("last year", .lastYear), ("past year", .lastYear), ("previous year", .lastYear),
        ("next year", .nextYear),
        ("cette année", .thisYear),
        ("l'année dernière", .lastYear), ("année dernière", .lastYear),
        ("l'année prochaine", .nextYear), ("année prochaine", .nextYear),
        ("в этом году", .thisYear), ("в прошлом году", .lastYear), ("в следующем году", .nextYear),

        ("this weekend", .thisWeekend), ("last weekend", .lastWeekend),
        ("past weekend", .lastWeekend), ("previous weekend", .lastWeekend),
        ("next weekend", .nextWeekend),
    ]

    private let fillers: Set<String> = [
        "to", "through", "until", "in", "during", "on", "the", "for", "from", "of", "a", "an", "at", "and",
        "le", "la", "les", "de", "du", "des", "au",
    ]

    private let isoPattern = #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#
    private let numericDatePattern = #"\b(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})\b"#
}

private struct Named {
    var name: String
    var value: Int
}

private struct Span {
    var range: TransactionSearchQuery.Range
    var extent: NSRange
}

private enum Phrase {
    case today, yesterday, tomorrow
    case thisWeek, lastWeek, nextWeek
    case thisMonth, lastMonth, nextMonth
    case thisYear, lastYear, nextYear
    case thisWeekend, lastWeekend, nextWeekend
}
