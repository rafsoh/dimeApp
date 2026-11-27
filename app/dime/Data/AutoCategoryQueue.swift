//
//  AutoCategoryQueue.swift
//  dime
//
//  Feature Lab's Auto-Categorise, as far as everything that saves transactions needs it: the app, its
//  widgets and Shortcuts. Apple Intelligence itself only runs in the app (see AutoCategorizer).
//

import CoreData
import Foundation

/// Transactions waiting for Apple Intelligence to pick their category, and the ones the user wants left
/// without one. Kept in the app group, so a transaction logged from a widget is categorised the next time
/// Dime opens.
struct AutoCategoryQueue {
    /// The Feature Lab switch.
    static let enabledKey = "autoCategorise"

    /// Posted when transactions are queued, so the app can start on them straight away.
    static let didQueueNotification = Notification.Name("DimeAutoCategoryDidQueue")

    private static let queueKey = "autoCategoriseQueue"
    private static let keptKey = "autoCategoriseKeptUncategorised"

    /// How many transactions the user left without a category are remembered.
    static let keptLimit = 2000

    /// A queued transaction that doesn't turn up for this long, deleted or never synced, is forgotten.
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    /// Tries before a transaction the model keeps failing on is left as it is.
    static let maximumAttempts = 3

    struct Entry: Codable, Equatable {
        var queuedAt: Date
        var attempts: Int
    }

    let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.com.rafaelsoh.dime")) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults?.bool(forKey: Self.enabledKey) == true
    }

    // MARK: Which transactions

    /// Whether the transaction is one to categorise: it has no category, isn't a transfer, has a note with
    /// words or emoji in it, and isn't one the user chose to leave without a category.
    func wantsCategory(_ transaction: Transaction) -> Bool {
        guard !transaction.isGone, transaction.category == nil, !transaction.isTransfer,
              Self.hasMeaningfulText(transaction.wrappedNote)
        else {
            return false
        }

        return !isKeptUncategorised(transaction)
    }

    /// A note of only numbers and punctuation can't say what something was, so it isn't worth asking about.
    static func hasMeaningfulText(_ note: String) -> Bool {
        note.unicodeScalars.contains { CharacterSet.letters.contains($0) || $0.properties.isEmojiPresentation }
    }

    // MARK: Left without a category

    /// Remembers that the user took the transaction's category away, so it's never given one again.
    func keepUncategorised(_ transaction: Transaction) {
        guard let id = transaction.id?.uuidString else {
            return
        }

        var kept = defaults?.stringArray(forKey: Self.keptKey) ?? []
        kept.removeAll { $0 == id }
        kept.append(id)
        defaults?.set(Array(kept.suffix(Self.keptLimit)), forKey: Self.keptKey)

        remove([transaction])
    }

    func isKeptUncategorised(_ transaction: Transaction) -> Bool {
        guard let id = transaction.id?.uuidString else {
            return false
        }

        return defaults?.stringArray(forKey: Self.keptKey)?.contains(id) == true
    }

    // MARK: Queue

    var entries: [UUID: Entry] {
        guard let data = defaults?.data(forKey: Self.queueKey),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }

        var entries: [UUID: Entry] = [:]

        for (key, entry) in stored {
            if let id = UUID(uuidString: key) {
                entries[id] = entry
            }
        }

        return entries
    }

    private func store(_ entries: [UUID: Entry]) {
        guard !entries.isEmpty else {
            defaults?.removeObject(forKey: Self.queueKey)
            return
        }

        var stored: [String: Entry] = [:]

        for (id, entry) in entries {
            stored[id.uuidString] = entry
        }

        if let data = try? JSONEncoder().encode(stored) {
            defaults?.set(data, forKey: Self.queueKey)
        }
    }

    /// Queues the transactions that want a category, when the Feature Lab switch is on. Call it once
    /// they're saved.
    ///
    /// - Parameter announce: Whether to post `didQueueNotification`, so the app starts on them.
    /// - Returns: Whether any were queued.
    @discardableResult
    func add(_ transactions: [Transaction], announce: Bool = true) -> Bool {
        guard isEnabled else {
            return false
        }

        let ids = transactions.filter { wantsCategory($0) }.compactMap(\.id)

        guard !ids.isEmpty else {
            return false
        }

        var current = entries

        for id in ids where current[id] == nil {
            current[id] = Entry(queuedAt: .now, attempts: 0)
        }

        store(current)

        if announce {
            NotificationCenter.default.post(name: Self.didQueueNotification, object: nil)
        }

        return true
    }

    /// Queues a new occurrence of a recurring transaction, unless the user left the recurring transaction
    /// without a category: then the occurrence is left without one too.
    func addOccurrence(_ occurrence: Transaction, of recurring: Transaction) {
        if isKeptUncategorised(recurring) {
            keepUncategorised(occurrence)
        } else {
            add([occurrence])
        }
    }

    func remove(_ transactions: [Transaction]) {
        remove(ids: transactions.compactMap(\.id))
    }

    func remove(ids: [UUID]) {
        var current = entries

        guard ids.contains(where: { current[$0] != nil }) else {
            return
        }

        for id in ids {
            current[id] = nil
        }

        store(current)
    }

    /// Counts a try that failed, say because the model was busy. After `maximumAttempts` the transaction is
    /// forgotten and stays as the user logged it.
    func recordFailedAttempt(ids: [UUID]) {
        var current = entries

        for id in ids {
            guard var entry = current[id] else {
                continue
            }

            entry.attempts += 1
            current[id] = entry.attempts >= Self.maximumAttempts ? nil : entry
        }

        store(current)
    }

    /// Forgets transactions queued so long ago that they're never going to turn up.
    func removeExpired(now: Date = .now) {
        let current = entries
        let kept = current.filter { now.timeIntervalSince($0.value.queuedAt) < Self.lifetime }

        if kept.count != current.count {
            store(kept)
        }
    }

    func clear() {
        defaults?.removeObject(forKey: Self.queueKey)
    }
}
