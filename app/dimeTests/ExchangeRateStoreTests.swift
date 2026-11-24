//
//  ExchangeRateStoreTests.swift
//  dimeTests
//

@testable import dime
import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StubURLProtocol: URLProtocol {
    static var responses: [String: (Int, Data)] = [:]
    static var requested: [String] = []

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.requested.append(url)
        let (status, data) = Self.responses[url] ?? (404, Data())

        if let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ExchangeRateStoreTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var fileURL: URL {
        directory.appendingPathComponent("ExchangeRates/rates.json")
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        StubURLProtocol.responses = [:]
        StubURLProtocol.requested = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> ExchangeRateStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let store = ExchangeRateStore(fileURL: fileURL, session: URLSession(configuration: configuration), calendar: calendar)
        store.delayBetweenRequests = 0
        return store
    }

    private func date(_ string: String, hour: Int = 12) -> Date {
        let day = RateDay(string: string)!
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour))!
    }

    private func currencyAPI(_ day: String, _ rates: [String: Double]) -> Data {
        let body = rates.map { "\"\($0.key.lowercased())\": \($0.value)" }.joined(separator: ", ")
        return Data("{\"date\": \"\(day)\", \"usd\": {\(body)}}".utf8)
    }

    private func stub(_ request: ExchangeRateRequest, _ data: Data, mirror: Int = 0) {
        StubURLProtocol.responses[ExchangeRateStore.urls(for: request)[mirror].absoluteString] = (200, data)
    }

    // MARK: - Days and URLs

    func testDaysFormatForEachProvider() {
        let day = RateDay(year: 2025, month: 3, day: 1)

        XCTAssertEqual(day.string, "2025-03-01")
        XCTAssertEqual(day.currencyAPITag, "2025.3.1")
        XCTAssertEqual(RateDay(string: "2025-03-01"), day)
        XCTAssertNil(RateDay(string: "2025-13-01"))
        XCTAssertNil(RateDay(string: "garbage"))
        XCTAssertTrue(RateDay(year: 2024, month: 12, day: 31) < day)
    }

    func testRequestURLs() {
        let day = RateDay(year: 2025, month: 3, day: 1)

        XCTAssertEqual(ExchangeRateStore.urls(for: .currencyAPIDay(day)).map(\.absoluteString), [
            "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@2025.3.1/v1/currencies/usd.min.json",
            "https://2025-03-01.currency-api.pages.dev/v1/currencies/usd.min.json"
        ])
        XCTAssertEqual(ExchangeRateStore.urls(for: .currencyAPILatest).first?.absoluteString, "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")
        XCTAssertEqual(ExchangeRateStore.urls(for: .frankfurterDay(RateDay(year: 2020, month: 1, day: 2))).first?.absoluteString, "https://api.frankfurter.dev/v1/2020-01-02?base=USD")
        XCTAssertEqual(ExchangeRateStore.urls(for: .frankfurterRange(RateDay(year: 2020, month: 1, day: 1), RateDay(year: 2020, month: 12, day: 31))).first?.absoluteString, "https://api.frankfurter.dev/v1/2020-01-01..2020-12-31?base=USD")
        XCTAssertEqual(ExchangeRateStore.urls(for: .frankfurterLatest).first?.absoluteString, "https://api.frankfurter.dev/v1/latest?base=USD")
    }

    func testRecentDaysUseExchangeAPIAndOlderDaysAreBatchedByYear() {
        let days = ["2019-05-04", "2019-11-30", "2021-02-03", "2024-03-01", "2024-03-02", "2025-06-07"].compactMap(RateDay.init(string:))

        XCTAssertEqual(ExchangeRateStore.requests(for: days), [
            .currencyAPIDay(RateDay(year: 2025, month: 6, day: 7)),
            .currencyAPIDay(RateDay(year: 2024, month: 3, day: 2)),
            .frankfurterDay(RateDay(year: 2024, month: 3, day: 1)),
            .frankfurterDay(RateDay(year: 2021, month: 2, day: 3)),
            .frankfurterRange(RateDay(year: 2019, month: 5, day: 4), RateDay(year: 2019, month: 11, day: 30))
        ])
    }

    // MARK: - Parsing

    func testParsesBothProviders() throws {
        let exchange = try XCTUnwrap(ExchangeRateStore.parseCurrencyAPI(Data(#"{"date": "2025-03-01", "usd": {"eur": 0.96, "jpy": 150, "bad": 0, "neg": -1, "str": "x"}}"#.utf8)))
        XCTAssertEqual(exchange.day, RateDay(year: 2025, month: 3, day: 1))
        XCTAssertEqual(exchange.rates.unitsPerDollar, ["EUR": 0.96, "JPY": 150])
        XCTAssertEqual(exchange.rates.source, .currencyAPI)

        let single = try XCTUnwrap(ExchangeRateStore.parseFrankfurter(Data(#"{"amount": 1.0, "base": "USD", "date": "2020-01-02", "rates": {"EUR": 0.89, "GBP": 0.76}}"#.utf8)))
        XCTAssertEqual(single, [RateDay(year: 2020, month: 1, day: 2): DayRates(source: .frankfurter, unitsPerDollar: ["EUR": 0.89, "GBP": 0.76])])

        let range = try XCTUnwrap(ExchangeRateStore.parseFrankfurter(Data(#"{"amount": 1.0, "base": "USD", "start_date": "2020-01-02", "end_date": "2020-01-03", "rates": {"2020-01-02": {"EUR": 0.89}, "2020-01-03": {"EUR": 0.9}}}"#.utf8)))
        XCTAssertEqual(range.count, 2)
        XCTAssertEqual(range[RateDay(year: 2020, month: 1, day: 3)]?.unitsPerDollar["EUR"], 0.9)

        XCTAssertNil(ExchangeRateStore.parseFrankfurter(Data(#"{"base": "EUR", "date": "2020-01-02", "rates": {"USD": 1.1}}"#.utf8)))
        XCTAssertNil(ExchangeRateStore.parseCurrencyAPI(Data("<html>".utf8)))
        XCTAssertNil(ExchangeRateStore.parseCurrencyAPI(Data(#"{"date": "2025-03-01", "usd": {}}"#.utf8)))
    }

    // MARK: - Refreshing and looking up

    func testRefreshFetchesLatestAndMissingDaysOnce() async throws {
        let store = makeStore()
        let now = date("2025-06-10")
        stub(.currencyAPILatest, currencyAPI("2025-06-09", ["EUR": 0.9, "JPY": 140]))
        stub(.currencyAPIDay(RateDay(year: 2025, month: 3, day: 1)), currencyAPI("2025-03-01", ["EUR": 0.95]))
        StubURLProtocol.responses["https://api.frankfurter.dev/v1/2020-01-02..2020-01-06?base=USD"] = (200, Data(#"{"base": "USD", "start_date": "2020-01-02", "end_date": "2020-01-06", "rates": {"2020-01-02": {"EUR": 0.89}, "2020-01-03": {"EUR": 0.893}, "2020-01-06": {"EUR": 0.894}}}"#.utf8))

        let dates = [date("2025-03-01"), date("2025-03-01", hour: 20), date("2020-01-02"), date("2020-01-04"), date("2020-01-06"), now]
        let result = await store.refresh(dates: dates, now: now)

        XCTAssertTrue(result.updatedLatest)
        XCTAssertEqual(result.requests, 3)
        XCTAssertEqual(result.failedRequests, 0)
        XCTAssertEqual(result.remainingDays, 0)
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2025-03-01")), 0.95)
        XCTAssertEqual(store.unitsPerDollar(of: "eur", on: date("2020-01-03")), 0.893)
        // A Saturday uses Friday's rate.
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2020-01-04")), 0.893)
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: now), 0.9)
        XCTAssertEqual(store.latestSource, .currencyAPI)
        XCTAssertEqual(store.lastUpdated, now)

        StubURLProtocol.requested = []
        let again = await store.refresh(dates: dates, now: now.addingTimeInterval(3_600))
        XCTAssertEqual(again.requests, 0)
        XCTAssertTrue(StubURLProtocol.requested.isEmpty)

        // Today's transaction becomes a past day tomorrow and is fetched then, so it's left out here.
        let tomorrow = await store.refresh(dates: Array(dates.dropLast()), now: now.addingTimeInterval(86_400))
        XCTAssertEqual(tomorrow.requests, 1)
        XCTAssertEqual(StubURLProtocol.requested, [ExchangeRateStore.urls(for: .currencyAPILatest)[0].absoluteString])
    }

    func testLookupFallsBackToEarlierDaysThenARecentLaterDayAndNeverGuesses() async {
        let store = makeStore()
        let now = date("2025-06-10")
        stub(.currencyAPILatest, currencyAPI("2025-06-09", ["EUR": 0.9, "THB": 33]))
        stub(.currencyAPIDay(RateDay(year: 2025, month: 1, day: 1)), currencyAPI("2025-01-01", ["EUR": 0.97]))
        await store.refresh(dates: [date("2025-01-01")], now: now)

        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2025-02-15")), 0.97)
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2024-12-15")), 0.97)
        XCTAssertNil(store.unitsPerDollar(of: "EUR", on: date("2024-06-01")))
        XCTAssertEqual(store.unitsPerDollar(of: "THB", on: date("2025-05-20")), 33)
        XCTAssertNil(store.unitsPerDollar(of: "THB", on: date("2025-02-15")))
        XCTAssertNil(store.unitsPerDollar(of: "XYZ", on: date("2025-02-15")))

        let converter = CurrencyConverter(mainCurrency: "EUR", rates: store)
        XCTAssertNil(converter.convert(10, from: "XYZ", on: now))
        XCTAssertEqual(converter.convert(10, from: "USD", on: date("2025-01-01")) ?? 0, 9.7, accuracy: 1e-9)
    }

    func testMirrorAndFrankfurterFallbacks() async {
        let store = makeStore()
        let now = date("2025-06-10")
        stub(.frankfurterLatest, Data(#"{"base": "USD", "date": "2025-06-09", "rates": {"EUR": 0.91}}"#.utf8))
        stub(.currencyAPIDay(RateDay(year: 2025, month: 3, day: 1)), currencyAPI("2025-03-01", ["EUR": 0.95]), mirror: 1)
        stub(.frankfurterDay(RateDay(year: 2025, month: 3, day: 2)), Data(#"{"base": "USD", "date": "2025-02-28", "rates": {"EUR": 0.96}}"#.utf8))

        let result = await store.refresh(dates: [date("2025-03-01"), date("2025-03-02")], now: now)

        XCTAssertTrue(result.updatedLatest)
        XCTAssertEqual(result.failedRequests, 0)
        XCTAssertEqual(store.latestSource, .frankfurter)
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2025-03-01")), 0.95)
        XCTAssertEqual(store.unitsPerDollar(of: "EUR", on: date("2025-02-28")), 0.96)
    }

    func testFailuresAreRetriedLaterAndCountedNotGuessed() async {
        let store = makeStore()
        let now = date("2025-06-10")

        let result = await store.refresh(dates: [date("2025-03-01")], now: now)

        XCTAssertFalse(result.updatedLatest)
        XCTAssertEqual(result.failedRequests, 2)
        XCTAssertEqual(result.remainingDays, 1)
        XCTAssertNil(store.unitsPerDollar(of: "EUR", on: date("2025-03-01")))
        XCTAssertTrue(store.needsLatest(now: now))
        XCTAssertEqual(store.missingDays(for: [date("2025-03-01")], now: now), [RateDay(year: 2025, month: 3, day: 1)])
    }

    func testRequestsPerRefreshAreLimited() async {
        let store = makeStore()
        store.maximumRequestsPerRefresh = 3
        let now = date("2025-06-10")
        let dates = (1 ... 10).map { date("2025-04-\($0 < 10 ? "0" : "")\($0)") }

        let result = await store.refresh(dates: dates, now: now)

        XCTAssertEqual(result.requests, 3)
        XCTAssertEqual(StubURLProtocol.requested.count, 3 + 2 * 3)
        XCTAssertEqual(result.remainingDays, 10)
    }

    func testOnlyPastDaysWithinProviderHistoryAreFetched() {
        let store = makeStore()
        let now = date("2025-06-10")

        XCTAssertEqual(store.missingDays(for: [now, date("2025-06-11"), date("1998-12-31"), date("2025-06-09")], now: now), [RateDay(year: 2025, month: 6, day: 9)])
    }

    // MARK: - Cache file

    func testCacheIsSharedThroughTheFile() async {
        let app = makeStore()
        let widget = makeStore()
        let now = date("2025-06-10")
        XCTAssertNil(widget.unitsPerDollar(of: "EUR", on: now))

        stub(.currencyAPILatest, currencyAPI("2025-06-09", ["EUR": 0.9]))
        await app.refresh(dates: [], now: now)

        widget.reloadIfChanged()
        XCTAssertEqual(widget.unitsPerDollar(of: "EUR", on: now), 0.9)
        XCTAssertEqual(makeStore().unitsPerDollar(of: "EUR", on: now), 0.9)
    }

    func testCorruptCacheIsDiscardedAndRefetched() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: fileURL)
        let store = makeStore()
        let now = date("2025-06-10")

        XCTAssertNil(store.unitsPerDollar(of: "EUR", on: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        stub(.currencyAPILatest, currencyAPI("2025-06-09", ["EUR": 0.9]))
        await store.refresh(dates: [], now: now)
        XCTAssertEqual(makeStore().unitsPerDollar(of: "EUR", on: now), 0.9)
    }

    func testCacheFromAnotherFormatVersionIsDiscarded() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version": 99, "days": {}, "coveredDays": []}"#.utf8).write(to: fileURL)

        XCTAssertEqual(makeStore().snapshot, ExchangeRateCache())
    }
}
