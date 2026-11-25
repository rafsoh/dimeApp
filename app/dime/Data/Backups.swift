//
//  Backups.swift
//  dime
//

import CoreData
import Foundation
import os
import SwiftUI
import WidgetKit

#if os(iOS)
import UIKit
#endif

struct BackupSummary: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let transactionCount: Int

    var id: URL { url }
}

struct RestoreResult {
    var transactions = 0
    var categories = 0
    var budgets = 0
    var templates = 0

    var total: Int { transactions + categories + budgets + templates }
}

private struct BackupFile: Codable {
    // 2 added Transaction.currencyCode.
    static let currentVersion = 2

    var version = BackupFile.currentVersion
    var createdAt: Date
    // What a transaction without a currency was in when this was written.
    var mainCurrency: String?
    var categories: [CategoryRecord]
    var transactions: [TransactionRecord]
    var budgets: [BudgetRecord]
    var mainBudgets: [MainBudgetRecord]
    var templates: [TemplateRecord]
}

private struct CategoryRecord: Codable {
    var ref: String
    var id: UUID?
    var name: String?
    var emoji: String?
    var colour: String?
    var income: Bool
    var order: Int64
    var dateCreated: Date?
}

private struct TransactionRecord: Codable {
    var id: UUID?
    var note: String?
    var amount: Double
    var date: Date?
    var day: Date?
    var month: Date?
    var income: Bool
    var onceRecurring: Bool
    var recurringType: Int16
    var recurringCoefficient: Int16
    var categoryRef: String?
    var currencyCode: String?

    // Matches transactions from versions that didn't assign ids. Leaves out the currency so backups
    // written before it existed still match.
    static func contentKey(date: Date?, amount: Double, note: String?, income: Bool) -> String {
        "\(date?.timeIntervalSinceReferenceDate ?? 0)|\(amount)|\(note ?? "")|\(income)"
    }
}

private struct BudgetRecord: Codable {
    var id: UUID?
    var amount: Double
    var dateCreated: Date?
    var green: Bool
    var startDate: Date?
    var type: Int16
    var categoryRef: String?
    // Rollover, added later: optional so older backups still decode.
    var rolloverEnabled: Bool?
    var rolloverAnchor: Date?
    var rolloverBalance: Double?
}

private struct MainBudgetRecord: Codable {
    var amount: Double
    var dateCreated: Date?
    var green: Bool
    var startDate: Date?
    var type: Int16
    var rolloverEnabled: Bool?
    var rolloverAnchor: Date?
    var rolloverBalance: Double?
}

private struct TemplateRecord: Codable {
    var id: UUID?
    var amount: Double
    var income: Bool
    var note: String?
    var order: Int16
    var recurringCoefficient: Int16
    var recurringType: Int16
    var categoryRef: String?
    /// Missing from backups made before templates had a currency; those templates use the main currency.
    var currencyCode: String?
}

// Backups are plain JSON rather than copies of the SQLite file, so restoring never touches the CloudKit
// mirroring metadata stored in the database.
struct BackupStore {
    enum FormatError: Error {
        case newerVersion(Int)
    }

    let directory: URL
    var maximumCount = 14

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    // A drop this large since the last backup is treated as data loss rather than the user tidying up.
    static func looksLikeDataLoss(currentTransactionCount: Int, backupTransactionCount: Int) -> Bool {
        backupTransactionCount >= 10 && currentTransactionCount * 2 < backupTransactionCount
    }

