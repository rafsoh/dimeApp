//
//  DataController.swift
//  Bonsai
//
//  Created by Rafael Soh on 3/6/22.
//

import CloudKit
import CoreData
import Foundation
import Network
import os
import SwiftUI
import WidgetKit

@available(iOS 16, *)
enum CustomError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notFound,
         coreDataSave,
         unknownId(id: String),
         unknownError(message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unknownError(message): return "An unknown error occurred: \(message)"
        case let .unknownId(id): return "No category with an ID matching: \(id)"
        case .notFound: return "Category not found"
        case .coreDataSave: return "Couldn't save to CoreData"
        }
    }
}

final class CloudSyncStatus: ObservableObject {
    struct Problem: Equatable {
        let message: String
        let detail: String?
    }

    enum Summary: Equatable {
        case off
        case waiting
        case syncing
        case upToDate
        case problem(Problem)
    }

    let isEnabled: Bool

    @Published private(set) var lastSynced: Date?
    @Published private var accountStatus: CKAccountStatus?
    @Published private var problems: [NSPersistentCloudKitContainer.EventType: Problem] = [:]
    @Published private var eventsInProgress: [UUID: NSPersistentCloudKitContainer.EventType] = [:]

    private static let lastSyncedKey = "lastICloudSync"
    private let containerIdentifier: String
    private var observers: [NSObjectProtocol] = []

    init(isEnabled: Bool, containerIdentifier: String) {
        self.isEnabled = isEnabled
        self.containerIdentifier = containerIdentifier
        lastSynced = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.object(forKey: Self.lastSyncedKey) as? Date

        guard isEnabled else {
            return
        }

        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            self?.handle(event)
        })

        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAccountStatus()
        })

        refreshAccountStatus()
    }

    var summary: Summary {
        guard isEnabled else {
            return .off
        }

        if let accountProblem {
            return .problem(accountProblem)
        }

        // Export failures come first: they mean changes made on this device exist nowhere else.
        if let problem = problems[.export] ?? problems[.import] ?? problems[.setup] {
            return .problem(problem)
        }

        if eventsInProgress.values.contains(where: { $0 != .setup }) {
            return .syncing
        }

        // Setup can stall indefinitely, for example while the iCloud account is being checked.
        if eventsInProgress.values.contains(.setup) || lastSynced == nil {
            return .waiting
        }

        return .upToDate
    }

    private var accountProblem: Problem? {
        guard let accountStatus else {
            return nil
        }

        switch accountStatus {
        case .available:
            return nil
        case .noAccount:
            return Problem(message: String(localized: "Sign in to iCloud in the Settings app to back up and sync your data."), detail: nil)
        case .restricted:
            return Problem(message: String(localized: "iCloud is restricted on this device, so your data isn't being backed up."), detail: nil)
        case .temporarilyUnavailable:
            return Problem(message: String(localized: "iCloud is temporarily unavailable. Check your Apple Account in the Settings app."), detail: nil)
        case .couldNotDetermine:
            return Problem(message: String(localized: "Couldn't check your iCloud account."), detail: nil)
        @unknown default:
            return Problem(message: String(localized: "Couldn't check your iCloud account."), detail: nil)
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard let endDate = event.endDate else {
            eventsInProgress[event.identifier] = event.type
            return
        }

        eventsInProgress[event.identifier] = nil

        if event.succeeded {
            problems[event.type] = nil

            if event.type != .setup {
                lastSynced = endDate
                UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(endDate, forKey: Self.lastSyncedKey)
            }
        } else if let error = event.error {
            problems[event.type] = Self.problem(for: error)
        }
    }

    private func refreshAccountStatus() {
        CKContainer(identifier: containerIdentifier).accountStatus { [weak self] status, _ in
            DispatchQueue.main.async {
                self?.accountStatus = status
            }
        }
    }

    static func problem(for error: Error) -> Problem {
        for code in cloudKitErrorCodes(in: error) {
            switch code {
            case .quotaExceeded:
                return Problem(message: String(localized: "Your iCloud storage is full, so new changes aren't being backed up or synced. Free up space in the Settings app."), detail: nil)
            case .notAuthenticated:
                return Problem(message: String(localized: "Sign in to iCloud in the Settings app to back up and sync your data."), detail: nil)
            case .accountTemporarilyUnavailable:
                return Problem(message: String(localized: "iCloud is temporarily unavailable. Check your Apple Account in the Settings app."), detail: nil)
            case .networkUnavailable, .networkFailure:
                return Problem(message: String(localized: "You're offline. Changes will sync when you're back online."), detail: nil)
            case .userDeletedZone:
                return Problem(message: String(localized: "Dime's data was deleted from iCloud in the Settings app."), detail: nil)
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return Problem(message: String(localized: "iCloud is busy right now. Dime will try again automatically."), detail: nil)
            default:
                continue
            }
        }

        let nsError = error as NSError
        return Problem(message: String(localized: "Sync ran into a problem and will try again."), detail: "\(nsError.domain) \(nsError.code)")
    }

    static func isNetworkError(_ error: Error) -> Bool {
        cloudKitErrorCodes(in: error).contains { $0 == .networkUnavailable || $0 == .networkFailure }
    }

    // NSPersistentCloudKitContainer wraps CloudKit errors in its own errors and in per-record partial failures.
    private static func cloudKitErrorCodes(in error: Error) -> [CKError.Code] {
        var codes: [CKError.Code] = []
        var pending: [Error] = [error]

        while let next = pending.popLast() {
            if let cloudKitError = next as? CKError {
                codes.append(cloudKitError.code)

                if let partialErrors = cloudKitError.partialErrorsByItemID {
                    pending.append(contentsOf: partialErrors.values)
                }
            }

            if let underlying = (next as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                pending.append(underlying)
            }
        }

        return codes
    }
}

// Recurring transactions may only be generated from data that is current with iCloud. Otherwise a device
// that was offline or in the background logs occurrences that another device has already logged.
struct RecurringGenerationGate {
    private(set) var isOpen: Bool
    private let isSyncEnabled: Bool
    private var isAccountUnavailable = false
    private var isOnline = true

    init(isSyncEnabled: Bool) {
        self.isSyncEnabled = isSyncEnabled
        isOpen = !isSyncEnabled
    }

    mutating func syncEventFinished(isImport: Bool, succeeded: Bool, isNetworkError: Bool) {
        if succeeded {
            if isImport {
                isOpen = true
            }
        } else if isNetworkError {
            needsFreshImport()
        } else {
            // Sync is failing for some other reason; waiting would stop recurring transactions indefinitely.
            isOpen = true
        }
    }

    mutating func accountBecameUnavailable() {
        isAccountUnavailable = true
        isOpen = true
    }

    mutating func needsFreshImport() {
        guard isSyncEnabled, !isAccountUnavailable else {
            return
        }

        isOpen = false
    }

    @discardableResult
    mutating func connectivityChanged(isOnline: Bool) -> Bool {
        guard isOnline != self.isOnline else {
            return false
        }

        self.isOnline = isOnline
        needsFreshImport()
        return true
    }

    // Offline, local data can't be checked against what other devices logged, so keep waiting.
    mutating func fallbackElapsed() {
        if isOnline {
            isOpen = true
        }
    }
}

class DataController: ObservableObject {
    static let shared = DataController()

    static let iCloudSyncEnabledKey = "iCloudSyncEnabled"
    static let lastBulkDeletionKey = "lastBulkDeletion"
    static let dataIsCurrentNotification = Notification.Name("DimeDataIsCurrentWithICloud")
    private static let cloudKitContainerIdentifier = "iCloud.com.rafaelsoh.dime"

    static var isICloudSyncPreferred: Bool {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.object(forKey: iCloudSyncEnabledKey) as? Bool ?? true
    }

