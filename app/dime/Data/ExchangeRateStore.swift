//
//  ExchangeRateStore.swift
//  dime
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

struct RateDay: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }

        guard parts.count == 3, (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]) else {
            return nil
        }

        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    var string: String {
        func padded(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }

        return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }

    // npm version tags have no zero padding.
    var currencyAPITag: String {
        "\(year).\(month).\(day)"
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func < (lhs: RateDay, rhs: RateDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

enum ExchangeRateSource: String, Codable {
    case currencyAPI
    case frankfurter

    var name: String {
        switch self {
        case .currencyAPI:
            return "fawazahmed0/exchange-api"
        case .frankfurter:
            return "Frankfurter (European Central Bank)"
        }
    }
}

struct DayRates: Codable, Equatable {
    var source: ExchangeRateSource
    /// Units of each currency one US dollar bought that day.
    var unitsPerDollar: [String: Double]
}

struct ExchangeRateCache: Codable, Equatable {
    static let currentVersion = 1

    var version = ExchangeRateCache.currentVersion
    var days: [String: DayRates] = [:]
    /// Days a provider answered for without publishing rates, such as weekends, so they aren't asked again.
    var coveredDays: Set<String> = []
    var latestDay: String?
    var latestFetchedAt: Date?
}

private struct RateLog {
    #if canImport(os)
    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "ExchangeRates")

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
    #else
    func notice(_ message: String) {
        print(message)
    }

    func error(_ message: String) {
        print(message)
    }
    #endif
}

enum ExchangeRateRequest: Equatable {
    case currencyAPILatest
    case currencyAPIDay(RateDay)
    case frankfurterLatest
    case frankfurterDay(RateDay)
    case frankfurterRange(RateDay, RateDay)
}

// Exchange rates are a local cache that can always be rebuilt: they never go into Core Data or CloudKit.
// The file lives in the app group so the widgets and intents can read it; only the app fetches.
final class ExchangeRateStore: ExchangeRateProviding {
    struct RefreshResult: Equatable {
        var requests = 0
        var failedRequests = 0
        var updatedLatest = false
        var addedDays = 0
        var remainingDays = 0
    }

    static let shared = ExchangeRateStore(fileURL: ExchangeRateStore.defaultFileURL)
    static let didChangeNotification = Notification.Name("DimeExchangeRatesDidChange")

    // The first day fawazahmed0/exchange-api has history for; Frankfurter covers earlier days back to 1999.
    static let currencyAPIFirstDay = RateDay(year: 2024, month: 3, day: 2)
    static let frankfurterFirstDay = RateDay(year: 1999, month: 1, day: 4)

    static var defaultFileURL: URL {
        #if canImport(Darwin)
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CurrencyConverter.appGroup)
        #else
        let container: URL? = nil
        #endif
        let base = container ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ExchangeRates", isDirectory: true).appendingPathComponent("rates.json")
    }

    let fileURL: URL
    var calendar: Calendar
    var maximumRequestsPerRefresh = 40
    var delayBetweenRequests: TimeInterval = 0.25

    private let session: URLSession
    private let lock = NSLock()
    private let logger = RateLog()
    private var cache = ExchangeRateCache()
    private var sortedDays: [String] = []
    private var loadedModificationDate: Date?
    private var hasLoaded = false
    private var isRefreshing = false

    init(fileURL: URL, session: URLSession = .shared, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.fileURL = fileURL
        self.session = session
        self.calendar = calendar
    }

    // MARK: - Reading

    var snapshot: ExchangeRateCache {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return cache
    }

    var lastUpdated: Date? {
        snapshot.latestFetchedAt
    }

    var latestSource: ExchangeRateSource? {
        let cache = snapshot
        return cache.latestDay.flatMap { cache.days[$0]?.source }
    }

    /// The exact day, then the nearest earlier day that has the currency, then a later day within a month.
    func unitsPerDollar(of currencyCode: String, on date: Date) -> Double? {
        let code = currencyCode.uppercased()
        let key = RateDay(date: date, calendar: calendar).string

        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()

        if let value = cache.days[key]?.unitsPerDollar[code] {
            return value
        }

        var index = insertionIndex(of: key)

        while index > 0 {
            index -= 1

            if let value = cache.days[sortedDays[index]]?.unitsPerDollar[code] {
                return value
            }
        }

        // A later day's rate stands in only for a recent gap. Years-old amounts in a currency without history
        // would be badly wrong at today's rate, so they're left out instead.
        for later in sortedDays[insertionIndex(of: key)...] {
            guard let distance = daysBetween(key, later), distance <= Self.maximumDaysToLaterRate else {
                break
            }

            if let value = cache.days[later]?.unitsPerDollar[code] {
                return value
            }
        }

        return nil
    }

    static let maximumDaysToLaterRate = 31

    private func daysBetween(_ earlier: String, _ later: String) -> Int? {
        guard let start = RateDay(string: earlier).flatMap({ calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) }),
              let end = RateDay(string: later).flatMap({ calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) })
        else {
            return nil
        }

        return calendar.dateComponents([.day], from: start, to: end).day
    }

    /// Another process (the app, for a widget) may have written the file since it was read.
    func reloadIfChanged() {
        lock.lock()
        defer { lock.unlock() }

        guard hasLoaded else {
            return
        }

        if modificationDate() != loadedModificationDate {
            hasLoaded = false
            loadIfNeeded()
        }
    }

    private func insertionIndex(of key: String) -> Int {
        var low = 0
        var high = sortedDays.count

        while low < high {
            let middle = (low + high) / 2

            if sortedDays[middle] <= key {
                low = middle + 1
            } else {
                high = middle
            }
        }

        return low
    }

    // MARK: - Cache file

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    // Call with the lock held.
    private func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        loadedModificationDate = modificationDate()

        guard let data = try? Data(contentsOf: fileURL) else {
            cache = ExchangeRateCache()
            sortedDays = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode(ExchangeRateCache.self, from: data)

            guard decoded.version == ExchangeRateCache.currentVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }

            cache = decoded
        } catch {
            logger.error("Discarding the unreadable exchange rate cache: \(error)")
            try? FileManager.default.removeItem(at: fileURL)
            loadedModificationDate = nil
            cache = ExchangeRateCache()
        }

        sortedDays = cache.days.keys.sorted()
    }

    // Call with the lock held.
    private func save() {
        sortedDays = cache.days.keys.sorted()

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: fileURL, options: .atomic)
            loadedModificationDate = modificationDate()
        } catch {
            logger.error("Saving exchange rates failed: \(error)")
        }
    }

    func removeAll() {
        lock.lock()
        cache = ExchangeRateCache()
        sortedDays = []
        hasLoaded = true
        try? FileManager.default.removeItem(at: fileURL)
        loadedModificationDate = nil
        lock.unlock()
    }

    // MARK: - Planning

    func needsLatest(now: Date) -> Bool {
        guard let fetchedAt = snapshot.latestFetchedAt else {
            return true
        }

        return !calendar.isDate(fetchedAt, inSameDayAs: now) || fetchedAt > now
    }

    /// Days with foreign transactions that have no rates cached yet. Past days are cached for good; today
    /// and later days are served by the latest rates.
    func missingDays(for dates: [Date], now: Date) -> [RateDay] {
        let cache = snapshot
        let today = RateDay(date: now, calendar: calendar)
        let days = Set(dates.map { RateDay(date: $0, calendar: calendar) })

        return days
            .filter { $0 < today && $0 >= Self.frankfurterFirstDay }
            .filter { cache.days[$0.string] == nil && !cache.coveredDays.contains($0.string) }
            .sorted()
    }

    /// Recent days go to fawazahmed0/exchange-api one at a time; older ones to Frankfurter, a year per request.
    static func requests(for days: [RateDay]) -> [ExchangeRateRequest] {
        let recent = days.filter { $0 >= currencyAPIFirstDay }.sorted()
        let older = days.filter { $0 < currencyAPIFirstDay }.sorted()

        let ranges = Dictionary(grouping: older, by: \.year).keys.sorted().compactMap { year -> ExchangeRateRequest? in
            let inYear = older.filter { $0.year == year }

            guard let first = inYear.first, let last = inYear.last else {
                return nil
            }

            return first == last ? .frankfurterDay(first) : .frankfurterRange(first, last)
        }

        // Newest first, so the days most likely to be looked at are fetched before the request limit.
        return recent.reversed().map { .currencyAPIDay($0) } + ranges.reversed()
    }

    static func urls(for request: ExchangeRateRequest) -> [URL] {
        let strings: [String]

        switch request {
        case .currencyAPILatest:
            strings = [
                "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json",
                "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json"
            ]
        case let .currencyAPIDay(day):
            strings = [
                "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(day.currencyAPITag)/v1/currencies/usd.min.json",
                "https://\(day.string).currency-api.pages.dev/v1/currencies/usd.min.json"
            ]
        case .frankfurterLatest:
            strings = ["https://api.frankfurter.dev/v1/latest?base=USD"]
        case let .frankfurterDay(day):
            strings = ["https://api.frankfurter.dev/v1/\(day.string)?base=USD"]
        case let .frankfurterRange(first, last):
            strings = ["https://api.frankfurter.dev/v1/\(first.string)..\(last.string)?base=USD"]
        }

        return strings.compactMap(URL.init(string:))
    }

    // MARK: - Parsing

    private static func cleaned(_ rates: [String: Any]) -> [String: Double] {
        var cleaned: [String: Double] = [:]

        for (code, value) in rates {
            guard let number = (value as? Double) ?? (value as? Int).map(Double.init), number.isFinite, number > 0 else {
                continue
            }

            cleaned[code.uppercased()] = number
        }

        return cleaned
    }

    /// `{"date": "2025-03-01", "usd": {"eur": 0.96, …}}`
    static func parseCurrencyAPI(_ data: Data) -> (day: RateDay, rates: DayRates)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let day = (object["date"] as? String).flatMap(RateDay.init(string:)),
              let usd = object["usd"] as? [String: Any]
        else {
            return nil
        }

        let rates = cleaned(usd)
        return rates.isEmpty ? nil : (day, DayRates(source: .currencyAPI, unitsPerDollar: rates))
    }

    /// `{"base": "USD", "date": "2020-01-02", "rates": {…}}`, or for a range
    /// `{"base": "USD", "start_date": …, "end_date": …, "rates": {"2020-01-02": {…}, …}}`.
    static func parseFrankfurter(_ data: Data) -> [RateDay: DayRates]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["base"] as? String)?.uppercased() == CurrencyConverter.pivotCurrency,
              let rates = object["rates"] as? [String: Any]
        else {
            return nil
        }

        if let day = (object["date"] as? String).flatMap(RateDay.init(string:)) {
            let cleaned = cleaned(rates)
            return cleaned.isEmpty ? nil : [day: DayRates(source: .frankfurter, unitsPerDollar: cleaned)]
        }

        var days: [RateDay: DayRates] = [:]

        for (key, value) in rates {
            guard let day = RateDay(string: key), let dayRates = value as? [String: Any] else {
                continue
            }

            let cleaned = cleaned(dayRates)

            if !cleaned.isEmpty {
                days[day] = DayRates(source: .frankfurter, unitsPerDollar: cleaned)
            }
        }

        return days.isEmpty ? nil : days
    }

    // MARK: - Fetching

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }

    /// Tries each mirror in turn. Returns the parsed days, or nil when none answered usefully.
    private func fetch(_ request: ExchangeRateRequest) async -> [RateDay: DayRates]? {
        for url in Self.urls(for: request) {
            guard let data = try? await data(from: url) else {
                logger.notice("No exchange rates from \(url.absoluteString)")
                continue
            }

            switch request {
            case .currencyAPILatest, .currencyAPIDay:
                if let parsed = Self.parseCurrencyAPI(data) {
                    return [parsed.day: parsed.rates]
                }
            case .frankfurterLatest, .frankfurterDay, .frankfurterRange:
                if let parsed = Self.parseFrankfurter(data) {
                    return parsed
                }
            }

            logger.error("Unreadable exchange rates from \(url.absoluteString)")
        }

        return nil
    }

    private func store(_ days: [RateDay: DayRates], covering requested: [RateDay], latest: RateDay?, now: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()

        var added = 0

        for (day, rates) in days where cache.days[day.string] == nil || day == latest {
            cache.days[day.string] = rates
            added += 1
        }

        // Recent days may only be missing because they haven't been published yet.
        let settled = calendar.date(byAdding: .day, value: -7, to: now).map { RateDay(date: $0, calendar: calendar) }

        for day in requested where cache.days[day.string] == nil {
            if let settled, day < settled {
                cache.coveredDays.insert(day.string)
            }
        }

        if let latest {
            cache.latestDay = latest.string
            cache.latestFetchedAt = now
        }

        save()
        return added
    }

    /// Fetches the latest rates at most once a day (or when `force` is set) and rates for the days of
    /// `dates` that aren't cached, up to `maximumRequestsPerRefresh` requests. Safe to call often.
    @discardableResult
    func refresh(dates: [Date], force: Bool = false, now: Date = Date()) async -> RefreshResult {
        var waits = 0

        // Skipping is fine for automatic refreshes; one the user asked for waits for the running one.
        while !beginRefreshing() {
            guard force, waits < 120 else {
                return RefreshResult()
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            waits += 1
        }

        defer {
            endRefreshing()
        }

        var result = RefreshResult()

        if force || needsLatest(now: now) {
            result.requests += 1

            var latest = await fetch(.currencyAPILatest)

            if latest == nil {
                latest = await fetch(.frankfurterLatest)
            }

            if let latest, let day = latest.keys.max() {
                result.addedDays += store(latest, covering: [], latest: day, now: now)
                result.updatedLatest = true
            } else {
                result.failedRequests += 1
            }
        }

        let missing = missingDays(for: dates, now: now)
        let requests = Self.requests(for: missing)

        for request in requests.prefix(max(0, maximumRequestsPerRefresh - result.requests)) {
            if result.requests > 0, delayBetweenRequests > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayBetweenRequests * 1_000_000_000))
            }

            result.requests += 1
            let requested = days(in: request, from: missing)
            var fetched = await fetch(request)

            // A recent day exchange-api doesn't have can still come from Frankfurter.
            if fetched == nil, case let .currencyAPIDay(day) = request {
                fetched = await fetch(.frankfurterDay(day))
            }

            guard let fetched else {
                result.failedRequests += 1
                continue
            }

            result.addedDays += store(fetched, covering: requested, latest: nil, now: now)
        }

        result.remainingDays = missingDays(for: dates, now: now).count
        logger.notice("Exchange rate refresh: \(result.requests) requests, \(result.failedRequests) failed, \(result.addedDays) days added, \(result.remainingDays) days still missing")

        if result.addedDays > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }

        return result
    }

    private func beginRefreshing() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isRefreshing else {
            return false
        }

        isRefreshing = true
        return true
    }

    private func endRefreshing() {
        lock.lock()
        isRefreshing = false
        lock.unlock()
    }

    private func days(in request: ExchangeRateRequest, from missing: [RateDay]) -> [RateDay] {
        switch request {
        case .currencyAPILatest, .frankfurterLatest:
            return []
        case let .currencyAPIDay(day), let .frankfurterDay(day):
            return [day]
        case let .frankfurterRange(first, last):
            return missing.filter { $0 >= first && $0 <= last }
        }
    }
}