    func list() -> [BackupSummary] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap(Self.summary(for:)).sorted { $0.createdAt > $1.createdAt }
    }

    // File names carry the date and transaction count so listing never has to read the backups.
    private static func summary(for url: URL) -> BackupSummary? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")

        guard url.pathExtension == "json", parts.count == 3, parts[0] == "backup",
              let seconds = TimeInterval(parts[1]), let transactionCount = Int(parts[2])
        else {
            return nil
        }

        return BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: seconds), transactionCount: transactionCount)
    }

    private static func reference(for category: Category) -> String {
        category.id?.uuidString ?? category.objectID.uriRepresentation().absoluteString
    }

    // Call on the context's queue.
    @discardableResult
    func write(from context: NSManagedObjectContext, at date: Date = .now, mainCurrency: String? = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.string(forKey: "currency")) throws -> BackupSummary {
        let categories: [Category] = try context.fetch(Category.fetchRequest())
        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        transactionRequest.relationshipKeyPathsForPrefetching = ["category"]
        let transactions = try context.fetch(transactionRequest)
        let budgets: [Budget] = try context.fetch(Budget.fetchRequest())
        let mainBudgets: [MainBudget] = try context.fetch(MainBudget.fetchRequest())
        let templates: [TemplateTransaction] = try context.fetch(TemplateTransaction.fetchRequest())

        let file = BackupFile(
            createdAt: date,
            mainCurrency: mainCurrency?.uppercased(),
            categories: categories.map {
                CategoryRecord(ref: Self.reference(for: $0), id: $0.id, name: $0.name, emoji: $0.emoji, colour: $0.colour, income: $0.income, order: $0.order, dateCreated: $0.dateCreated)
            },
            transactions: transactions.map {
                TransactionRecord(id: $0.id, note: $0.note, amount: $0.amount, date: $0.date, day: $0.day, month: $0.month, income: $0.income, onceRecurring: $0.onceRecurring, recurringType: $0.recurringType, recurringCoefficient: $0.recurringCoefficient, categoryRef: $0.category.map(Self.reference(for:)), currencyCode: $0.currencyCode)
            },
            budgets: budgets.map {
                BudgetRecord(id: $0.id, amount: $0.amount, dateCreated: $0.dateCreated, green: $0.green, startDate: $0.startDate, type: $0.type, categoryRef: $0.category.map(Self.reference(for:)), rolloverEnabled: $0.rolloverEnabled, rolloverAnchor: $0.rolloverAnchor, rolloverBalance: $0.rolloverBalance)
            },
            mainBudgets: mainBudgets.map {
                MainBudgetRecord(amount: $0.amount, dateCreated: $0.dateCreated, green: $0.green, startDate: $0.startDate, type: $0.type, rolloverEnabled: $0.rolloverEnabled, rolloverAnchor: $0.rolloverAnchor, rolloverBalance: $0.rolloverBalance)
            },
            templates: templates.map {
                TemplateRecord(id: $0.id, amount: $0.amount, income: $0.income, note: $0.note, order: $0.order, recurringCoefficient: $0.recurringCoefficient, recurringType: $0.recurringType, categoryRef: $0.category.map(Self.reference(for:)), currencyCode: $0.currencyCode)
            }
        )

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("backup-\(Int(date.timeIntervalSince1970))-\(transactions.count).json")
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
        prune()

        return BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: TimeInterval(Int(date.timeIntervalSince1970))), transactionCount: transactions.count)
    }

    private func prune() {
        for backup in list().dropFirst(maximumCount) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    // Adds back whatever the backup has and the store lacks, matched by id. Existing objects are never
    // changed or removed. Call on the context's queue; the caller saves.
    func restore(_ backup: BackupSummary, into context: NSManagedObjectContext) throws -> RestoreResult {
        let file = try JSONDecoder().decode(BackupFile.self, from: Data(contentsOf: backup.url))

        // Fields this version doesn't know would be dropped from the restored objects.
        guard file.version <= BackupFile.currentVersion else {
            throw FormatError.newerVersion(file.version)
        }

        var result = RestoreResult()

        var categories: [Category] = try context.fetch(Category.fetchRequest())
        var categoriesByRef: [String: Category] = [:]

        for record in file.categories {
            // A category recreated after data loss has a new id; categories are unique by name and by emoji.
            let match = categories.first { record.id != nil && $0.id == record.id }
                ?? categories.first { $0.income == record.income && record.name != nil && $0.name?.caseInsensitiveCompare(record.name ?? "") == .orderedSame }
                ?? categories.first { $0.income == record.income && record.emoji != nil && $0.emoji == record.emoji }

            if let match {
                categoriesByRef[record.ref] = match
                continue
            }

            let category = Category(context: context)
            category.id = record.id ?? UUID()
            category.name = record.name
            category.emoji = record.emoji
            category.colour = record.colour
            category.income = record.income
            category.order = record.order
            category.dateCreated = record.dateCreated
            categoriesByRef[record.ref] = category
            categories.append(category)
            result.categories += 1
        }

        let existingTransactions: [Transaction] = try context.fetch(Transaction.fetchRequest())
        var transactionIDs = Set(existingTransactions.compactMap(\.id))
        var transactionKeys = Set(existingTransactions.map {
            TransactionRecord.contentKey(date: $0.date, amount: $0.amount, note: $0.note, income: $0.income)
        })

        for record in file.transactions {
            if let id = record.id {
                guard transactionIDs.insert(id).inserted else {
                    continue
                }
            } else {
                guard transactionKeys.insert(TransactionRecord.contentKey(date: record.date, amount: record.amount, note: record.note, income: record.income)).inserted else {
                    continue
                }
            }

            let transaction = Transaction(context: context)
            transaction.id = record.id ?? UUID()
            transaction.note = record.note
            transaction.amount = record.amount
            // The main currency may have changed since the backup, so a missing currency is pinned to the one it meant.
            transaction.currencyCode = record.currencyCode ?? file.mainCurrency
            transaction.date = record.date
            transaction.day = record.day
            transaction.month = record.month
            transaction.income = record.income
            transaction.onceRecurring = record.onceRecurring
            transaction.recurringType = record.recurringType
            transaction.recurringCoefficient = record.recurringCoefficient
            transaction.category = record.categoryRef.flatMap { categoriesByRef[$0] }
            result.transactions += 1
        }

        let existingBudgets: [Budget] = try context.fetch(Budget.fetchRequest())
        var budgetIDs = Set(existingBudgets.compactMap(\.id))

        for record in file.budgets {
            if let id = record.id, budgetIDs.contains(id) {
                continue
            }

            let category = record.categoryRef.flatMap { categoriesByRef[$0] }

            if category?.budget != nil {
                continue
            }

            let id = record.id ?? UUID()
            let budget = Budget(context: context)
            budget.id = id
            budget.amount = record.amount
            budget.dateCreated = record.dateCreated
            budget.green = record.green
            budget.startDate = record.startDate
            budget.type = record.type
            budget.category = category
            budget.rolloverEnabled = record.rolloverEnabled ?? false
            budget.rolloverAnchor = record.rolloverAnchor
            budget.rolloverBalance = record.rolloverBalance ?? 0
            budgetIDs.insert(id)
            result.budgets += 1
        }

        let mainBudgetRequest: NSFetchRequest<MainBudget> = MainBudget.fetchRequest()

        if try context.count(for: mainBudgetRequest) == 0, let record = file.mainBudgets.first {
            let mainBudget = MainBudget(context: context)
            mainBudget.amount = record.amount
            mainBudget.dateCreated = record.dateCreated
            mainBudget.green = record.green
            mainBudget.startDate = record.startDate
            mainBudget.type = record.type
            mainBudget.rolloverEnabled = record.rolloverEnabled ?? false
            mainBudget.rolloverAnchor = record.rolloverAnchor
            mainBudget.rolloverBalance = record.rolloverBalance ?? 0
            result.budgets += 1
        }

        let existingTemplates: [TemplateTransaction] = try context.fetch(TemplateTransaction.fetchRequest())
        var templateIDs = Set(existingTemplates.compactMap(\.id))
        var templateOrders = Set(existingTemplates.map(\.order))

        for record in file.templates {
            if let id = record.id, templateIDs.contains(id) {
                continue
            }

            guard templateOrders.insert(record.order).inserted else {
                continue
            }

            let id = record.id ?? UUID()
            let template = TemplateTransaction(context: context)
            template.id = id
            template.amount = record.amount
            template.income = record.income
            template.note = record.note
            template.order = record.order
            template.recurringCoefficient = record.recurringCoefficient
            template.recurringType = record.recurringType
            template.category = record.categoryRef.flatMap { categoriesByRef[$0] }
            template.currencyCode = record.currencyCode
            templateIDs.insert(id)
            result.templates += 1
        }

        return result
    }
}