    // 2.1.3 kept this setting in iCloud key-value storage and honoured it. Carry the user's choice over once.
    private static func migrateLegacyICloudSyncSetting() {
        guard let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime"),
              defaults.object(forKey: iCloudSyncEnabledKey) == nil,
              let legacyValue = NSUbiquitousKeyValueStore.default.object(forKey: "icloud_sync") as? Bool
        else {
            return
        }

        defaults.set(legacyValue, forKey: iCloudSyncEnabledKey)
    }

    var container = NSPersistentCloudKitContainer(name: "MainModel")

    let isCloudKitSyncEnabled: Bool
    let syncStatus: CloudSyncStatus

    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "DataController")

    // Main thread only.
    private var recurringGate: RecurringGenerationGate
    private var recurringFallback: DispatchWorkItem?
    private var pathMonitor: NWPathMonitor?

    init() {
        #if DEBUG
        // Unit tests run inside the app, and must never open the simulator's real store.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let demoDataset = DemoDataset(arguments: ProcessInfo.processInfo.arguments) ?? (isRunningTests ? .minimal : nil)
        let usesDemoData = demoDataset != nil
        #else
        let usesDemoData = false
        #endif

        let description = NSPersistentStoreDescription()

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // The widget and intents extensions open this same file through the app group. CloudKit mirroring
        // does not support several processes syncing one store, so only the app mirrors it and exports
        // whatever the extensions write from persistent history.
        let isAppExtension = Bundle.main.bundleURL.pathExtension == "appex"

        if !isAppExtension {
            Self.migrateLegacyICloudSyncSetting()
        }

        isCloudKitSyncEnabled = !isAppExtension && !usesDemoData && Self.isICloudSyncPreferred
        syncStatus = CloudSyncStatus(isEnabled: isCloudKitSyncEnabled, containerIdentifier: Self.cloudKitContainerIdentifier)
        recurringGate = RecurringGenerationGate(isSyncEnabled: isCloudKitSyncEnabled)

        if isCloudKitSyncEnabled {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
        } else {
            description.cloudKitContainerOptions = nil
        }

        let groupID = "group.com.rafaelsoh.dime"

        if usesDemoData {
            // An in-memory SQLite store, so demo data never touches the user's real store.
            description.url = URL(fileURLWithPath: "/dev/null")
        } else if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            description.url = url.appendingPathComponent("Main.sqlite")
        }

        container.persistentStoreDescriptions = [description]

        if !usesDemoData, let storeURL = description.url {
            do {
                if let snapshot = try StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: container.managedObjectModel, in: StoreSnapshot.directory(forStoreAt: storeURL)) {
                    logger.notice("Saved the store before migrating it to \(snapshot.path, privacy: .public)")
                }
            } catch {
                logger.error("Saving the store before migrating it failed: \(String(describing: error), privacy: .public)")
            }
        }

        container.loadPersistentStores { description, error in

            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo) for \(description)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // CloudKit imports and other processes write to the same rows this context holds. With the default
        // NSErrorMergePolicy the first overlapping change makes this and every later save fail.
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        observeExtensionWrites(isAppExtension: isAppExtension)

        if !isAppExtension && !usesDemoData {
            observeMainAccountName()
        }

        if isCloudKitSyncEnabled {
            observeCloudKitSync()
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema") {
            initializeCloudKitSchema()
        }

        if let demoDataset {
            seedDemoData(demoDataset)
        }
        #endif
    }

    #if DEBUG
    // Debug builds sync with the CloudKit development environment. New attributes must be pushed there
    // with this, then deployed to production in the CloudKit Dashboard before a release ships them.
    private func initializeCloudKitSchema() {
        guard isCloudKitSyncEnabled else {
            logger.error("Not initializing the CloudKit schema: iCloud sync is off or demo data is in use")
            return
        }

        logger.notice("Initializing the CloudKit schema")

        do {
            try container.initializeCloudKitSchema(options: [])
            logger.notice("Initialized the CloudKit schema")
        } catch {
            logger.error("Initializing the CloudKit schema failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    private func observeCloudKitSync() {
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil
            else {
                return
            }

            if let error = event.error {
                self.logger.error("CloudKit event \(event, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }

            if event.type == .import || event.type == .setup {
                let isNetworkError = event.error.map(CloudSyncStatus.isNetworkError) ?? false
                self.recurringGate.syncEventFinished(isImport: event.type == .import, succeeded: event.succeeded, isNetworkError: isNetworkError)

                if isNetworkError {
                    self.scheduleRecurringFallback()
                }

                self.updateRecurringTransactionsIfReady()
            }
        }

        CKContainer(identifier: Self.cloudKitContainerIdentifier).accountStatus { [weak self] status, _ in
            guard status != .available else {
                return
            }

            DispatchQueue.main.async {
                self?.recurringGate.accountBecameUnavailable()
                self?.updateRecurringTransactionsIfReady()
            }
        }

        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self, self.recurringGate.connectivityChanged(isOnline: path.status == .satisfied) else {
                    return
                }

                self.scheduleRecurringFallback()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.rafaelsoh.dime.network"))
        self.pathMonitor = pathMonitor

        scheduleRecurringFallback()
    }

    // MARK: Main account's name

    /// Main's name syncs through iCloud key-value storage, since Main has no object in the store.
    private func observeMainAccountName() {
        MainAccount.adoptNameFromICloud(clearingIfMissing: false)

        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

            guard changed.contains(MainAccount.nameKey) else {
                return
            }

            MainAccount.adoptNameFromICloud(clearingIfMissing: true)
            self?.objectWillChange.send()
            WidgetCenter.shared.reloadAllTimelines()
        }

        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: Writes from extensions

    /// Marks saves made by the widget extension, such as Quick Add, so the app can find them in persistent history.
    private static let extensionAuthor = "extension"
    private var extensionHistoryToken: NSPersistentHistoryToken?

    /// The app's view context only merges its own coordinator's saves by itself. Saves from the widget extension
    /// reach the same file through the app group, so the app reads them from persistent history instead.
    private func observeExtensionWrites(isAppExtension: Bool) {
        if isAppExtension {
            container.viewContext.transactionAuthor = Self.extensionAuthor
            return
        }

        extensionHistoryToken = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)

        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in
            self?.mergeExtensionWrites()
        }
    }

    private func mergeExtensionWrites() {
        guard extensionHistoryToken != nil else {
            return
        }

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: extensionHistoryToken)

        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(NSPersistentHistoryTransaction.author), Self.extensionAuthor)
            request.fetchRequest = fetchRequest
        }

        do {
            let result = try container.viewContext.execute(request) as? NSPersistentHistoryResult
            let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []

            for transaction in transactions {
                container.viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                extensionHistoryToken = transaction.token
            }
        } catch {
            logger.error("Reading changes from extensions failed: \(String(describing: error), privacy: .public)")
        }
    }

    func applicationWillEnterForeground() {
        mergeExtensionWrites()

        if isCloudKitSyncEnabled {
            recurringGate.needsFreshImport()
            scheduleRecurringFallback()
        }

        updateRecurringTransactionsIfReady()
    }

    // CloudKit sometimes reports a successful setup and then never imports.
    private func scheduleRecurringFallback() {
        recurringFallback?.cancel()

        let fallback = DispatchWorkItem { [weak self] in
            self?.recurringGate.fallbackElapsed()
            self?.updateRecurringTransactionsIfReady()
        }

        recurringFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: fallback)
    }

    // internal variables

    var tipCounter: Int {
        get {
            UserDefaults.standard.integer(forKey: "tipCounter")
        }

        set {
            UserDefaults.standard.set(newValue, forKey: "tipCounter")
        }
    }

    var addedTransaction: Bool {
        get {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.bool(forKey: "newTransactionAdded")
        }

        set {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(newValue, forKey: "newTransactionAdded")
        }
    }

    // adding or deleting

    func deleteAll() {
        let context = container.viewContext
        let fetchRequests: [NSFetchRequest<NSFetchRequestResult>] = [
            Transaction.fetchRequest(),
            TemplateTransaction.fetchRequest(),
            Budget.fetchRequest(),
            MainBudget.fetchRequest(),
            Category.fetchRequest(),
            Account.fetchRequest()
        ]

        for fetchRequest in fetchRequests {
            fetchRequest.includesPropertyValues = false
            let objects = (try? context.fetch(fetchRequest)) as? [NSManagedObject] ?? []
            objects.forEach(context.delete)
        }

        MainAccount.rename(to: "")
        save()
    }

    func save() {
        let context = container.viewContext

        guard context.hasChanges else {
            return
        }

        // Lets the backup check tell a deliberate bulk delete apart from data going missing.
        let deletedObjects = context.deletedObjects

        if deletedObjects.contains(where: { $0 is Category }) || deletedObjects.filter({ $0 is Transaction }).count >= 10 {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(Date.now, forKey: Self.lastBulkDeletionKey)
        }

        do {
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("Saving the view context failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes a transaction, and both legs when it's a transfer: one leg alone would show money
    /// leaving or arriving in an account with nothing on the other side.
    func deleteTransaction(_ transaction: Transaction) {
        guard transaction.managedObjectContext != nil else {
            return
        }

        if let counterpart = transaction.transferCounterpart {
            container.viewContext.delete(counterpart)
        }

        container.viewContext.delete(transaction)
        save()
    }

    @discardableResult
    func updateRecurringTransaction(transaction: Transaction) -> Bool {
        guard (1 ... 3).contains(transaction.recurringType) else {
            return false
        }

        let calendar = Calendar.current

        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date.now)) else {
            return false
        }

        var occurrenceDate = transaction.nextTransactionDate

        guard occurrenceDate < startOfTomorrow else {
            return false
        }

        while occurrenceDate < startOfTomorrow {
            guard let followingDate = transaction.recurrenceDate(after: occurrenceDate) else {
                break
            }

            insertOccurrence(of: transaction, on: occurrenceDate, carriesRecurrence: followingDate >= startOfTomorrow)
            occurrenceDate = followingDate
        }

        transaction.recurringType = 0

        save()

        return true
    }

    private func insertOccurrence(of transaction: Transaction, on date: Date, carriesRecurrence: Bool) {
        let occurrence = Transaction(context: container.viewContext)
        occurrence.note = transaction.wrappedNote
        occurrence.category = transaction.category
        occurrence.account = transaction.account
        occurrence.amount = transaction.wrappedAmount
        // A missing currency would follow later changes of the main currency, so new rows always name one.
        occurrence.currencyCode = transaction.currencyCode ?? currencyConverter.mainCurrency
        occurrence.date = date
        occurrence.id = UUID()
        occurrence.income = transaction.income
        occurrence.day = date

        let calendar = Calendar(identifier: .gregorian)

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        occurrence.month = calendar.date(from: dateComponents)

        occurrence.onceRecurring = true

        if carriesRecurrence {
            occurrence.recurringType = transaction.recurringType
            occurrence.recurringCoefficient = transaction.recurringCoefficient
        } else {
            occurrence.recurringType = 0
        }
    }

    func updateRecurringTransactions() {
        let calendar = Calendar.current

        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date.now)) else {
            return
        }

        var loggedIDs = Set<UUID>()

        for transaction in results(for: fetchRequestForRecurringTransactions()) {
            // Sync could duplicate a recurring transaction under the same id. Once one copy has logged an
            // occurrence, retire the other copies instead of letting each of them log it again.
            if let id = transaction.id, loggedIDs.contains(id) {
                if transaction.nextTransactionDate < startOfTomorrow {
                    transaction.recurringType = 0
                }

                continue
            }

            if updateRecurringTransaction(transaction: transaction), let id = transaction.id {
                loggedIDs.insert(id)
            }
        }

        save()
    }

    var isDataCurrentWithICloud: Bool {
        recurringGate.isOpen
    }

    func updateRecurringTransactionsIfReady() {
        guard recurringGate.isOpen else {
            return
        }

        updateRecurringTransactions()
        NotificationCenter.default.post(name: Self.dataIsCurrentNotification, object: self)
    }

    func updateBudgetDates() {
        let budgets = results(for: fetchRequestForBudgets())
        let mainBudget = results(for: fetchRequestForMainBudget())

        budgets.forEach { budget in
            while budget.endDate <= Date.now, budget.endDate > budget.wrappedDate {
                budget.startDate = budget.endDate
            }
        }

        mainBudget.forEach { budget in
            while budget.endDate <= Date.now, budget.endDate > budget.wrappedDate {
                budget.startDate = budget.endDate
            }
        }

        save()
    }

    func newTransaction(note: String, category: Category?, income: Bool, amount: Double, currencyCode: String? = nil, account: Account? = nil, date: Date, repeatType: Int, repeatCoefficient: Int, delay _: Bool) -> Transaction {
        let transaction = insertTransaction(note: note, category: category, income: income, amount: amount, currencyCode: currencyCode, account: account, date: date, repeatType: repeatType, repeatCoefficient: repeatCoefficient)

        save()

        return transaction
    }

    /// Inserts a transaction without saving, so imports can save many at once. No account means Main.
    func insertTransaction(note: String, category: Category?, income: Bool, amount: Double, currencyCode: String? = nil, account: Account? = nil, date: Date, repeatType: Int = 0, repeatCoefficient: Int = 1) -> Transaction {
        let transaction = Transaction(context: container.viewContext)

        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income
        transaction.category = category
        transaction.account = account

        transaction.amount = amount
        transaction.currencyCode = currencyCode ?? currencyForNewTransaction()
        transaction.date = date
        transaction.id = UUID()

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            updateRecurringTransaction(transaction: transaction)
        }

        return transaction
    }

    // MARK: Quick Add templates

    /// Templates in the order Settings and the widgets show them.
    func quickAddTemplates() -> [TemplateTransaction] {
        let request: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()
        // The widget extension holds on to its context, and the app edits templates from another process.
        request.shouldRefreshRefetchedObjects = true

        // Several devices can sync templates with the same order, so the id breaks ties the same way on each.
        return results(for: request).sorted {
            ($0.order, $0.id?.uuidString ?? "") < ($1.order, $1.id?.uuidString ?? "")
        }
    }

    /// The template a widget button names, read fresh from the store. Nil when it has since been deleted.
    func quickAddTemplate(withURI uri: URL) -> TemplateTransaction? {
        guard let objectID = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: uri) else {
            return nil
        }

        let request: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()
        request.predicate = NSPredicate(format: "self == %@", objectID)
        request.shouldRefreshRefetchedObjects = true
        request.fetchLimit = 1

        return results(for: request).first
    }

    var canAddQuickAddTemplate: Bool {
        quickAddTemplates().count < TemplateTransaction.quickAddLimit
    }

    var nextQuickAddOrder: Int16 {
        (quickAddTemplates().map(\.order).max() ?? -1) + 1
    }

    /// Adds a template with a transaction's details. They aren't linked: changing or deleting one never touches the other.
    @discardableResult
    func addQuickAddTemplate(from transaction: Transaction) -> TemplateTransaction? {
        guard canAddQuickAddTemplate else {
            return nil
        }

        // Worked out before inserting, or the new template counts itself.
        let order = nextQuickAddOrder
        let template = TemplateTransaction(context: container.viewContext)
        template.id = UUID()
        template.order = order
        template.note = transaction.note
        template.amount = transaction.amount
        template.income = transaction.income
        template.category = transaction.category
        template.currencyCode = transaction.currencyCode
        template.account = transaction.account

        save()

        return template
    }

    func deleteQuickAddTemplate(_ template: TemplateTransaction) {
        container.viewContext.delete(template)

        // Number the rest from 0 again, so new templates always go at the end.
        for (index, remaining) in quickAddTemplates().filter({ $0 != template }).enumerated() where remaining.order != Int16(index) {
            remaining.order = Int16(index)
        }

        save()
    }

    /// Moves templates the way `List.onMove` describes, then numbers them all from 0.
    func moveQuickAddTemplates(fromOffsets source: IndexSet, toOffset destination: Int) {
        var templates = quickAddTemplates()
        templates.move(fromOffsets: source, toOffset: destination)

        for (index, template) in templates.enumerated() where template.order != Int16(index) {
            template.order = Int16(index)
        }

        save()
    }

    /// Logs a transaction now with the template's details. It keeps no link to the template.
    @discardableResult
    func logQuickAddTemplate(_ template: TemplateTransaction) -> Transaction {
        newTransaction(note: template.wrappedNote, category: template.category, income: template.income, amount: template.amount, currencyCode: template.currencyCode ?? currencyConverter.mainCurrency, account: template.account, date: Date.now, repeatType: 0, repeatCoefficient: 1, delay: false)
    }

    // MARK: Accounts

    /// The user's accounts in their order. Main isn't one of them: it's every transaction without an account.
    func accounts() -> [Account] {
        let request: NSFetchRequest<Account> = Account.fetchRequest()

        // Several devices can sync accounts with the same order, so the key breaks ties the same way on each.
        return results(for: request).sorted {
            ($0.order, $0.key) < ($1.order, $1.key)
        }
    }

    /// Main first, then the user's accounts.
    func accountChoices() -> [AccountChoice] {
        [.main] + accounts().map(AccountChoice.account)
    }

    func accountCount() -> Int {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    enum AccountNameError {
        case none, missingName, duplicateName
    }

    func accountNameCheck(_ name: String, editing: AccountChoice? = nil) -> AccountNameError {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .missingName
        }

        let taken = accountChoices()
            .filter { $0 != editing }
            .contains { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }

        return taken ? .duplicateName : .none
    }

    @discardableResult
    func addAccount(named name: String) -> Account {
        // Worked out before inserting, or the new account counts itself.
        let order = (accounts().map(\.order).max() ?? -1) + 1

        let account = Account(context: container.viewContext)
        account.id = UUID()
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.dateCreated = Date.now
        account.order = order

        save()

        return account
    }

    func renameAccount(_ choice: AccountChoice, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch choice {
        case .main:
            MainAccount.rename(to: trimmed)
            objectWillChange.send()
            WidgetCenter.shared.reloadAllTimelines()
        case let .account(account):
            account.name = trimmed
            save()
        }
    }

    /// Deletes an account. Its transactions and Quick Add templates move to Main; nothing else is deleted.
    ///
    /// The model's delete rule would also leave them in Main, but they're moved here first so that no
    /// transaction ever depends on a delete rule to survive.
    func deleteAccount(_ account: Account) {
        for transaction in account.transactions as? Set<Transaction> ?? [] {
            transaction.account = nil
        }

        for template in account.templates as? Set<TemplateTransaction> ?? [] {
            template.account = nil
        }

        if AccountPreferences.lastUsed(among: accounts()) == .account(account) {
            AccountPreferences.record(.main)
        }

        container.viewContext.delete(account)
        save()
    }

    /// Moves accounts the way `List.onMove` describes, then numbers them all from 0. Main always stays first.
    /// `displayed` is the list the offsets refer to; it defaults to `accounts()`.
    func moveAccounts(_ displayed: [Account]? = nil, fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = displayed ?? accounts()
        ordered.move(fromOffsets: source, toOffset: destination)

        for (index, account) in ordered.enumerated() where account.order != Int64(index) {
            account.order = Int64(index)
        }

        save()
    }

    /// How many transactions an account has, transfers included.
    func transactionCount(in choice: AccountChoice) -> Int {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = choice.predicate
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    // MARK: Transfers

    /// Saves a transfer between two accounts as an outgoing and an incoming leg sharing a transfer id.
    ///
    /// With `editing`, that transaction becomes one of the legs: a transfer keeps its id, an ordinary transaction
    /// becomes the outgoing leg of a new transfer. A missing other leg is recreated, so a transfer that lost
    /// its other half ends up whole again.
    @discardableResult
    func saveTransfer(editing leg: Transaction? = nil, from: AccountChoice, to: AccountChoice, amount: Double, currencyCode: String, date: Date, note: String) -> (outgoing: Transaction, incoming: Transaction) {
        let context = container.viewContext
        let transferID = leg?.transferID ?? UUID()
        let counterpart = leg?.transferCounterpart

        let outgoing: Transaction
        let incoming: Transaction

        if let leg, leg.isTransfer, leg.income {
            incoming = leg
            outgoing = counterpart ?? Transaction(context: context)
        } else if let leg {
            outgoing = leg
            incoming = counterpart ?? Transaction(context: context)
        } else {
            outgoing = Transaction(context: context)
            incoming = Transaction(context: context)
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        for (transaction, isIncoming, account) in [(outgoing, false, from.account), (incoming, true, to.account)] {
            if transaction.id == nil {
                transaction.id = UUID()
            }

            transaction.transferID = transferID
            transaction.income = isIncoming
            transaction.account = account
            transaction.category = nil
            transaction.note = trimmedNote
            transaction.amount = amount
            transaction.currencyCode = currencyCode
            setDate(date, on: transaction)

            // Transfers don't repeat: the legs would each log their own occurrences.
            transaction.recurringType = 0
            transaction.recurringCoefficient = 1
            transaction.onceRecurring = false
        }

        save()

        return (outgoing, incoming)
    }

    /// Turns one leg of a transfer back into an ordinary transaction in its own account, deleting the other leg.
    func endTransfer(keeping leg: Transaction) {
        if let counterpart = leg.transferCounterpart {
            container.viewContext.delete(counterpart)
        }

        leg.transferID = nil
    }

    /// Sets a transaction's date and the day and month it's grouped under.
    func setDate(_ date: Date, on transaction: Transaction) {
        let calendar = Calendar(identifier: .gregorian)

        transaction.date = date
        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now
        transaction.month = calendar.date(from: calendar.dateComponents([.month, .year], from: date)) ?? Date.now
    }

    // fetching

    // Transfers never repeat, but a leg could reach here from an older backup or a bad sync; it must not log copies.
    func fetchRequestForRecurringTransactions() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = TransferPredicate.excluding(NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0))
        return itemRequest
    }

    /// Lists show each transfer once.
    func fetchRequestForRecentTransactions(type: TimePeriod) -> NSFetchRequest<Transaction> {
        let request = fetchRequestForRecentTransactionsIncludingTransfers(type: type)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [request.predicate, TransferPredicate.oneLegPerTransfer].compactMap { $0 })
        return request
    }

    private func fetchRequestForRecentTransactionsIncludingTransfers(type: TimePeriod) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextDay as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: thisWeek)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextWeek as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextMonth as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!
            let nextYear = calendar.date(byAdding: .year, value: 1, to: thisYear)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextYear as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        }
    }

    func fetchRequestForExport() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return itemRequest
    }

    func fetchRequestForCategoriesMigration(income: Bool? = nil) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]

        if let unwrappedIncome = income {
            itemRequest.predicate = NSPredicate(format: "income = %d", unwrappedIncome)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForCategories(income: Bool) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        itemRequest.predicate = NSPredicate(format: "income = %d", income)
        return itemRequest
    }

    func getAllCategories(income: Bool) -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        request.predicate = NSPredicate(format: "income = %d", income)

        return results(for: request)
    }

    func getSuggestedNotes(searchQuery: String, category: Category?, income: Bool) -> [Transaction] {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]

        let beginPredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [beginPredicate, containPredicate])

        let incomePredicate = NSPredicate(format: "income = %d", income)

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, categoryPredicate, incomePredicate, TransferPredicate.excluded])

            itemRequest.predicate = andPredicate
        } else {
            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, incomePredicate, TransferPredicate.excluded])
            itemRequest.predicate = andPredicate
        }

        let transactions = results(for: itemRequest)

        var seen = [Transaction]()
        let filtered = transactions.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
