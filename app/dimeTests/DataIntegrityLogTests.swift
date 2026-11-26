//
//  DataIntegrityLogTests.swift
//  dimeTests
//

import CloudKit
@testable import dime
import XCTest

final class DataIntegrityLogTests: XCTestCase {
    func testFailureSummaryKeepsDomainsAndCodesOnly() {
        let underlying = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.quotaExceeded.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Coffee 4.50"]
        )
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_100,
            userInfo: [
                NSLocalizedDescriptionKey: "Rent note for March",
                NSUnderlyingErrorKey: underlying,
                CKPartialErrorsByItemIDKey: [
                    "record": NSError(domain: "PartialDomain", code: 99, userInfo: [
                        NSLocalizedDescriptionKey: "Groceries 12.40"
                    ])
                ]
            ]
        )

        let summary = DataIntegrityLog.failureSummary(for: error)

        XCTAssertEqual(summary.domain, NSCocoaErrorDomain)
        XCTAssertEqual(summary.code, 134_100)
        XCTAssertTrue(summary.chain.contains("\(NSCocoaErrorDomain):134100"))
        XCTAssertTrue(summary.chain.contains("\(CKError.errorDomain):\(CKError.Code.quotaExceeded.rawValue)"))
        XCTAssertTrue(summary.chain.contains("PartialDomain:99"))
        XCTAssertFalse(summary.chain.contains("Coffee"))
        XCTAssertFalse(summary.chain.contains("4.50"))
        XCTAssertFalse(summary.chain.contains("Rent"))
        XCTAssertFalse(summary.chain.contains("March"))
        XCTAssertFalse(summary.chain.contains("Groceries"))
        XCTAssertFalse(summary.chain.contains("12.40"))
    }

    func testFailureSummaryRedactsDomainsThatLookLikeUserText() {
        let error = NSError(domain: "Spent 12.50 on coffee", code: 3, userInfo: nil)
        let summary = DataIntegrityLog.failureSummary(for: error)

        XCTAssertEqual(summary.domain, "redacted")
        XCTAssertEqual(summary.chain, "redacted:3")
        XCTAssertFalse(summary.chain.contains("coffee"))
        XCTAssertFalse(summary.chain.contains("12.50"))
    }
}
