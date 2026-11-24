//
//  CSVCurrencyTests.swift
//  dimeTests
//

@testable import dime
import XCTest

final class CSVCurrencyTests: XCTestCase {
    private let dateFormat = "yyyy-MM-dd HH:mm:ss Z"

    private func build(_ text: String) throws -> (mapping: ColumnMapping, result: ImportParseResult) {
        let table = try XCTUnwrap(CSVTable.parse(text))
        let mapping = ColumnMapping.detect(in: table)
        return (mapping, ImportParseResult.build(table: table, mapping: mapping, dateFormat: dateFormat))
    }

    func testExportKeepsEarlierColumnsAndEachCurrencysDigits() {
        XCTAssertTrue(CSVExport.header.hasPrefix("Date,Note,Amount,Category,Type,"))
        XCTAssertEqual(CSVExport.header, "Date,Note,Amount,Category,Type,Currency\n")
        XCTAssertEqual(CSVExport.amount(12.5, currencyCode: "USD"), "12.50")
        XCTAssertEqual(CSVExport.amount(1.25, currencyCode: "KWD"), "1.250")
        XCTAssertEqual(CSVExport.amount(1_200, currencyCode: "JPY"), "1200.00")
    }

    func testExportedFileImportsWithItsCurrencies() throws {
        let text = CSVExport.header + """
        2025-03-01 12:00:00 +0000,Lunch,12.50,Food,Expense,USD
        2025-03-02 09:30:00 +0000,Ramen,1200.00,Food,Expense,JPY
        2025-03-03 18:00:00 +0000,Salary,4000.00,Salary,Income,usd

        """
        let (mapping, result) = try build(text)

        XCTAssertEqual(mapping[.currency], 5)
        XCTAssertEqual(mapping[.category], 3)
        XCTAssertEqual(mapping[.type], 4)
        XCTAssertEqual(result.rows.map(\.currencyCode), ["USD", "JPY", "USD"])
        XCTAssertEqual(result.rows.map(\.amount), [12.5, 1_200, 4_000])
        XCTAssertEqual(result.skippedCount, 0)
    }

    func testFilesWithoutACurrencyColumnUseTheMainCurrency() throws {
        let text = """
        Date,Note,Amount,Category,Type
        2025-03-01 12:00:00 +0000,Lunch,12.50,Food,Expense
        2025-03-02 09:30:00 +0000,Taxi,8.00,Transport,Expense

        """
        let (mapping, result) = try build(text)

        XCTAssertNil(mapping[.currency])
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows.allSatisfy { $0.currencyCode == nil })
    }

    func testUnknownCurrenciesAreSkippedAndEmptyOnesUseTheMainCurrency() throws {
        let text = """
        Date,Note,Amount,Category,Currency
        2025-03-01 12:00:00 +0000,Lunch,12.50,Food,EUR
        2025-03-02 09:30:00 +0000,Taxi,8.00,Transport,
        2025-03-03 09:30:00 +0000,Book,20.00,Shopping,EUR

        """
        let table = try XCTUnwrap(CSVTable.parse(text))
        var mapping = ColumnMapping.detect(in: table)
        XCTAssertEqual(mapping[.currency], 4)

        let rows = table.rows.enumerated().map { index, row in index == 2 ? Array(row.dropLast()) + ["Bitcoin"] : row }
        let edited = CSVTable(headers: table.headers, hasHeaderRow: true, rows: rows)
        mapping[.currency] = 4
        let result = ImportParseResult.build(table: edited, mapping: mapping, dateFormat: dateFormat)

        XCTAssertEqual(result.rows.map(\.currencyCode), ["EUR", nil])
        XCTAssertEqual(result.skipped[.currency], 1)
    }

    func testCurrencyColumnIsNotTakenForACategory() throws {
        let text = """
        2025-03-01 12:00:00 +0000,Lunch at the market,12.50,EUR,Food
        2025-03-02 09:30:00 +0000,Taxi home,8.00,EUR,Transport
        2025-03-03 09:30:00 +0000,Ramen,1200,JPY,Food

        """
        let (mapping, result) = try build(text)

        XCTAssertEqual(mapping[.currency], 3)
        XCTAssertEqual(mapping[.category], 4)
        XCTAssertEqual(result.rows.map(\.categoryName), ["Food", "Transport", "Food"])
    }

    func testImportedRowsConvertLikeTransactions() {
        let row = ImportedRow(date: Date(timeIntervalSinceReferenceDate: 0), amount: 10, note: "", categoryName: "Food", income: nil, currencyCode: "EUR")
        let entry = row.money(income: false)

        XCTAssertEqual(entry.currencyCode, "EUR")
        XCTAssertEqual(CurrencyConverter(mainCurrency: "USD").total(of: [entry]).report.excludedCount, 1)
    }
}