//
//        let notes = transactions.map { $0.wrappedNote }
//
//        return Array(Set(notes))
    }

    @available(iOS 16, *)
    func findCategory(withId id: UUID) throws -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundCategory = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundCategory
        } catch {
            throw CustomError.notFound
        }
    }

    func getAllBudgets() -> [Budget] {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]
        return results(for: request)
    }

    @available(iOS 16, *)
    func findBudget(withId id: UUID) throws -> Budget {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundBudget = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundBudget
        } catch {
            throw CustomError.notFound
        }
    }

    func categoryCheck(name: String, emoji: String, income: Bool) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if income {
            let fetchRequest = fetchRequestForCategories(income: true)
            let incomeCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            let expenseCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func categoryCheckEdit(name: String, emoji: String, toEdit: Category) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if toEdit.income {
            let fetchRequest = fetchRequestForCategories(income: true)
            var incomeCategories = results(for: fetchRequest)

            if let position = incomeCategories.firstIndex(of: toEdit) {
                incomeCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            var expenseCategories = results(for: fetchRequest)

            if let position = expenseCategories.firstIndex(of: toEdit) {
                expenseCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func fetchRequestForBudgets() -> NSFetchRequest<Budget> {
        let itemRequest: NSFetchRequest<Budget> = Budget.fetchRequest()

        return itemRequest
    }

    func fetchRequestForMainBudget() -> NSFetchRequest<MainBudget> {
        let itemRequest: NSFetchRequest<MainBudget> = MainBudget.fetchRequest()

        return itemRequest
    }

    /// Totals for the log and Shortcuts. Transfers are neither spending nor income.
    func fetchRequestForLogView(type: Int, optionalIncome: Bool?, categoryFilters: [Category] = []) -> NSFetchRequest<Transaction> {
        let request = fetchRequestForLogViewIncludingTransfers(type: type, optionalIncome: optionalIncome, categoryFilters: categoryFilters)
        request.predicate = TransferPredicate.excluding(request.predicate)
        return request
    }

    private func fetchRequestForLogViewIncludingTransfers(type: Int, optionalIncome: Bool?, categoryFilters: [Category] = []) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let dateCapPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        // all time
        if type == 5 {
            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        } else {
            let startPredicate: NSPredicate

            if type == 1 {
                let today = calendar.startOfDay(for: Date.now)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            } else if type == 2 {
                let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)
                let thisWeek = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            } else if type == 3 {
                let startOfMonth = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstDayOfMonth")

                let thisMonth = getStartOfMonth(startDay: startOfMonth)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            } else {
                let dateComponents = calendar.dateComponents([.year], from: Date.now)
                let thisYear = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            }

            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        }

    }

    var currencyConverter: CurrencyConverter {
        .current()
    }

    // In a shared store participants may have different main currencies, so a missing currency would be
    // ambiguous: every new transaction names its currency. Shortcuts, automations and imports nobody watches
    // use the main currency; only the entry screen, where the currency is on show, starts from the last used.
    func currencyForNewTransaction() -> String {
        currencyConverter.mainCurrency
    }

    func currencyForNewEntry() -> String {
        CurrencyPreferences.defaultCurrency(
            mainCurrency: currencyConverter.mainCurrency,
            recent: CurrencyPreferences.recentCurrencies(in: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
        )
    }

    /// Dates of transactions in a currency other than the main one, the only days rates are needed for.
    func foreignCurrencyDates() -> [Date] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "%K != nil AND NOT (%K ==[c] %@)", #keyPath(Transaction.currencyCode), #keyPath(Transaction.currencyCode), currencyConverter.mainCurrency)
        return results(for: request).compactMap(\.date)
    }

    /// For when the user picks a foreign currency, so its conversion can be previewed before anything is saved.
    func ensureLatestExchangeRates() {
        if ExchangeRateStore.shared.needsLatest(now: Date()) {
            refreshExchangeRates(force: true)
        }
    }

    // Only the app fetches rates; the widgets and intents read what it cached. Without foreign transactions
    // nothing is fetched unless `force` is set.
    func refreshExchangeRates(force: Bool = false) {
        let dates = foreignCurrencyDates()

        guard force || !dates.isEmpty else {
            return
        }

        Task {
            let result = await ExchangeRateStore.shared.refresh(dates: dates, force: force)

            if result.addedDays > 0 {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    func getShortcutInsights(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [Category]) -> Double {
        shortcutInsightsTotal(type: type, timeframe: timeframe, optionalIncome: optionalIncome, categories: categories).value
    }

    func shortcutInsightsTotal(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [Category]) -> MoneyTotal {
        let fetchRequest = fetchRequestForLogView(type: timeframe, optionalIncome: optionalIncome, categoryFilters: categories)
        let allTransactions = results(for: fetchRequest)

        return allTransactions.total(using: currencyConverter, signed: type == 1)
    }

    func getLogViewTotalSpent(type: Int) -> Double {
        logViewTotal(type: type, income: false).value
    }

    func getLogViewTotalIncome(type: Int) -> Double {
        logViewTotal(type: type, income: true).value
    }

    func logViewTotal(type: Int, income: Bool) -> MoneyTotal {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: income)
        let allTransactions = results(for: fetchRequest)

        return allTransactions.total(using: currencyConverter)
    }

    func getLogViewTotalNet(type: Int) -> (value: Double, positive: Bool) {
        let total = logViewNetTotal(type: type).value

        if total >= 0 {
            return (total, true)
        } else {
            return (abs(total), false)
        }
    }

    func logViewNetTotal(type: Int) -> MoneyTotal {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: nil)
        let allTransactions = results(for: fetchRequest)

        return allTransactions.total(using: currencyConverter, signed: true)
    }

    func getLineGraphDataNet(type: Int) -> [LineGraphDataPoint] {
        lineGraphNet(type: type).points
    }

    func lineGraphNet(type: Int) -> (points: [LineGraphDataPoint], report: ConversionReport) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: nil)
        let transactions = results(for: fetchRequest)
        let converter = currencyConverter
        var report = ConversionReport()

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                let amount = converter.amount(of: transaction.money, report: &report)

                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                let amount = converter.amount(of: transaction.money, report: &report)

                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                let amount = converter.amount(of: transaction.money, report: &report)

                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                } else {
                    let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += amount
                    } else {
                        totalForDay -= amount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        }

        return (holdingDataPoints, report)
    }

    func getLineGraphData(income: Bool, type: Int) -> [LineGraphDataPoint] {
        lineGraph(income: income, type: type).points
    }

    func lineGraph(income: Bool, type: Int) -> (points: [LineGraphDataPoint], report: ConversionReport) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: income)
        let transactions = results(for: fetchRequest)
        let converter = currencyConverter
        var report = ConversionReport()

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate > lastWeek {
                    let amount = converter.amount(of: transaction.money, report: &report)

                    if transaction.wrappedDate < changingDate {
                        totalForDay += amount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)
            totalForDay = 0

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > lastMonth {
                    let amount = converter.amount(of: transaction.money, report: &report)

                    if transaction.wrappedDate < changingDate {
                        totalForDay += amount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let thisMonthLastYear = calendar.date(byAdding: .year, value: -1, to: thisMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > thisMonthLastYear {
                    let amount = converter.amount(of: transaction.money, report: &report)

                    if transaction.wrappedDate < changingDate {
                        totalForDay += amount
                    } else {
                        let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                            let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        }

                        totalForDay += amount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        }

        return (holdingDataPoints, report)
    }

    func getBudgetLeftover(budget: Budget? = nil, overallBudget: MainBudget? = nil) -> Double {
        budgetLeftover(budget: budget, overallBudget: overallBudget).value
    }

    // Budgets are in the main currency; spending against them is converted to it.
    func budgetLeftover(budget: Budget? = nil, overallBudget: MainBudget? = nil) -> MoneyTotal {
        let itemRequest: NSFetchRequest<Transaction>
        let budgetAmount: Double

        if let unwrappedOverallBudget = overallBudget {
            itemRequest = fetchRequestForMainBudgetTransactions(budget: unwrappedOverallBudget)
            budgetAmount = unwrappedOverallBudget.amount
        } else if let unwrappedBudget = budget {
            itemRequest = fetchRequestForBudgetTransactions(budget: unwrappedBudget)
            budgetAmount = unwrappedBudget.amount
        } else {
            itemRequest = Transaction.fetchRequest()
            budgetAmount = 0
        }

        let transactions = results(for: itemRequest)

        var leftover = transactions.total(using: currencyConverter)
        leftover.value = budgetAmount - leftover.value

        let rolling: RolloverBudget? = overallBudget.map { $0 as RolloverBudget } ?? budget
        if let rolling, let carry = rolloverCarryIn(for: rolling, category: budget?.category, at: rolling.startDate ?? Date.now) {
            leftover.value += carry
        }

        return leftover
    }

    /// What rolls into the period starting at `start`, or nil when the budget doesn't roll over or the period starts before rollover did.
    func rolloverCarryIn(for budget: RolloverBudget, category: Category?, at start: Date) -> Double? {
        guard let rollover = BudgetRollover(budget), rollover.periods(until: start) != nil else { return nil }
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = BudgetRollover.spendingPredicate(rollover, before: start, category: category, accounts: budget.accountPredicate)
        let spent = results(for: request).total(using: currencyConverter).value
        return rollover.carryIn(at: start, spentSinceAnchor: spent)
    }

    func fetchRequestForMainBudgetTransactions(budget: MainBudget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), budget.startDate! as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let predicates = [startPredicate, endPredicate, incomePredicate, TransferPredicate.excluded] + [budget.accountPredicate].compactMap { $0 }

        itemRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return itemRequest
    }

    func fetchRequestForBudgetTransactions(budget: Budget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), budget.startDate! as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), budget.category!)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let predicates = [startPredicate, endPredicate, categoryPredicate, incomePredicate, TransferPredicate.excluded] + [budget.accountPredicate].compactMap { $0 }

        itemRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return itemRequest
    }

    /// Transfers are neither spending nor income.
    func fetchRequestForLineGraph(optionalIncome: Bool?) -> NSFetchRequest<Transaction> {
        let request = fetchRequestForLineGraphIncludingTransfers(optionalIncome: optionalIncome)
        request.predicate = TransferPredicate.excluding(request.predicate)
        return request
    }

    private func fetchRequestForLineGraphIncludingTransfers(optionalIncome: Bool?) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]

        if let income = optionalIncome {
            itemRequest.predicate = NSPredicate(format: "income = %d", income)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForLogViewCategoryFilter(income: Bool) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = TransferPredicate.excluding(NSPredicate(format: "income = %d", income))
        return itemRequest
    }

    func getInsights(type: Int, date: Date, income: Bool, accounts: NSPredicate? = nil) -> (amount: Double, maximum: Double, average: Double, numberOfDays: Int, dates: [Date], dateDictionary: [Date: Double], report: ConversionReport) {
        let currentItemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date, income: income, accounts: accounts)
        let currentTransactions = results(for: currentItemRequest)
        let converter = currencyConverter
        var report = ConversionReport()

        var iterativeDate = date

        if type == 1 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            // calendar initialization
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
            calendar.minimumDaysInFirstWeek = 4

            var dictionary = [Date: Double]()
            var totalForWeek = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var weekAverage = 0.0

            for _ in 1 ... 7 {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForWeek += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let currentWeek = calendar.date(from: dateComponents)!

            if currentWeek == date {
//                let fromDate = Calendar.current.startOfDay(for: currentWeek)
//                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numberOfDays = Calendar.current.dateComponents([.day], from: currentWeek, to: Date.now)

                weekAverage = totalForWeek / Double((numberOfDays.day! + 1))
            } else {
                weekAverage = totalForWeek / 7
            }

            return (totalForWeek, maximum, weekAverage, numberOfDays, dates, dictionary, report)
        } else if type == 2 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)
            let range = calendar.range(of: .day, in: .month, for: iterativeDate)!

            var dictionary = [Date: Double]()
            var totalForMonth = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... range.count {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForMonth += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                monthAverage = totalForMonth / Double((numDays.day! + 1))
            } else {
                monthAverage = totalForMonth / Double(range.count)
            }

            return (totalForMonth, maximum, monthAverage, numberOfDays, dates, dictionary, report)
        } else if type == 3 {
            // trackin dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)

            var dictionary = [Date: Double]()
            var totalForYear = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... 12 {
                nextDate = calendar.date(byAdding: .month, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                let holdingTotal = holding.total(using: converter)
                let total = holdingTotal.value
                report.merge(holdingTotal.report)

                totalForYear += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let currentYear = calendar.date(from: dateComponents)!

            if currentYear == date {
                let fromDate = Calendar.current.startOfDay(for: currentYear)
                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numDays = Calendar.current.dateComponents([.month], from: fromDate, to: toDate)

                monthAverage = totalForYear / Double((numDays.month! + 1))
            } else {
                monthAverage = totalForYear / 12
            }

            return (totalForYear, maximum, monthAverage, numberOfDays, dates, dictionary, report)
        } else {
            return (0, 0, 0, 0, [Date](), [Date: Double](), report)
        }
    }

    /// Transfers are neither spending nor income. `accounts` limits it to some accounts.
    func fetchRequestForInsights(type: Int, date: Date, income: Bool? = nil, accounts: NSPredicate? = nil) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)

        let endPredicate: NSPredicate

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