final class BackupManager: ObservableObject {
    struct SuggestedRestore: Identifiable {
        let backup: BackupSummary
        let currentTransactionCount: Int

        var id: URL { backup.url }
    }

    enum RestoreError: Error {
        case waitingForICloud
        case currencyChangeInProgress
    }

    static let shared = BackupManager(dataController: .shared)

    @Published private(set) var backups: [BackupSummary] = []
    @Published private(set) var isWorking = false
    @Published var suggestedRestore: SuggestedRestore?

    private static let backupInterval: TimeInterval = 20 * 60 * 60
    private static let handledBackupKey = "handledRestoreSuggestion"

    private let dataController: DataController
    private let store: BackupStore
    private let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "Backups")
    private var observer: NSObjectProtocol?

    init(dataController: DataController, store: BackupStore = BackupStore(directory: BackupStore.defaultDirectory)) {
        self.dataController = dataController
        self.store = store
    }

    private var isUsingTemporaryStore: Bool {
        dataController.container.persistentStoreCoordinator.persistentStores.first?.url?.path == "/dev/null"
    }

    func start() {
        guard observer == nil, !isUsingTemporaryStore else {
            return
        }

        refreshList()

        observer = NotificationCenter.default.addObserver(forName: DataController.dataIsCurrentNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkForMissingData()
        }

        if dataController.isDataCurrentWithICloud {
            checkForMissingData()
        }
    }

    func refreshList() {
        backups = store.list()
    }

    // The newest backup that a later deliberate bulk delete (a category, Erase All) hasn't superseded.
    private func referenceBackup(in backups: [BackupSummary]) -> BackupSummary? {
        guard let latest = backups.first else {
            return nil
        }

        if let deletion = defaults?.object(forKey: DataController.lastBulkDeletionKey) as? Date, deletion > latest.createdAt {
            return nil
        }

        if defaults?.string(forKey: Self.handledBackupKey) == latest.url.lastPathComponent {
            return nil
        }

        return latest
    }

    // Only called once the store is current with iCloud, so anything missing now is missing from iCloud too.
    func checkForMissingData() {
        guard suggestedRestore == nil, !isWorking, let backup = referenceBackup(in: store.list()) else {
            return
        }

        let currentCount = dataController.transactionCount()

        if BackupStore.looksLikeDataLoss(currentTransactionCount: currentCount, backupTransactionCount: backup.transactionCount) {
            suggestedRestore = SuggestedRestore(backup: backup, currentTransactionCount: currentCount)
        }
    }

    func dismissSuggestion(_ suggestion: SuggestedRestore) {
        defaults?.set(suggestion.backup.url.lastPathComponent, forKey: Self.handledBackupKey)
        suggestedRestore = nil
    }

    func backUpIfNeeded() {
        if let latest = store.list().first, Date.now.timeIntervalSince(latest.createdAt) < Self.backupInterval {
            return
        }

        backUp(automatic: true)
    }

    func backUpNow(completion: ((Bool) -> Void)? = nil) {
        backUp(automatic: false, completion: completion)
    }

    private func backUp(automatic: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !isUsingTemporaryStore, !isWorking else {
            completion?(false)
            return
        }

        isWorking = true
        let reference = referenceBackup(in: store.list())
        let finishBackgroundTask = beginBackgroundTask()

        dataController.container.performBackgroundTask { [store, logger] context in
            var succeeded = false

            do {
                let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
                let transactionCount = try context.count(for: transactionRequest)
                let isEmpty = try transactionCount == 0 && context.count(for: categoryRequest) == 0
                // Never let a wiped or shrunken store push good backups out of the rotation.
                let looksLost = reference.map {
                    BackupStore.looksLikeDataLoss(currentTransactionCount: transactionCount, backupTransactionCount: $0.transactionCount)
                } ?? false

                if !automatic || (!isEmpty && !looksLost) {
                    try store.write(from: context)
                    succeeded = true
                }
            } catch {
                logger.error("Backing up failed: \(String(describing: error), privacy: .public)")
            }

            DispatchQueue.main.async {
                self.isWorking = false
                self.refreshList()
                finishBackgroundTask()
                completion?(succeeded)
            }
        }
    }

    func restore(_ backup: BackupSummary, completion: @escaping (Result<RestoreResult, Error>) -> Void) {
        // Restoring before iCloud has caught up would re-add items that are about to be downloaded again.
        guard dataController.isDataCurrentWithICloud else {
            completion(.failure(RestoreError.waitingForICloud))
            return
        }

        // Rows restored mid-change could miss it and be read in the wrong currency.
        guard defaults?.data(forKey: MainCurrencyChangeManager.pendingPlanKey) == nil else {
            completion(.failure(RestoreError.currencyChangeInProgress))
            return
        }

        isWorking = true
        let context = dataController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform { [store] in
            let result = Result {
                let restored = try store.restore(backup, into: context)

                if context.hasChanges {
                    try context.save()
                }

                return restored
            }

            DispatchQueue.main.async {
                self.isWorking = false

                if case .success = result {
                    self.defaults?.set(backup.url.lastPathComponent, forKey: Self.handledBackupKey)
                    self.suggestedRestore = nil
                    WidgetCenter.shared.reloadAllTimelines()
                }

                completion(result)
            }
        }
    }

    private func beginBackgroundTask() -> () -> Void {
        #if os(iOS)
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Dime backup") {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }

        return {
            guard identifier != .invalid else {
                return
            }

            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        #else
        return {}
        #endif
    }
}
