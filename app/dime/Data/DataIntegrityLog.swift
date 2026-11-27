//
//  DataIntegrityLog.swift
//  dime
//
//  Privacy-safe diagnostics for store loading, migration, sync, backup, and bulk deletion.
//  Callers may pass counts, booleans, and short tokens (error domains, event types).
//  They must not pass notes, amounts, names, or any other user-entered text.
//

import CloudKit
import Foundation
import os

#if canImport(Sentry)
import Sentry
#endif

enum DataIntegrityLog {
    struct FailureSummary: Equatable {
        var domain: String
        var code: Int
        /// Domains and codes only, never `userInfo` values or localized text.
        var chain: String
    }

    private static let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "DataIntegrity")
    private static let lock = NSLock()
    private static let pendingKey = "dime.dataIntegrity.pending"
    private static let maximumPending = 40
    private static let suiteName = "group.com.rafaelsoh.dime"
    private static let allowedTokenCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")

    /// A breadcrumb. `persist` keeps it for the app to forward when this process has no Sentry SDK
    /// (widgets and intents). Routine breadcrumbs stay in memory only.
    static func breadcrumb(
        _ message: String,
        numbers: [String: Int] = [:],
        flags: [String: Bool] = [:],
        tokens: [String: String] = [:],
        persist: Bool = false
    ) {
        deliver(message: message, capture: false, error: nil, numbers: numbers, flags: flags, tokens: tokens, persist: persist)
    }

    static func capture(
        _ message: String,
        numbers: [String: Int] = [:],
        flags: [String: Bool] = [:],
        tokens: [String: String] = [:]
    ) {
        deliver(message: message, capture: true, error: nil, numbers: numbers, flags: flags, tokens: tokens, persist: true)
    }

    static func capture(
        _ error: Error,
        message: String,
        numbers: [String: Int] = [:],
        flags: [String: Bool] = [:],
        tokens: [String: String] = [:]
    ) {
        deliver(message: message, capture: true, error: error, numbers: numbers, flags: flags, tokens: tokens, persist: true)
    }

    /// One captured event per app version for this key, shared across the app and its extensions.
    static func captureOnce(
        key: String,
        message: String,
        numbers: [String: Int] = [:],
        flags: [String: Bool] = [:],
        tokens: [String: String] = [:]
    ) {
        let storageKey = onceStorageKey(key)
        guard markOnce(storageKey) else {
            return
        }

        deliver(message: message, capture: true, error: nil, numbers: numbers, flags: flags, tokens: tokens, persist: true)
    }

    static func failureSummary(for error: Error) -> FailureSummary {
        var parts: [String] = []
        var pending: [NSError] = [error as NSError]
        var seen = 0

        while let next = pending.popLast(), seen < 8 {
            seen += 1
            parts.append("\(safeToken(next.domain)):\(next.code)")

            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? Error {
                pending.append(underlying as NSError)
            }

            if let multiple = next.userInfo[NSMultipleUnderlyingErrorsKey] as? [Any] {
                pending.append(contentsOf: multiple.prefix(4).compactMap { $0 as? Error }.map { $0 as NSError })
            }

            // Partial CloudKit failures can carry the record itself. Keep the error code only.
            if let partial = next.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any] {
                let partialErrors = partial.values.compactMap { $0 as? Error }.prefix(3)
                pending.append(contentsOf: partialErrors.map { $0 as NSError })
            }
        }

        let primary = error as NSError
        let chain = parts.joined(separator: " | ")
        return FailureSummary(domain: safeToken(primary.domain), code: primary.code, chain: String(chain.prefix(300)))
    }

    /// Sends diagnostics an extension stored in the app group. No-op until the app starts Sentry.
    static func flushPending() {
        #if canImport(Sentry)
        for record in dequeueAll() {
            send(record)
        }
        #endif
    }

    // MARK: - Delivery

    private struct PendingRecord: Codable {
        var message: String
        var capture: Bool
        var numbers: [String: Int]
        var flags: [String: Bool]
        var tokens: [String: String]
        var failureDomain: String?
        var failureCode: Int?
        var failureChain: String?
    }

    private static func deliver(
        message: String,
        capture: Bool,
        error: Error?,
        numbers: [String: Int],
        flags: [String: Bool],
        tokens: [String: String],
        persist: Bool
    ) {
        var safeTokens = tokens.mapValues(safeToken)
        safeTokens["process"] = processToken

        let summary = error.map(failureSummary(for:))
        if let summary {
            safeTokens["failureDomain"] = summary.domain
        }

        let record = PendingRecord(
            message: message,
            capture: capture,
            numbers: numbers,
            flags: flags,
            tokens: safeTokens,
            failureDomain: summary?.domain,
            failureCode: summary?.code,
            failureChain: summary?.chain
        )

        logLocally(record)

        #if canImport(Sentry)
        send(record)
        #else
        if capture || persist {
            enqueue(record)
        }
        #endif
    }

    private static var processToken: String {
        let identifier = Bundle.main.bundleIdentifier ?? "app"
        return safeToken(identifier.split(separator: ".").last.map(String.init) ?? "app")
    }

    private static func logLocally(_ record: PendingRecord) {
        let numbers = record.numbers.keys.sorted().map { "\($0)=\(record.numbers[$0] ?? 0)" }.joined(separator: " ")
        let flags = record.flags.keys.sorted().map { "\($0)=\(record.flags[$0] == true ? "1" : "0")" }.joined(separator: " ")
        let tokens = record.tokens.keys.sorted().map { "\($0)=\(record.tokens[$0] ?? "")" }.joined(separator: " ")
        logger.notice("\(record.message, privacy: .public) \(numbers, privacy: .public) \(flags, privacy: .public) \(tokens, privacy: .public) \(record.failureChain ?? "", privacy: .public)")
    }

    #if canImport(Sentry)
    private static func send(_ record: PendingRecord) {
        if record.capture {
            let sendEvent: (Scope) -> Void = { scope in
                scope.setContext(value: context(from: record), key: "data_integrity")
            }

            if let domain = record.failureDomain, let code = record.failureCode {
                let error = NSError(domain: domain, code: code, userInfo: [
                    NSLocalizedDescriptionKey: "\(domain) \(code)",
                    "chain": record.failureChain ?? ""
                ])
                SentrySDK.capture(error: error, block: sendEvent)
            } else {
                SentrySDK.capture(message: record.message, block: sendEvent)
            }
        } else {
            let crumb = Breadcrumb(level: .info, category: "data.integrity")
            crumb.type = "info"
            crumb.message = record.message
            for (key, value) in context(from: record) {
                crumb.setData(value: value, key: key)
            }
            SentrySDK.addBreadcrumb(crumb)
        }
    }

    private static func context(from record: PendingRecord) -> [String: Any] {
        var context: [String: Any] = ["event": record.message]
        for (key, value) in record.numbers {
            context[key] = value
        }
        for (key, value) in record.flags {
            context[key] = value
        }
        for (key, value) in record.tokens {
            context[key] = value
        }
        if let chain = record.failureChain {
            context["chain"] = chain
        }
        return context
    }
    #endif

    // MARK: - App group queue

    private static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private static func enqueue(_ record: PendingRecord) {
        lock.lock()
        defer { lock.unlock() }

        var records = decodePending(defaults()?.data(forKey: pendingKey))
        records.append(record)
        if records.count > maximumPending {
            records.removeFirst(records.count - maximumPending)
        }
        defaults()?.set(encodePending(records), forKey: pendingKey)
    }

    private static func dequeueAll() -> [PendingRecord] {
        lock.lock()
        defer { lock.unlock() }

        let records = decodePending(defaults()?.data(forKey: pendingKey))
        defaults()?.removeObject(forKey: pendingKey)
        return records
    }

    private static func decodePending(_ data: Data?) -> [PendingRecord] {
        guard let data else {
            return []
        }
        return (try? JSONDecoder().decode([PendingRecord].self, from: data)) ?? []
    }

    private static func encodePending(_ records: [PendingRecord]) -> Data? {
        try? JSONEncoder().encode(records)
    }

    private static func onceStorageKey(_ key: String) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "dime.dataIntegrity.once.\(safeToken(key)).\(safeToken(version)).\(safeToken(build))"
    }

    private static func markOnce(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let defaults = defaults() else {
            return true
        }
        if defaults.bool(forKey: key) {
            return false
        }
        defaults.set(true, forKey: key)
        return true
    }

    /// The distinct per-record codes inside a CloudKit partial failure (CKError 2), such as "14_26" for
    /// serverRecordChanged and zoneNotFound. Empty when the chain has none.
    static func partialErrorCodes(in error: Error) -> String {
        var codes = Set<Int>()
        var pending: [NSError] = [error as NSError]
        var seen = 0

        while let next = pending.popLast(), seen < 12 {
            seen += 1

            if let partial = next.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any] {
                for case let itemError as NSError in partial.values.prefix(50) {
                    codes.insert(itemError.code)
                }
            }

            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? Error {
                pending.append(underlying as NSError)
            }
        }

        return codes.sorted().prefix(5).map(String.init).joined(separator: "_")
    }

    /// Whether the device ran out of storage anywhere in the error chain: SQLite's "database or disk is full"
    /// (code 13, which Core Data often reports under its own error), a file write out of space, or ENOSPC.
    static func isOutOfSpace(_ error: Error) -> Bool {
        var pending: [NSError] = [error as NSError]
        var seen = 0

        while let next = pending.popLast(), seen < 12 {
            seen += 1

            switch (next.domain, next.code) {
            case ("NSSQLiteErrorDomain", 13), (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)):
                return true
            default:
                break
            }

            if (next.userInfo["NSSQLiteErrorDomain"] as? NSNumber)?.intValue == 13 {
                return true
            }

            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? Error {
                pending.append(underlying as NSError)
            }

            if let multiple = next.userInfo[NSMultipleUnderlyingErrorsKey] as? [Any] {
                pending.append(contentsOf: multiple.prefix(4).compactMap { $0 as? Error }.map { $0 as NSError })
            }
        }

        return false
    }

    /// Crash reasons can carry a whole record. Core Data's relationship and validation exceptions describe the
    /// objects involved: "(source = <Transaction: 0x…> (entity: Transaction; id: … <x-coredata://…>; data: {
    /// amount = 40; currencyCode = CHF; note = "…" … })". The sentence stays; the record, its store id and
    /// anything quoted are removed.
    static func redactedExceptionReason(_ reason: String) -> String {
        var value = reason

        if let range = value.range(of: "data: {") ?? value.range(of: "data: <") {
            value = String(value[..<range.lowerBound]) + "data: <redacted>"
        }

        value = value.replacingOccurrences(of: #"x-coredata://[^\s>]*"#, with: "x-coredata://<redacted>", options: .regularExpression)
        value = value.replacingOccurrences(of: #""[^"]*"?"#, with: "\"<redacted>\"", options: .regularExpression)

        if value.count > 400 {
            value = String(value.prefix(400)) + "…"
        }

        return value
    }

    /// Keeps error domains and other tokens. Anything with spaces or punctuation is dropped,
    /// because that is where a note, name, or amount would show up.
    static func safeToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, trimmed.unicodeScalars.allSatisfy({ allowedTokenCharacters.contains($0) }) else {
            return "redacted"
        }
        return trimmed
    }
}