//            let endOfPeriod = calendar.date(byAdding: .day, value: -1, to: next) ?? Date.now
//
            if next > Date.now {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
//
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
//            } else {
//
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate: NSCompoundPredicate

        if let unwrappedIncome = income {
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedIncome)

            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, endPredicate, TransferPredicate.excluded] + [accounts].compactMap { $0 })
        } else {
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, TransferPredicate.excluded] + [accounts].compactMap { $0 })
        }

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func getInsightsSummary(type: Int, date: Date) -> (spent: Double, income: Double, net: Double, positive: Bool, average: Double) {
        let itemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date)
        let currentTransactions = results(for: itemRequest)
        let converter = currencyConverter

        let holdingSpent = currentTransactions.filter { !$0.income }.total(using: converter).value
        let holdingIncome = currentTransactions.filter(\.income).total(using: converter).value

        let net = holdingIncome - holdingSpent
        let absoluteNet: Double
        let positive: Bool

        if net < 0 {
            absoluteNet = abs(net)
            positive = false
        } else {
            absoluteNet = net
            positive = true
        }

        let calendar = Calendar.current

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numberOfDays.day! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 7)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            } else {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: next)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            }
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
//            } else {
//
//                let range = calendar.range(of: .day, in: .month, for: date)!
//                let numDays = range.count
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays))
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                let numDays = Calendar.current.dateComponents([.month], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.month! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 12)
            }
        }
    }

    func fetchRequestForWidgetInsights(type: InsightsTimePeriod, income: Bool) -> (fetchRequest: NSFetchRequest<Transaction>, date: Date) {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let incomePredicate = NSPredicate(format: "income = %d", income)

        let startDate: Date
        let startPredicate: NSPredicate

        switch type {
        case .unknown:
            startDate = Date.now
            startPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .month:
            let startOfMonth = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstDayOfMonth")

            startDate = getStartOfMonth(startDay: startOfMonth)

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        }

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate, TransferPredicate.excluded])

        itemRequest.predicate = andPredicate
        itemRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
        ]

        return (itemRequest, startDate)
    }

    /// Lists show each transfer once.
    func fetchRequestForRecentTransactionsWithCount(type: TimePeriod, count: Int) -> NSFetchRequest<Transaction> {
        let request = fetchRequestForRecentTransactionsWithCountIncludingTransfers(type: type, count: count)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [request.predicate, TransferPredicate.oneLegPerTransfer].compactMap { $0 })
        return request
    }

    private func fetchRequestForRecentTransactionsWithCountIncludingTransfers(type: TimePeriod, count: Int) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        }
    }

    func fetchRequestForMainBudgetWidget() -> (found: Bool, totalSpent: Double, budgetAmount: Double, percentage: Double, type: Int, startDate: Date) {
        let holding = results(for: fetchRequestForMainBudget())

        if let budget = holding.first {
            let itemRequest = fetchRequestForMainBudgetTransactions(budget: budget)
//
            let transactions = results(for: itemRequest)

            let holdingTotal = transactions.total(using: currencyConverter).value

            let percentageOfDays: Double

            let calendar = Calendar.current

            if budget.type == 1 {
                let components = calendar.dateComponents([.minute], from: budget.startDate!, to: Date.now)
                percentageOfDays = Double(components.minute!) / 1440
            } else {
                let components1 = calendar.dateComponents([.day], from: budget.startDate!, to: budget.endDate)
                let numberOfDays = components1.day!

                let components2 = calendar.dateComponents([.day], from: budget.startDate!, to: Date.now)
                let numberOfDaysPast = components2.day!

                percentageOfDays = Double(numberOfDaysPast) / Double(numberOfDays)
            }

            return (true, holdingTotal, budget.amount, percentageOfDays, Int(budget.type), budget.startDate!)

        } else {
            return (false, 0, 0, 0, 0, Date.now)
        }
    }

    func transactionCount() -> Int {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    func results<T: NSManagedObject>(for fetchRequest: NSFetchRequest<T>) -> [T] {
        return (try? container.viewContext.fetch(fetchRequest)) ?? []
    }
}

