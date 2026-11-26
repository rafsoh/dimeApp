//
//  DataIntegrityLogTests.swift
//  dimeTests
//

import CloudKit
@testable import dime
import XCTest

final class DataIntegrityLogTests: XCTestCase {
    func testOutOfSpaceIsFoundAnywhereInTheErrorChain() {
        // DIME-IOS-J arrived as SQLite's own error; Core Data saves usually wrap it.
        XCTAssertTrue(DataIntegrityLog.isOutOfSpace(NSError(domain: "NSSQLiteErrorDomain", code: 13)))

        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "NSSQLiteErrorDomain", code: 13)
        ])
        XCTAssertTrue(DataIntegrityLog.isOutOfSpace(wrapped))

        let codeInUserInfo = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: ["NSSQLiteErrorDomain": NSNumber(value: 13)])
        XCTAssertTrue(DataIntegrityLog.isOutOfSpace(codeInUserInfo))

        XCTAssertTrue(DataIntegrityLog.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
        XCTAssertTrue(DataIntegrityLog.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        ])))

        XCTAssertFalse(DataIntegrityLog.isOutOfSpace(NSError(domain: "NSSQLiteErrorDomain", code: 5)))
        XCTAssertFalse(DataIntegrityLog.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: 134_110)))
    }

    func testExceptionReasonsLoseTheRecordTheyDescribe() {
        // The shape of a reason Sentry received, cut off partway through the note as Sentry cuts it.
        let reason = """
        Illegal attempt to establish a relationship 'category' between objects in different contexts (source = <Transaction: 0x13b6f53b0> (entity: Transaction; id: 0xbdaf0d9217c9db13 <x-coredata://0472793F-6BEC-42E7-B004-43A646564D0F/Transaction/p5>; data: {
            amount = 40;
            currencyCode = CHF;
            note = "Sta
        """

        let redacted = DataIntegrityLog.redactedExceptionReason(reason)

        XCTAssertTrue(redacted.hasPrefix("Illegal attempt to establish a relationship 'category' between objects in different contexts"))
        XCTAssertFalse(redacted.contains("40"))
        XCTAssertFalse(redacted.contains("CHF"))
        XCTAssertFalse(redacted.contains("Sta"))
        XCTAssertFalse(redacted.contains("0472793F"))

        let quoted = DataIntegrityLog.redactedExceptionReason(#"Unacceptable value "Rent for March" for key note"#)
        XCTAssertFalse(quoted.contains("Rent"))
        XCTAssertTrue(quoted.contains("for key note"))

        XCTAssertEqual(
            DataIntegrityLog.redactedExceptionReason("*** -[__NSArray0 objectAtIndex:]: index 0 beyond bounds for empty array"),
            "*** -[__NSArray0 objectAtIndex:]: index 0 beyond bounds for empty array"
        )
    }

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