struct LineGraphDataPoint: Equatable {
    let date: Date
    let amount: Double

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        return dateFormatter.string(from: date)
    }

    var monthString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "MMM yy"

        return dateFormatter.string(from: date)
    }

    var amountString: String {
        if abs(amount) < 1000 {
            return String(format: "%.2f", amount)
        } else {
            return String(format: "%.0f", amount)
        }
    }
}

func getStartOfMonth(startDay: Int) -> Date {
    let calendar = Calendar.current

    guard startDay > 0 && startDay <= calendar.maximumRange(of: .day)!.upperBound else {
        let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
        return calendar.date(from: dateComponents) ?? Date.now
    }

    let today = calendar.startOfDay(for: Date.now)
    let currentDay = calendar.component(.day, from: today)

    var startComponents = DateComponents()
    startComponents.month = currentDay >= startDay ? 0 : -1

    startComponents.day = startDay - currentDay

    return calendar.date(byAdding: startComponents, to: today) ?? Date.now
}

func calculateStartOfMonthPeriod(earliestDate: Date, startOfMonthDay: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: earliestDate)
    components.day = startOfMonthDay

    let startOfMonth = Calendar.current.date(from: components) ?? Date.now
    return (earliestDate < startOfMonth) ? (Calendar.current.date(byAdding: .month, value: -1, to: startOfMonth) ?? Date.now) : startOfMonth
}

#if DEBUG
// Launch with `-demoData minimal` or `-demoData varied` to run against a seeded in-memory store.
enum DemoDataset: String {
    case minimal
    case varied

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-demoData"), index + 1 < arguments.count else {
            return nil
        }

        self.init(rawValue: arguments[index + 1])
    }
}

private struct DemoRandom {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        next() < probability
    }

    mutating func amount(_ range: ClosedRange<Double>) -> Double {
        ((range.lowerBound + (range.upperBound - range.lowerBound) * next()) * 20).rounded() / 20
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[min(items.count - 1, Int(next() * Double(items.count)))]
    }
}

extension DataController {
    func seedDemoData(_ dataset: DemoDataset) {
        let context = container.viewContext
        let calendar = Calendar.current
        let now = Date.now
        var order: Int64 = 0

        func category(_ name: String, _ emoji: String, _ colour: String, income: Bool = false) -> Category {
            let category = Category(context: context)
            category.id = UUID()
            category.name = name
            category.emoji = emoji
            category.colour = colour
            category.income = income
            category.order = order
            category.dateCreated = now
            order += 1
            return category
        }

        func add(_ note: String, _ category: Category, _ amount: Double, currencyCode: String? = nil, daysAgo: Int, hour: Int, minute: Int = 0) {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            if date > now {
                date = now.addingTimeInterval(-600)
            }

            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.note = note
            transaction.category = category
            transaction.income = category.income
            transaction.amount = amount
            transaction.currencyCode = currencyCode
            transaction.date = date
            transaction.day = calendar.startOfDay(for: date)
            transaction.month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        }

        switch dataset {
        case .minimal:
            let food = category("Food", "🍜", "#EC7A58")
            _ = category("Transport", "🚇", "#279AF4")
            _ = category("Salary", "💼", "#5FAF9F", income: true)
            add("Lunch with Sam", food, 14.5, daysAgo: 0, hour: 12, minute: 30)
            add("Ramen", food, 18.2, daysAgo: 1, hour: 19, minute: 45)
            add("Bakery", food, 6.8, daysAgo: 2, hour: 8, minute: 15)

        case .varied:
            let food = category("Food", "🍜", "#EC7A58")
            let groceries = category("Groceries", "🛒", "#5FAF9F")
            let transport = category("Transport", "🚇", "#279AF4")
            let coffee = category("Coffee", "☕", "#C38D5D")
            let shopping = category("Shopping", "🛍️", "#C56AF7")
            let fun = category("Entertainment", "🎬", "#ED80A2")
            let bills = category("Bills", "💡", "#F3BF56")
            let health = category("Health", "💊", "#E34D63")
            let salary = category("Salary", "💼", "#5FAF9F", income: true)
            let freelance = category("Freelance", "🎨", "#61C7FA", income: true)

            var random = DemoRandom(state: 42)

            for daysAgo in (0 ... 110).reversed() {
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                let weekday = calendar.component(.weekday, from: day)
                let weekend = weekday == 1 || weekday == 7
                let dayOfMonth = calendar.component(.day, from: day)
                // Some weeks are busier than others so the charts have shape.
                let busy = (daysAgo / 7) % 3 == 0 ? 1.5 : 1.0

                if !weekend && random.chance(0.32) {
                    add(random.pick(["Blue Bottle", "Flat white", "Oat latte", "Cold brew"]), coffee, random.amount(4.5 ... 6.8), daysAgo: daysAgo, hour: 8, minute: 20)
                }
                if random.chance(0.34 * busy) {
                    let dinner = weekend || random.chance(0.4)
                    add(random.pick(dinner ? ["Dinner – Ramen", "Thai with Mia", "Pizza night", "Sushi"] : ["Lunch", "Lunch with Sam", "Poke bowl", "Sandwich"]), food, random.amount(dinner ? 22 ... 64 : 9 ... 19), daysAgo: daysAgo, hour: dinner ? 19 : 12, minute: 40)
                }
                if (weekday == 1 || weekday == 4) && random.chance(0.7) {
                    add(random.pick(["Whole Foods", "Trader Joe's", "Costco", "Farmers market"]), groceries, random.amount(28 ... 135), daysAgo: daysAgo, hour: 17, minute: 10)
                }
                if random.chance(0.22 * busy) {
                    add(random.pick(["Uber", "Metro card", "Lyft", "Parking"]), transport, random.amount(3 ... 26), daysAgo: daysAgo, hour: 9, minute: 5)
                }
                if random.chance(0.05 * busy) {
                    add(random.pick(["New sneakers", "Uniqlo", "Amazon", "Desk lamp"]), shopping, random.amount(24 ... 160), daysAgo: daysAgo, hour: 15)
                }
                if weekend && random.chance(0.25) {
                    add(random.pick(["Cinema", "Concert tickets", "Bowling", "Museum"]), fun, random.amount(14 ... 72), daysAgo: daysAgo, hour: 20)
                }
                if random.chance(0.025) {
                    add(random.pick(["Pharmacy", "Dentist", "Vitamins"]), health, random.amount(12 ... 95), daysAgo: daysAgo, hour: 11)
                }
                if dayOfMonth == 3 {
                    add("Electricity", bills, random.amount(68 ... 128), daysAgo: daysAgo, hour: 10)
                }
                if dayOfMonth == 12 {
                    add("Phone plan", bills, 45, daysAgo: daysAgo, hour: 10)
                }
                if dayOfMonth == 1 {
                    add("Salary", salary, 4200, daysAgo: daysAgo, hour: 9)
                }
                if daysAgo == 40 || daysAgo == 9 {
                    add("Logo design", freelance, daysAgo == 40 ? 650 : 380, daysAgo: daysAgo, hour: 16)
                }
            }

            let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let streaming = Transaction(context: context)
            streaming.id = UUID()
            streaming.note = "Netflix"
            streaming.category = fun
            streaming.amount = 15.49
            streaming.date = calendar.date(byAdding: .month, value: -3, to: calendar.date(byAdding: .day, value: 6, to: firstOfMonth) ?? now)
            streaming.day = calendar.startOfDay(for: streaming.wrappedDate)
            streaming.month = calendar.date(from: calendar.dateComponents([.year, .month], from: streaming.wrappedDate))
            streaming.onceRecurring = true
            streaming.recurringType = 3
            streaming.recurringCoefficient = 1
            updateRecurringTransaction(transaction: streaming)

            seedDemoAccounts(groceries: groceries, shopping: shopping, coffee: coffee, firstOfMonth: firstOfMonth)
            seedDemoBudgets(food: food, groceries: groceries, coffee: coffee, shopping: shopping, health: health)
        }

        save()
    }

    /// Groceries and shopping go on a card and coffee is paid in cash; the rest stays in Main. Savings is fed
    /// by a transfer on the 2nd of each month, and cash was topped up this morning, so the log shows a transfer.
    /// Transfers aren't spending, so the budgets below come out the same.
    private func seedDemoAccounts(groceries: Category, shopping: Category, coffee: Category, firstOfMonth: Date) {
        let context = container.viewContext
        let calendar = Calendar.current
        let now = Date.now

        func account(_ name: String, order: Int64) -> Account {
            let account = Account(context: context)
            account.id = UUID()
            account.name = name
            account.order = order
            account.dateCreated = now
            return account
        }

        let card = account("Card", order: 0)
        let cash = account("Cash", order: 1)
        let savings = account("Savings", order: 2)

        // Earlier seeding saved along the way, so the transactions are fetched rather than taken from the inserted objects.
        for transaction in results(for: Transaction.fetchRequest() as NSFetchRequest<Transaction>) {
            if transaction.category == groceries || transaction.category == shopping {
                transaction.account = card
            } else if transaction.category == coffee {
                transaction.account = cash
            }
        }

        let currencyCode = currencyConverter.mainCurrency

        for monthsAgo in 0 ... 3 {
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: firstOfMonth) ?? firstOfMonth
            guard let second = calendar.date(byAdding: .day, value: 1, to: month),
                  let date = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: second),
                  date < now
            else { continue }

            saveTransfer(from: .main, to: .account(savings), amount: 500, currencyCode: currencyCode, date: date, note: "")
        }

        let morning = min(calendar.date(bySettingHour: 8, minute: 5, second: 0, of: now) ?? now, now.addingTimeInterval(-300))
        saveTransfer(from: .main, to: .account(cash), amount: 100, currencyCode: currencyCode, date: morning, note: "ATM")

        // `-insightsAccount <name>` starts Insights on one account and `-insightsAccount all` on every account.
        // Set here, before any view reads it.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-insightsAccount"), index + 1 < arguments.count {
            let key = [card, cash, savings].first { $0.wrappedName == arguments[index + 1] }?.key ?? ""
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(key, forKey: "insightsAccount")
        }
    }

    /// Budgets sized from the seeded spending so each lands in a known state: overall and Food on track,
    /// Groceries close to its limit, a weekly Coffee budget over, a yearly Shopping budget and an untouched Health budget.
    /// `-demoBudgets none` seeds no budgets; `-demoBudgets over` puts the overall budget over.
    /// Overall and Food roll over from earlier months, and Coffee carries a small overspend from last week.
    private func seedDemoBudgets(food: Category, groceries: Category, coffee: Category, shopping: Category, health: Category) {
        let arguments = ProcessInfo.processInfo.arguments
        let mode = arguments.firstIndex(of: "-demoBudgets").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        guard mode != "none" else { return }

        let context = container.viewContext
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let year = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
        var sundayCalendar = Calendar(identifier: .gregorian)
        sundayCalendar.firstWeekday = 1
        let week = sundayCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        func spent(_ category: Category?, since start: Date) -> Double {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            var predicates = [NSPredicate(format: "date >= %@ AND date <= %@ AND income = NO", start as CVarArg, now as CVarArg)]
            if let category {
                predicates.append(NSPredicate(format: "category == %@", category))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return ((try? context.fetch(request)) ?? []).total(using: currencyConverter).value
        }

        func elapsed(since start: Date, component: Calendar.Component, value: Int) -> Double {
            let end = calendar.date(byAdding: component, value: value, to: start) ?? now
            return max(0.1, now.timeIntervalSince(start) / end.timeIntervalSince(start))
        }

        func rounded(_ value: Double) -> Double {
            max(10, (value / 10).rounded(.up) * 10)
        }

        let monthElapsed = elapsed(since: month, component: .month, value: 1)

        let overall = MainBudget(context: context)
        overall.startDate = month
        overall.type = 3
        overall.amount = mode == "over" ? rounded(spent(nil, since: month) * 0.85) : rounded(spent(nil, since: month) / monthElapsed * 1.12)
        overall.rolloverEnabled = true
        overall.rolloverAnchor = calendar.date(byAdding: .month, value: -1, to: month)
        overall.rolloverBalance = 0

        @discardableResult
        func budget(_ category: Category, type: Int16, start: Date, amount: Double, order: Int) -> Budget {
            let budget = Budget(context: context)
            budget.id = UUID()
            budget.category = category
            budget.type = type
            budget.startDate = start
            budget.amount = amount
            budget.dateCreated = now.addingTimeInterval(Double(order))
            return budget
        }

        let foodBudget = budget(food, type: 3, start: month, amount: rounded(spent(food, since: month) / monthElapsed * 1.2), order: 0)
        budget(groceries, type: 3, start: month, amount: rounded(spent(groceries, since: month) / 0.92), order: 1)
        foodBudget.rolloverEnabled = true
        foodBudget.rolloverAnchor = calendar.date(byAdding: .month, value: -2, to: month)
        let coffeeBudget = budget(coffee, type: 2, start: week, amount: max(5, (spent(coffee, since: week) * 0.75).rounded()), order: 2)
        coffeeBudget.rolloverEnabled = true
        coffeeBudget.rolloverAnchor = week
        coffeeBudget.rolloverBalance = -6
        budget(shopping, type: 4, start: year, amount: rounded(spent(shopping, since: year) / elapsed(since: year, component: .year, value: 1) * 1.3), order: 3)
        if spent(health, since: month) == 0 {
            budget(health, type: 3, start: month, amount: 60, order: 4)
        }
    }
}
#endif
