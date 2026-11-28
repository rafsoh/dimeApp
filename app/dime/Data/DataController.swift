//
//  DataController.swift
//  Bonsai
//
//  Created by Rafael Soh on 3/6/22.
//

import CloudKit
import Combine
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
         storeUnavailable,
         unknownId(id: String),
         unknownError(message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unknownError(message): return "An unknown error occurred: \(message)"
        case let .unknownId(id): return "No category with an ID matching: \(id)"
        case .notFound: return "Category not found"
        case .coreDataSave: return "Dime couldn't save your changes"
        case .storeUnavailable: return "Dime couldn't open your data. Open Dime and try again."
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

    /// The person wants sync. It can still be paused for this launch, see `isMirroring`.
    let isEnabled: Bool
    /// Whether the store is mirrored to CloudKit this launch. Off while iCloud last reported no usable account.
    let isMirroring: Bool

    @Published private(set) var lastSynced: Date?
    @Published private var accountStatus: CKAccountStatus?
    @Published private var problems: [NSPersistentCloudKitContainer.EventType: Problem] = [:]
    @Published private var eventsInProgress: [UUID: NSPersistentCloudKitContainer.EventType] = [:]

    private static let lastSyncedKey = "lastICloudSync"
    private let containerIdentifier: String
    private var observers: [NSObjectProtocol] = []

    init(isEnabled: Bool, isMirroring: Bool, containerIdentifier: String) {
        self.isEnabled = isEnabled
        self.isMirroring = isMirroring
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
            DataIntegrityLog.breadcrumb("iCloud account changed")
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

        // The account became usable after launch; mirroring starts the next time Dime opens.
        guard isMirroring else {
            return .waiting
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
        CKContainer(identifier: containerIdentifier).accountStatus { [weak self] status, error in
            // Read at the next launch to decide whether to mirror. An error leaves the last answer in place.
            if error == nil {
                UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(status.rawValue, forKey: DataController.lastICloudAccountStatusKey)
            }

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
    static let didEraseAllDataKey = "didEraseAllData"
    static let dataIsCurrentNotification = Notification.Name("DimeDataIsCurrentWithICloud")
    static let lastICloudAccountStatusKey = "lastICloudAccountStatus"
    /// Transactions the person deleted on this device since the newest backup was written.
    static let deletedSinceBackupKey = "integrity.transactionsDeletedSinceBackup"
    private static let transactionsAtLastLoadKey = "integrity.transactionsAtLastLoad"
    private static let deletedSinceLastLoadKey = "integrity.transactionsDeletedSinceLastLoad"

    /// iCloud said there's no account, or a restricted one, the last time it was asked.
    static var lastKnownICloudAccountIsUnavailable: Bool {
        guard let raw = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.object(forKey: lastICloudAccountStatusKey) as? Int,
              let status = CKAccountStatus(rawValue: raw)
        else {
            return false
        }

        return status == .noAccount || status == .restricted
    }
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
        DataIntegrityLog.breadcrumb(
            "legacy iCloud sync setting carried over",
            flags: ["enabled": legacyValue]
        )
    }

    var container = NSPersistentCloudKitContainer(name: "MainModel")

    let isCloudKitSyncEnabled: Bool
    let syncStatus: CloudSyncStatus

    /// Why the store couldn't be opened, shown instead of the app until a retry succeeds. Nil once it's loaded.
    @Published private(set) var storeLoadFailure: StoreLoadFailure?

    struct StoreLoadFailure: Equatable {
        let domain: String
        let code: Int
        var isOutOfSpace = false
    }

    /// A save that failed, shown once until a save succeeds or the app comes back to the foreground. The
    /// changes stay in the view context and are saved again then; telling people matters because they're
    /// lost if the app is closed first.
    @Published private(set) var saveFailure: SaveFailure?

    struct SaveFailure: Identifiable, Equatable {
        let id = UUID()
        let isOutOfSpace: Bool
    }

    private var isSaveFailureAcknowledged = false
    /// Domain and code of save failures already sent this launch; a full disk fails every save after it.
    private var reportedSaveFailures: Set<String> = []

    var isStoreLoaded: Bool {
        !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    private var isAppExtension = false
    private var reportsIntegrity = false
    private var migrationNeededAtLaunch = false
    private var countsBeforeMigration: [String: Int]?

    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "DataController")

    /// Feature Lab: new transactions without a category wait here for Apple Intelligence to pick one.
    var autoCategoryQueue = AutoCategoryQueue()

    // Main thread only.
    private var recurringGate: RecurringGenerationGate
    private var transactionCountAtCloudKitEventStart: [UUID: Int] = [:]
    private var cloudKitEventsInProgress: Set<UUID> = []
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

        // The widget and intents extensions open this same file through the app group. CloudKit mirroring
        // does not support several processes syncing one store, so only the app mirrors it and exports
        // whatever the extensions write from persistent history.
        let isAppExtension = Bundle.main.bundleURL.pathExtension == "appex"
        self.isAppExtension = isAppExtension

        let description = NSPersistentStoreDescription()

        // Only the app migrates the store. After an update the widget is often started at the same moment as
        // the app, and two processes migrating one file make one of them fail (NSMigrationError 134110). A
        // widget can also be stopped by its memory limit partway through. Until the app has migrated the
        // file, an extension simply doesn't open it.
        description.shouldMigrateStoreAutomatically = !isAppExtension
        description.shouldInferMappingModelAutomatically = !isAppExtension
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if !isAppExtension {
            Self.migrateLegacyICloudSyncSetting()
        }

        // With no iCloud account (or a restricted one), mirroring fails its setup (NSCocoaErrorDomain 134405), and
        // right after that the store read as empty (DIME-IOS-E); CloudKit also clears a mirrored store's records
        // when the account goes away. So while iCloud last reported no usable account, the store opens on its own.
        // The preference is untouched, and the next launch after an account appears mirrors again.
        let syncPreferred = !isAppExtension && !usesDemoData && Self.isICloudSyncPreferred
        let accountUnavailable = syncPreferred && Self.lastKnownICloudAccountIsUnavailable
        isCloudKitSyncEnabled = syncPreferred && !accountUnavailable
        syncStatus = CloudSyncStatus(isEnabled: syncPreferred, isMirroring: isCloudKitSyncEnabled, containerIdentifier: Self.cloudKitContainerIdentifier)
        recurringGate = RecurringGenerationGate(isSyncEnabled: isCloudKitSyncEnabled)

        if accountUnavailable {
            DataIntegrityLog.breadcrumb("iCloud sync paused: no iCloud account at the last check", persist: true)
        }

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

        let storeURL = description.url
        let migrationNeeded = !usesDemoData && !isAppExtension && storeURL.map {
            StoreSnapshot.needsMigration(storeAt: $0, to: container.managedObjectModel)
        } ?? false
        var countsBeforeMigration: [String: Int]?

        if migrationNeeded, let storeURL {
            // The earlier model versions and their coordinators are released before any view runs.
            autoreleasepool {
                countsBeforeMigration = prepareForMigration(storeAt: storeURL)
            }
        }

        reportsIntegrity = !usesDemoData
        migrationNeededAtLaunch = migrationNeeded
        self.countsBeforeMigration = countsBeforeMigration

        var firstError = loadStore()

        if firstError != nil, !isAppExtension {
            // Another process holding the file, or finishing what it was doing with it, often lets go within
            // a moment. One more attempt is cheaper than a launch that shows nothing.
            Thread.sleep(forTimeInterval: 1)

            if let secondError = loadStore() {
                firstError = secondError
            } else if let recovered = firstError {
                DataIntegrityLog.capture(
                    recovered,
                    message: "Persistent store loaded on the second attempt",
                    flags: ["migrationNeeded": migrationNeeded, "cloudKit": isCloudKitSyncEnabled]
                )
                firstError = nil
            }
        }

        if let firstError {
            storeFailedToLoad(firstError)
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

    // MARK: Loading the store

    /// Counts the records and keeps a copy of the file before Core Data migrates it. Returns the counts.
    private func prepareForMigration(storeAt storeURL: URL) -> [String: Int]? {
        var countsBeforeMigration: [String: Int]?
        // Loaded once for both uses. They claim no app classes either way (see StoreSnapshot.modelVersions).
        let versions = StoreSnapshot.modelVersions()
        let sourceModel = StoreSnapshot.sourceModel(forStoreAt: storeURL, among: versions)

        if let sourceModel {
            countsBeforeMigration = StoreSnapshot.recordCounts(storeAt: storeURL, model: sourceModel)
        }

        var startingNumbers = countsBeforeMigration ?? [:]
        let facts = Self.storeFileFacts(storeURL)
        startingNumbers["fileBytes"] = facts.bytes
        startingNumbers["walBytes"] = facts.walBytes
        DataIntegrityLog.breadcrumb(
            "migration starting",
            numbers: startingNumbers,
            flags: [
                "sourceModelFound": sourceModel != nil,
                "counted": countsBeforeMigration != nil,
                "cloudKit": isCloudKitSyncEnabled
            ],
            persist: true
        )

        do {
            let snapshotDirectory = StoreSnapshot.directory(forStoreAt: storeURL)
            let copiedBySQLite: (Error) -> Void = { error in
                let nsError = error as NSError
                DataIntegrityLog.breadcrumb(
                    "pre-migration snapshot made by SQLite after Core Data refused",
                    numbers: ["coreDataCode": nsError.code],
                    flags: ["cloudKit": self.isCloudKitSyncEnabled],
                    persist: true
                )
            }

            if let snapshot = try StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: container.managedObjectModel, sourceModels: versions, in: snapshotDirectory, copiedBySQLite: copiedBySQLite) {
                logger.notice("Saved the store before migrating it")
                let bytes = (try? snapshot.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                DataIntegrityLog.breadcrumb(
                    "pre-migration snapshot saved",
                    numbers: ["bytes": bytes],
                    flags: ["cloudKit": isCloudKitSyncEnabled],
                    persist: true
                )
            }
        } catch StoreSnapshot.SnapshotError.notEnoughSpace {
            logger.notice("Not saving the store before migrating it: too little free space")
            DataIntegrityLog.breadcrumb(
                "pre-migration snapshot skipped for lack of space",
                numbers: countsBeforeMigration ?? [:],
                flags: ["cloudKit": isCloudKitSyncEnabled],
                persist: true
            )
        } catch {
            let nsError = error as NSError
            logger.error("Saving the store before migrating it failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            DataIntegrityLog.capture(
                error,
                message: "Pre-migration snapshot failed",
                numbers: countsBeforeMigration ?? [:],
                flags: ["cloudKit": isCloudKitSyncEnabled, "outOfSpace": DataIntegrityLog.isOutOfSpace(error)]
            )
        }

        return countsBeforeMigration
    }

    /// Adds the store to the coordinator. Returns the error when it can't be opened; never crashes, because
    /// a crash on launch leaves people with no way to their data short of deleting the app.
    private func loadStore() -> NSError? {
        var loadError: NSError?
        let migrationNeeded = migrationNeededAtLaunch
        let countsBefore = self.countsBeforeMigration

        // With the default shouldAddStoreAsynchronously, the completion runs before this returns.
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                loadError = error
                return
            }

            guard self.reportsIntegrity else {
                return
            }

            // The completion is not guaranteed to be on the view context's queue.
            let loadedURL = description.url
            DispatchQueue.main.async {
                self.noteStoreLoaded(
                    storeURL: loadedURL,
                    migrationNeeded: migrationNeeded,
                    countsBeforeMigration: countsBefore
                )

                if migrationNeeded {
                    // Extensions don't open a store that still needs migrating, so widgets show nothing until now.
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }

        return loadError
    }

    private func storeFailedToLoad(_ error: NSError) {
        logger.error("Loading the persistent store failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        storeLoadFailure = StoreLoadFailure(domain: error.domain, code: error.code, isOutOfSpace: DataIntegrityLog.isOutOfSpace(error))

        guard reportsIntegrity else {
            return
        }

        let storeURL = container.persistentStoreDescriptions.first?.url

        // Expected in an extension until the app has migrated the file after an update.
        if isAppExtension, let storeURL, StoreSnapshot.needsMigration(storeAt: storeURL, to: container.managedObjectModel) {
            DataIntegrityLog.breadcrumb(
                "store waiting for the app to migrate it",
                flags: ["migrationNeeded": true]
            )
            return
        }

        var numbers = countsBeforeMigration ?? [:]
        let facts = Self.storeFileFacts(storeURL)
        numbers["fileBytes"] = facts.bytes
        numbers["walBytes"] = facts.walBytes
        numbers["snapshotCount"] = facts.snapshotCount
        DataIntegrityLog.capture(
            error,
            message: "Persistent store failed to load",
            numbers: numbers,
            flags: [
                "migrationNeeded": migrationNeededAtLaunch,
                "cloudKit": isCloudKitSyncEnabled,
                "fileExists": facts.exists,
                "outOfSpace": DataIntegrityLog.isOutOfSpace(error)
            ]
        )
    }

    /// For Shortcuts actions: tries once more to open the store, and throws if it still can't be opened, so an
    /// action doesn't report a total of zero or a transaction logged when nothing was read or saved.
    @available(iOS 16, *)
    func requireLoadedStore() throws {
        if !isStoreLoaded {
            retryLoadingStore()
        }

        guard isStoreLoaded else {
            throw CustomError.storeUnavailable
        }
    }

    /// Tries again to open a store that failed to load. Main thread only.
    func retryLoadingStore() {
        guard !isStoreLoaded else {
            storeLoadFailure = nil
            return
        }

        if let error = loadStore() {
            storeFailedToLoad(error)
            return
        }

        DataIntegrityLog.breadcrumb("store loaded after retrying", flags: ["migrationNeeded": migrationNeededAtLaunch], persist: true)
        extensionHistoryToken = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        storeLoadFailure = nil
        updateRecurringTransactionsIfReady()
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
                  let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            if event.endDate == nil {
                self.cloudKitEventStarted(event)
            } else {
                self.cloudKitEventFinished(event)
            }
        }

        CKContainer(identifier: Self.cloudKitContainerIdentifier).accountStatus { [weak self] status, error in
            DataIntegrityLog.breadcrumb(
                "iCloud account status",
                flags: ["error": error != nil],
                tokens: ["status": Self.accountStatusToken(status)]
            )

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

    // MARK: Main account's name and icon

    /// Main's name and icon sync through iCloud key-value storage, since Main has no object in the store.
    private func observeMainAccountName() {
        // Key-value storage answers through the system's sync daemon, and a read at launch can keep the main
        // thread waiting until the watchdog ends the app (DIME-IOS-W). It's read on a background queue and
        // what it holds is stored on the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let values = MainAccount.iCloudValues()
            NSUbiquitousKeyValueStore.default.synchronize()

            DispatchQueue.main.async {
                guard MainAccount.adopt(values, clearingIfMissing: false) else { return }
                self?.objectWillChange.send()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }

        // Delivered on the queue that posts it, so the read stays off the main thread too. Only the default
        // store posts this, so it isn't named here: naming it would create it on the main thread.
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: nil) { [weak self] notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

            guard changed.contains(MainAccount.nameKey) || changed.contains(MainAccount.symbolKey) else {
                return
            }

            let values = MainAccount.iCloudValues()

            DispatchQueue.main.async {
                MainAccount.adopt(values, clearingIfMissing: true)
                self?.objectWillChange.send()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: CloudKit events

    /// CloudKit errors that mean "no account yet" or "deferred, will retry". They're expected, so they stay
    /// breadcrumbs rather than events (DIME-IOS-2): NSCocoaErrorDomain 134400 and 134419.
    private static let expectedCloudKitErrorCodes: Set<Int> = [134_400, 134_419]

    // Counts run on a background context, and only around imports and setup, which are what can remove rows.
    // Exports follow every save, and counting on the main thread for each one waited on the store while
    // CloudKit held it (DIME-IOS-9).
    private static func countsTransactions(around event: NSPersistentCloudKitContainer.Event) -> Bool {
        event.type == .import || event.type == .setup
    }

    private func cloudKitEventStarted(_ event: NSPersistentCloudKitContainer.Event) {
        DataIntegrityLog.breadcrumb("CloudKit event started", tokens: ["type": Self.cloudKitEventToken(event.type)])

        guard Self.countsTransactions(around: event) else {
            return
        }

        let id = event.identifier
        cloudKitEventsInProgress.insert(id)

        countTransactionsInBackground { [weak self] count in
            guard let self, let count, self.cloudKitEventsInProgress.contains(id) else {
                return
            }

            self.transactionCountAtCloudKitEventStart[id] = count
        }
    }

    private func cloudKitEventFinished(_ event: NSPersistentCloudKitContainer.Event) {
        let type = Self.cloudKitEventToken(event.type)
        cloudKitEventsInProgress.remove(event.identifier)
        let transactionsBefore = transactionCountAtCloudKitEventStart.removeValue(forKey: event.identifier)

        var numbers: [String: Int] = [:]
        if let transactionsBefore {
            numbers["transactionsBefore"] = transactionsBefore
        }
        if let end = event.endDate {
            numbers["durationMs"] = Int(end.timeIntervalSince(event.startDate) * 1000)
        }

        if let error = event.error {
            let nsError = error as NSError
            let networkError = CloudSyncStatus.isNetworkError(error)
            let summary = DataIntegrityLog.failureSummary(for: error)
            let expected = nsError.domain == NSCocoaErrorDomain && Self.expectedCloudKitErrorCodes.contains(nsError.code)
            logger.error("CloudKit event failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            numbers["code"] = nsError.code

            // Partial failures carry the per-record codes that say what went wrong.
            var tokens = ["type": type, "domain": nsError.domain]
            let partialCodes = DataIntegrityLog.partialErrorCodes(in: error)
            if !partialCodes.isEmpty {
                tokens["partialCodes"] = partialCodes
            }

            let flags = ["network": networkError, "succeeded": false, "expected": expected, "storeLoaded": isStoreLoaded]
            DataIntegrityLog.breadcrumb("CloudKit event failed", numbers: numbers, flags: flags, tokens: tokens)

            if !networkError, !expected {
                DataIntegrityLog.captureOnce(
                    key: "ck.\(type).\(summary.domain).\(summary.code)",
                    message: "CloudKit sync failed",
                    numbers: numbers,
                    flags: flags,
                    tokens: tokens
                )
            }

            if event.type == .setup, !networkError {
                reopenStoreIfCloudKitRemovedIt(afterSetupError: nsError)
            }
        } else {
            DataIntegrityLog.breadcrumb(
                "CloudKit event finished",
                numbers: numbers,
                flags: ["succeeded": event.succeeded],
                tokens: ["type": type]
            )
        }

        if event.type == .import || event.type == .setup {
            let isNetworkError = event.error.map(CloudSyncStatus.isNetworkError) ?? false
            recurringGate.syncEventFinished(isImport: event.type == .import, succeeded: event.succeeded, isNetworkError: isNetworkError)

            if isNetworkError {
                scheduleRecurringFallback()
            }

            updateRecurringTransactionsIfReady()
        }

        guard Self.countsTransactions(around: event), let transactionsBefore else {
            return
        }

        let start = event.startDate
        let end = event.endDate
        let succeeded = event.succeeded

        countTransactionsInBackground { [weak self] transactionsAfter in
            guard let self else {
                return
            }

            // An unreadable count used to be reported as 0, which made a failed read look like every row was gone.
            guard let transactionsAfter else {
                DataIntegrityLog.breadcrumb(
                    "transaction count unreadable after a CloudKit event",
                    numbers: numbers,
                    flags: ["storeLoaded": self.isStoreLoaded],
                    tokens: ["type": type]
                )
                return
            }

            guard transactionsBefore >= 10,
                  transactionsAfter * 2 < transactionsBefore,
                  !Self.bulkDeletionOccurred(from: start, to: end)
            else {
                return
            }

            var dropNumbers = numbers
            dropNumbers["transactions"] = transactionsAfter

            // Which history authors deleted the rows tells a CloudKit purge apart from an ordinary import.
            self.transactionDeletionAuthors(since: start) { authors in
                var tokens = ["type": type]
                for (index, author) in authors.enumerated() {
                    tokens["author\(index + 1)"] = author.name
                    dropNumbers["author\(index + 1)Deletes"] = author.deletes
                }

                DataIntegrityLog.capture(
                    "CloudKit sync reduced the transaction count",
                    numbers: dropNumbers,
                    flags: ["succeeded": succeeded, "storeLoaded": self.isStoreLoaded],
                    tokens: tokens
                )
            }
        }
    }

    /// When CloudKit setup fails, the store can be left out of the coordinator, and the app then shows nothing
    /// for the rest of the session. It's opened again without mirroring, so the person's data stays in view.
    private func reopenStoreIfCloudKitRemovedIt(afterSetupError error: NSError) {
        guard !isStoreLoaded, storeLoadFailure == nil else {
            return
        }

        container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
        let reloadError = loadStore()

        DataIntegrityLog.capture(
            error,
            message: "Store reopened without iCloud after CloudKit setup removed it",
            flags: ["reopened": reloadError == nil]
        )

        if let reloadError {
            storeFailedToLoad(reloadError)
        } else {
            extensionHistoryToken = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        }
    }

    /// Counts transactions on a background context and reports on the main queue. Nil when the count fails.
    private func countTransactionsInBackground(_ completion: @escaping (Int?) -> Void) {
        let context = container.newBackgroundContext()

        context.perform {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            let count = try? context.count(for: request)

            DispatchQueue.main.async {
                completion(count)
            }
        }
    }

    /// The history authors that deleted the most transactions since `date`, most first, at most two.
    private func transactionDeletionAuthors(since date: Date, completion: @escaping ([(name: String, deletes: Int)]) -> Void) {
        let context = container.newBackgroundContext()

        context.perform {
            var deletesByAuthor: [String: Int] = [:]
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: date)

            if let result = try? context.execute(request) as? NSPersistentHistoryResult,
               let transactions = result.result as? [NSPersistentHistoryTransaction] {
                for transaction in transactions {
                    let deletes = (transaction.changes ?? []).filter {
                        $0.changeType == .delete && $0.changedObjectID.entity.name == "Transaction"
                    }.count

                    guard deletes > 0 else {
                        continue
                    }

                    let author = transaction.author ?? transaction.contextName ?? "none"
                    deletesByAuthor[DataIntegrityLog.safeToken(author), default: 0] += deletes
                }
            }

            let top = deletesByAuthor.sorted { $0.value > $1.value }.prefix(2).map { (name: $0.key, deletes: $0.value) }

            DispatchQueue.main.async {
                completion(Array(top))
            }
        }
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
            let nsError = error as NSError
            logger.error("Reading changes from extensions failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            DataIntegrityLog.capture(error, message: "Reading changes from extensions failed")
        }
    }

    func applicationWillEnterForeground() {
        // Changes a failed save left in the context, say before storage was freed up, get another try.
        isSaveFailureAcknowledged = false
        if container.viewContext.hasChanges {
            save()
        }

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
        DataIntegrityLog.breadcrumb("erase all", numbers: integrityCounts())
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(true, forKey: Self.didEraseAllDataKey)

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
        MainAccount.setSymbol(nil)
        save()
    }

    func save() {
        let context = container.viewContext

        guard context.hasChanges else {
            return
        }

        // Lets the backup check tell a deliberate bulk delete apart from data going missing.
        let deletedObjects = context.deletedObjects
        var deletedCounts: [String: Int] = [:]
        for object in deletedObjects {
            guard let name = object.entity.name,
                  ["Transaction", "Category", "Budget", "MainBudget", "TemplateTransaction"].contains(name)
            else {
                continue
            }
            deletedCounts[name, default: 0] += 1
        }

        let deletedTransactions = deletedCounts["Transaction"] ?? 0
        let deletedCategories = deletedCounts["Category"] ?? 0

        // Deletes made here, one at a time or many, so the integrity checks don't read them as data loss
        // (DIME-IOS-G was someone deleting ten transactions by hand).
        if deletedTransactions > 0, let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime") {
            for key in [Self.deletedSinceLastLoadKey, Self.deletedSinceBackupKey] {
                defaults.set(defaults.integer(forKey: key) + deletedTransactions, forKey: key)
            }
        }

        if deletedCategories > 0 || deletedTransactions >= 10 {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(Date.now, forKey: Self.lastBulkDeletionKey)
            DataIntegrityLog.breadcrumb(
                "bulk delete",
                numbers: [
                    "transactions": deletedTransactions,
                    "categories": deletedCategories,
                    "budgets": deletedCounts["Budget"] ?? 0,
                    "mainBudgets": deletedCounts["MainBudget"] ?? 0,
                    "templates": deletedCounts["TemplateTransaction"] ?? 0
                ]
            )
        }

        do {
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()

            isSaveFailureAcknowledged = false
            if saveFailure != nil {
                saveFailure = nil
            }
        } catch {
            let nsError = error as NSError
            let outOfSpace = DataIntegrityLog.isOutOfSpace(error)
            logger.error("Saving the view context failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")

            let summary = DataIntegrityLog.failureSummary(for: error)
            let numbers = [
                "transactions": deletedTransactions,
                "categories": deletedCategories,
                "pendingObjects": context.insertedObjects.count + context.updatedObjects.count + context.deletedObjects.count
            ]

            if reportedSaveFailures.insert("\(summary.domain).\(summary.code)").inserted {
                DataIntegrityLog.capture(nsError, message: "Saving the view context failed", numbers: numbers, flags: ["outOfSpace": outOfSpace])
            } else {
                DataIntegrityLog.breadcrumb("saving the view context failed again", numbers: numbers, flags: ["outOfSpace": outOfSpace])
            }

            // The app's own saves are on the main thread; an extension has no one to tell.
            if !isAppExtension, Thread.isMainThread, !isSaveFailureAcknowledged, saveFailure == nil {
                saveFailure = SaveFailure(isOutOfSpace: outOfSpace)
            }
        }
    }

    /// The person has seen the save failure. It isn't shown again until a save succeeds or the app returns.
    func acknowledgeSaveFailure() {
        isSaveFailureAcknowledged = true
        saveFailure = nil
    }

    /// Deletes a category. Its transactions and Quick Add templates either move first (to another
    /// category, or to none) or are deleted with it, per `fate`. Its budget is always deleted.
    func deleteCategory(_ category: Category, fate: DeleteCategoryFate) {
        guard category.managedObjectContext != nil, !category.isDeleted else {
            return
        }

        if case let .move(to: destination) = fate {
            // A destination deleted meanwhile (say, on another device) leaves them without a category.
            let target = destination.flatMap { $0.managedObjectContext == nil || $0.isDeleted ? nil : $0 }

            for transaction in category.transactions as? Set<Transaction> ?? [] {
                transaction.category = target
            }

            for template in category.templates as? Set<TemplateTransaction> ?? [] {
                template.category = target
            }
        }

        container.viewContext.delete(category)
        save()
    }

    /// Deletes a transaction, and both legs when it's a transfer: one leg alone would show money
    /// leaving or arriving in an account with nothing on the other side.
    func deleteTransaction(_ transaction: Transaction) {
        // The other leg may already be gone, such as deleted by sync; only one that's still here is deleted.
        if !transaction.isGone, let counterpart = transaction.transferCounterpart, !counterpart.isGone {
            container.viewContext.delete(counterpart)
        }

        // A payment towards a debt takes the interest logged with it.
        if !transaction.isGone, transaction.isTransfer {
            deleteInterestCharges(forTransfer: transaction.transferID)
        }

        delete(transaction)
    }

    /// Deletes and saves, unless sync from another device already deleted it while a sheet or menu was open.
    /// Deleting an object that has no context any more throws.
    func delete(_ object: NSManagedObject) {
        guard !object.isGone else {
            return
        }

        container.viewContext.delete(object)
        save()
    }

    /// Logs the occurrences of a recurring transaction that are due by today, telling `inserted` about each.
    @discardableResult
    func updateRecurringTransaction(transaction: Transaction, inserted: (Transaction) -> Void = { _ in }) -> Bool {
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

            let carriesRecurrence = followingDate >= startOfTomorrow

            if transaction.isTransfer {
                // Stops once its goal is reached or its debt is paid off, or once the other side is gone.
                guard let occurrence = insertTransferOccurrence(of: transaction, on: occurrenceDate, carriesRecurrence: carriesRecurrence) else {
                    break
                }
                inserted(occurrence)
            } else {
                inserted(insertOccurrence(of: transaction, on: occurrenceDate, carriesRecurrence: carriesRecurrence))
            }
            occurrenceDate = followingDate
        }

        transaction.recurringType = 0

        save()

        return true
    }

    /// Logs the next occurrence of a repeating transfer, both legs of it, from its outgoing leg. Nil, logging
    /// nothing, when the transfer has nowhere to go any more, or goes into a goal that's reached or a debt that's
    /// paid off: saving or paying more would overshoot.
    private func insertTransferOccurrence(of outgoing: Transaction, on date: Date, carriesRecurrence: Bool) -> Transaction? {
        guard let incoming = outgoing.transferCounterpart, !incoming.isGone else {
            return nil
        }

        if let destination = incoming.account, !destination.isGone {
            if destination.isGoal, !destination.repeatsMonthly, destination.targetAmount > 0,
               destination.balance(using: currencyConverter, asOf: date).value >= destination.targetAmount - 0.005 {
                return nil
            }

            if destination.isDebt, -destination.balance(using: currencyConverter, asOf: date).value < 0.005 {
                return nil
            }
        }

        let legs = saveTransfer(
            from: outgoing.accountChoice,
            to: incoming.accountChoice,
            amount: outgoing.amount,
            currencyCode: outgoing.currencyCode ?? currencyConverter.mainCurrency,
            date: date,
            note: outgoing.wrappedNote,
            repeatType: carriesRecurrence ? Int(outgoing.recurringType) : 0,
            repeatCoefficient: Int(outgoing.recurringCoefficient)
        )

        // Every occurrence is an occurrence of a repeating transfer, like other repeating transactions.
        legs.outgoing.onceRecurring = true
        logInterest(forPayment: legs.incoming)

        return legs.outgoing
    }

    private func insertOccurrence(of transaction: Transaction, on date: Date, carriesRecurrence: Bool) -> Transaction {
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

        // Queued for a category once it's saved, unless the user left the recurring one without a category.
        autoCategoryQueue.addOccurrence(occurrence, of: transaction)

        return occurrence
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

        // Shortcuts, automations and Quick Add log through here, in the app or in a widget. Imports don't,
        // so they never queue thousands of transactions at once.
        autoCategoryQueue.add([transaction])

        return transaction
    }

    /// Logs a transaction from Shortcuts, inserted and saved on a background context. Returns its ID; throws
    /// when it couldn't be saved, so the action doesn't say it was logged.
    ///
    /// The action runs on the main actor, and saving in the view context waited there on a slow disk write for
    /// 2–3 seconds (DIME-IOS-Y). The action always logs at the current time, so a recurring transaction has no
    /// earlier occurrences to fill in here; the app catches up on recurring transactions as usual.
    @available(iOS 16, *)
    @MainActor
    func newTransactionInBackground(note: String, categoryID: NSManagedObjectID?, income: Bool, amount: Double, currencyCode: String?, accountID: NSManagedObjectID? = nil, repeatType: Int) async throws -> NSManagedObjectID {
        let author = container.viewContext.transactionAuthor
        let mergePolicy = container.viewContext.mergePolicy
        let resolvedCurrency = currencyCode ?? currencyForNewTransaction()
        let categoryQueue = self.autoCategoryQueue

        let objectID: NSManagedObjectID = try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.transactionAuthor = author
                context.mergePolicy = mergePolicy

                let category = categoryID.flatMap { try? context.existingObject(with: $0) as? Category }
                // No account, or one deleted meanwhile, is Main.
                let account = accountID.flatMap { try? context.existingObject(with: $0) as? Account }.flatMap { $0.isDeleted ? nil : $0 }
                let transaction = Transaction(context: context)
                Self.fill(transaction, note: note, category: category, income: income, amount: amount, currencyCode: resolvedCurrency, account: account, date: Date.now, repeatType: repeatType, repeatCoefficient: 1)

                do {
                    try context.save()
                    // Feature Lab: queued for Apple Intelligence, like any other new transaction.
                    categoryQueue.add([transaction])
                    continuation.resume(returning: transaction.objectID)
                } catch {
                    let nsError = error as NSError
                    DataIntegrityLog.capture(nsError, message: "Saving a Shortcuts transaction failed", flags: ["outOfSpace": DataIntegrityLog.isOutOfSpace(error)])
                    context.rollback()
                    continuation.resume(throwing: CustomError.coreDataSave)
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return objectID
    }

    /// Inserts a transaction without saving, so imports can save many at once. No account means Main.
    func insertTransaction(note: String, category: Category?, income: Bool, amount: Double, currencyCode: String? = nil, account: Account? = nil, date: Date, repeatType: Int = 0, repeatCoefficient: Int = 1) -> Transaction {
        let transaction = Transaction(context: container.viewContext)
        Self.fill(transaction, note: note, category: category, income: income, amount: amount, currencyCode: currencyCode ?? currencyForNewTransaction(), account: account, date: date, repeatType: repeatType, repeatCoefficient: repeatCoefficient)

        if repeatType > 0 {
            updateRecurringTransaction(transaction: transaction)
        }

        return transaction
    }

    /// A new transaction's values, in whichever context it was inserted. Recurrences are set up but not filled in.
    private static func fill(_ transaction: Transaction, note: String, category: Category?, income: Bool, amount: Double, currencyCode: String, account: Account?, date: Date, repeatType: Int, repeatCoefficient: Int) {
        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income
        transaction.category = category
        transaction.account = account

        transaction.amount = amount
        transaction.currencyCode = currencyCode
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
        }
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
        guard !template.isGone else {
            return
        }

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

    /// Adds an account. Without `symbol`, its icon is guessed from its name.
    @discardableResult
    func addAccount(named name: String, symbol: String? = nil) -> Account {
        // Worked out before inserting, or the new account counts itself.
        let order = (accounts().map(\.order).max() ?? -1) + 1

        let account = Account(context: container.viewContext)
        account.id = UUID()
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.symbol = symbol ?? AccountIcons.guess(for: name)
        account.dateCreated = Date.now
        account.order = order

        save()

        return account
    }

    /// Renames an account and, with `symbol`, changes its icon.
    func renameAccount(_ choice: AccountChoice, to name: String, symbol: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch choice {
        case .main:
            MainAccount.rename(to: trimmed)
            if let symbol {
                MainAccount.setSymbol(symbol)
            }
            objectWillChange.send()
            WidgetCenter.shared.reloadAllTimelines()
        case let .account(account):
            // Sync can delete it while its editor is open.
            guard !account.isDeleted, account.managedObjectContext != nil else { return }
            account.name = trimmed
            if let symbol {
                account.symbol = symbol
            }
            save()
        }
    }

    /// Changes Main's icon alone, such as when a backup brings it back.
    func setMainAccountSymbol(_ symbol: String) {
        MainAccount.setSymbol(symbol)
        objectWillChange.send()
    }

    /// The transfers between an account and Main, as the legs in the account. Once the account is deleted and
    /// its side moves to Main, each would move money from Main to Main.
    func transfersWithMain(of account: Account) -> [Transaction] {
        let legs = (account.transactions as? Set<Transaction> ?? []).filter { $0.isTransfer && !$0.isDeleted }

        return legs.filter { leg in
            guard let other = leg.transferCounterpart else { return false }
            return other.account == nil || other.account == account
        }
    }

    /// Deletes an account. Its transactions and Quick Add templates move to Main. The only thing deleted with it
    /// is its transfers with Main, which would be from Main to Main, and the confirmation says so first.
    ///
    /// The model's delete rule would also leave the rest in Main, but they're moved here first so that no
    /// transaction ever depends on a delete rule to survive.
    func deleteAccount(_ account: Account) {
        // Sync can delete it while the confirmation is up, and deleting an object with no context throws.
        guard !account.isDeleted, account.managedObjectContext != nil else { return }

        for leg in transfersWithMain(of: account) where !leg.isDeleted {
            if let other = leg.transferCounterpart {
                container.viewContext.delete(other)
            }
            // A debt's payments from Main go, so the interest logged with them goes too.
            deleteInterestCharges(forTransfer: leg.transferID)
            container.viewContext.delete(leg)
        }

        for transaction in account.transactions as? Set<Transaction> ?? [] where !transaction.isDeleted {
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
    func saveTransfer(editing leg: Transaction? = nil, from: AccountChoice, to: AccountChoice, amount: Double, currencyCode: String, date: Date, note: String, repeatType: Int = 0, repeatCoefficient: Int = 1) -> (outgoing: Transaction, incoming: Transaction) {
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

        // An account deleted meanwhile, such as by sync, can't be linked; what was in it is in Main now.
        func linkable(_ choice: AccountChoice) -> Account? {
            choice.account.flatMap { ($0.isDeleted || $0.managedObjectContext == nil) ? nil : $0 }
        }

        for (transaction, isIncoming, account) in [(outgoing, false, linkable(from)), (incoming, true, linkable(to))] {
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

            // Only the outgoing leg repeats, so each occurrence is logged once, with both its legs.
            let repeats = !isIncoming && (1 ... 3).contains(repeatType)
            transaction.recurringType = repeats ? Int16(repeatType) : 0
            transaction.recurringCoefficient = repeats ? Int16(max(1, repeatCoefficient)) : 1
            transaction.onceRecurring = repeats
        }

        save()

        // A backdated repeating transfer logs the occurrences already due.
        if outgoing.recurringType > 0 {
            updateRecurringTransaction(transaction: outgoing)
        }

        return (outgoing, incoming)
    }

    /// Turns one leg of a transfer back into an ordinary transaction in its own account, deleting the other leg.
    func endTransfer(keeping leg: Transaction) {
        if let counterpart = leg.transferCounterpart {
            container.viewContext.delete(counterpart)
        }

        deleteInterestCharges(forTransfer: leg.transferID)
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

    /// Repeating transactions, and repeating transfers by their outgoing leg. An incoming leg never carries the
    /// repeat; one that does, from a bad sync, is left out so it can't log a second copy of each occurrence.
    func fetchRequestForRecurringTransactions() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "%K > %i AND (%K == nil OR %K == NO)", #keyPath(Transaction.recurringType), 0, #keyPath(Transaction.transferID), #keyPath(Transaction.income))
        return itemRequest
    }

    /// Both legs of each transfer; a list shows each once with `oneLegPerTransfer()`.
    func fetchRequestForRecentTransactions(type: TimePeriod) -> NSFetchRequest<Transaction> {
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

    /// `accounts` limits it to some accounts; nil counts every account.
    func shortcutInsightsTotal(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [Category], accounts: NSPredicate? = nil) -> MoneyTotal {
        let fetchRequest = fetchRequestForLogView(type: timeframe, optionalIncome: optionalIncome, categoryFilters: categories)
        if let accounts {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fetchRequest.predicate, accounts].compactMap { $0 })
        }
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

    /// The log header's net, spent and earned totals from one fetch, and with `lineGraph` (the header's
    /// display type) its line graph. Call on `context`'s queue.
    func logInsightsSummary(type: Int, lineGraph displayType: Int?, in context: NSManagedObjectContext) -> LogInsightsSummary {
        let transactions = results(for: fetchRequestForLogView(type: type, optionalIncome: nil), in: context)
        let converter = currencyConverter
        var summary = LogInsightsSummary()

        summary.net = transactions.total(using: converter, signed: true)
        summary.spent = transactions.filter { !$0.income }.total(using: converter)
        summary.income = transactions.filter(\.income).total(using: converter)

        if let displayType {
            if displayType == 1 {
                summary.lineGraph = lineGraphNet(type: type, in: context).points
            } else {
                summary.lineGraph = lineGraph(income: displayType == 2, type: type, in: context).points
            }
        }

        return summary
    }

    /// `logInsightsSummary` worked out on a background context.
    ///
    /// The header used to fetch every transaction in its time frame several times over on each redraw, and
    /// the log redraws it on every change to the view context. While CloudKit merged an import into a store
    /// of 4,000 transactions, that held the main thread for 10 seconds (DIME-IOS-Q).
    func loadLogInsightsSummary(type: Int, lineGraph displayType: Int?) async -> LogInsightsSummary {
        await withCheckedContinuation { continuation in
            container.performBackgroundTask { context in
                continuation.resume(returning: self.logInsightsSummary(type: type, lineGraph: displayType, in: context))
            }
        }
    }

    func getLineGraphDataNet(type: Int) -> [LineGraphDataPoint] {
        lineGraphNet(type: type).points
    }

    func lineGraphNet(type: Int, in context: NSManagedObjectContext? = nil) -> (points: [LineGraphDataPoint], report: ConversionReport) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: nil)
        let transactions = results(for: fetchRequest, in: context)
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

    func lineGraph(income: Bool, type: Int, in context: NSManagedObjectContext? = nil) -> (points: [LineGraphDataPoint], report: ConversionReport) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: income)
        let transactions = results(for: fetchRequest, in: context)
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

        let predicates = [startPredicate, endPredicate, incomePredicate, TransferPredicate.excluded] + [budget.accountPredicate]

        itemRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return itemRequest
    }

    func fetchRequestForBudgetTransactions(budget: Budget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), budget.startDate! as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), budget.category!)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let predicates = [startPredicate, endPredicate, categoryPredicate, incomePredicate, TransferPredicate.excluded] + [budget.accountPredicate]

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

    /// Both legs of each transfer, so twice `count` rows: a list shows each transfer once with
    /// `oneLegPerTransfer()`, then takes `count`.
    func fetchRequestForRecentTransactionsWithCount(type: TimePeriod, count: Int) -> NSFetchRequest<Transaction> {
        let request = fetchRequestForRecentTransactionsWithCountIncludingTransfers(type: type, count: count)
        if request.fetchLimit > 0 {
            request.fetchLimit = count * 2
        }
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

    /// For the interface. Integrity checks use `readableTransactionCount()`, which doesn't turn a failure into 0.
    func transactionCount() -> Int {
        readableTransactionCount() ?? 0
    }

    /// Nil when the count fails, as it does with the store out of the coordinator.
    func readableTransactionCount() -> Int? {
        count(of: "Transaction")
    }

    /// Only the counts that could be read. A missing key means the count failed, never that it was 0.
    func integrityCounts() -> [String: Int] {
        let names = [
            "Transaction": "transactions",
            "Category": "categories",
            "Budget": "budgets",
            "MainBudget": "mainBudgets",
            "TemplateTransaction": "templates",
            "Account": "accounts"
        ]

        var counts: [String: Int] = [:]
        for (entityName, key) in names {
            counts[key] = count(of: entityName)
        }
        return counts
    }

    private func count(of entityName: String) -> Int? {
        guard container.managedObjectModel.entitiesByName[entityName] != nil else {
            return 0
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)

        do {
            return try container.viewContext.count(for: request)
        } catch {
            let nsError = error as NSError
            logger.error("Counting \(entityName, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return nil
        }
    }

    private struct StoreFileFacts {
        var exists = false
        var bytes = 0
        var walBytes = 0
        var shmBytes = 0
        var snapshotCount = 0
    }

    private static func storeFileFacts(_ storeURL: URL?) -> StoreFileFacts {
        guard let storeURL else {
            return StoreFileFacts()
        }

        func byteCount(_ url: URL) -> Int {
            (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }

        var facts = StoreFileFacts()
        facts.exists = FileManager.default.fileExists(atPath: storeURL.path)
        facts.bytes = byteCount(storeURL)
        facts.walBytes = byteCount(URL(fileURLWithPath: storeURL.path + "-wal"))
        facts.shmBytes = byteCount(URL(fileURLWithPath: storeURL.path + "-shm"))
        facts.snapshotCount = StoreSnapshot.list(in: StoreSnapshot.directory(forStoreAt: storeURL)).count
        return facts
    }

    private static func bulkDeletionOccurred(from start: Date?, to end: Date?) -> Bool {
        guard let deletion = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.object(forKey: lastBulkDeletionKey) as? Date else {
            return false
        }
        if let start, deletion < start {
            return false
        }
        if let end, deletion > end.addingTimeInterval(2) {
            return false
        }
        return true
    }

    private static func cloudKitEventToken(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return "setup"
        case .import:
            return "import"
        case .export:
            return "export"
        @unknown default:
            return "unknown"
        }
    }

    private static func accountStatusToken(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        @unknown default:
            return "unknown"
        }
    }

    private func noteStoreLoaded(storeURL: URL?, migrationNeeded: Bool, countsBeforeMigration: [String: Int]?) {
        let facts = Self.storeFileFacts(storeURL)
        let counts = integrityCounts()
        var numbers = counts
        numbers["fileBytes"] = facts.bytes
        numbers["walBytes"] = facts.walBytes
        numbers["shmBytes"] = facts.shmBytes
        numbers["snapshotCount"] = facts.snapshotCount

        if let countsBeforeMigration {
            for (key, value) in countsBeforeMigration {
                numbers["before_\(key)"] = value
            }
        }

        // A count that couldn't be read is left out rather than compared as 0.
        let tracked = ["transactions", "categories", "budgets", "mainBudgets", "templates", "accounts"]
        let migrationDropped = migrationNeeded && countsBeforeMigration.map { before in
            tracked.contains { key in
                guard let now = counts[key], let earlier = before[key] else {
                    return false
                }
                return now < earlier
            }
        } ?? false
        let erasedAll = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.bool(forKey: Self.didEraseAllDataKey) ?? false

        // Emptied: there were transactions at the previous load, more than the person has deleted since, and
        // now there are none. A new install's empty store (about 112 KB with CloudKit's tables) used to trip a
        // file-size check instead (DIME-IOS-1).
        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let transactionsAtLastLoad = defaults?.object(forKey: Self.transactionsAtLastLoadKey) as? Int
        let deletedSinceLastLoad = defaults?.integer(forKey: Self.deletedSinceLastLoadKey) ?? 0
        let emptyWithoutErase = counts["transactions"] == 0 && (transactionsAtLastLoad ?? 0) - deletedSinceLastLoad > 0
        numbers["transactionsAtLastLoad"] = transactionsAtLastLoad
        numbers["deletedSinceLastLoad"] = deletedSinceLastLoad

        if let transactions = counts["transactions"] {
            defaults?.set(transactions, forKey: Self.transactionsAtLastLoadKey)
            defaults?.set(0, forKey: Self.deletedSinceLastLoadKey)
        }

        DataIntegrityLog.breadcrumb(
            "store loaded",
            numbers: numbers,
            flags: [
                "migrationNeeded": migrationNeeded,
                "cloudKit": isCloudKitSyncEnabled,
                "fileExists": facts.exists,
                "syncPreferred": Self.isICloudSyncPreferred,
                "erasedAll": erasedAll,
                "countsReadable": counts["transactions"] != nil
            ],
            persist: migrationDropped || emptyWithoutErase
        )

        if migrationDropped {
            DataIntegrityLog.capture(
                "Store migration reduced record counts",
                numbers: numbers,
                flags: ["cloudKit": isCloudKitSyncEnabled]
            )
        }

        if emptyWithoutErase {
            DataIntegrityLog.captureOnce(
                key: "emptied-store",
                message: "Store emptied unexpectedly",
                numbers: numbers,
                flags: ["cloudKit": isCloudKitSyncEnabled, "migrationNeeded": migrationNeeded, "erasedAll": erasedAll]
            )
        }
    }

    /// Fetches in the view context, or in `context` (on its queue) when given.
    func results<T: NSManagedObject>(for fetchRequest: NSFetchRequest<T>, in context: NSManagedObjectContext? = nil) -> [T] {
        return (try? (context ?? container.viewContext).fetch(fetchRequest)) ?? []
    }
}

extension Transaction {
    /// Every transaction as a fault, without its values: for views that only check whether there are any.
    static var identifiersOnlyRequest: NSFetchRequest<Transaction> {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = []
        request.includesPropertyValues = false
        return request
    }
}

extension NSManagedObjectContext {
    private static let recordEntityNames: Set<String> = ["Transaction", "Category", "Budget", "MainBudget", "TemplateTransaction"]

    /// A save in any context that changed Dime's records, delivered on the main queue.
    ///
    /// NSManagedObjectContextDidSave is posted on the saving context's queue: CloudKit imports and exports,
    /// backups and currency changes all save on background queues. A view's onReceive runs on that queue,
    /// and updating view state there crashed in MainActor.assumeIsolated. The objects are inspected before
    /// the hop, on the queue they belong to, and CloudKit's metadata-only saves are left out.
    static let recordsDidSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
        .filter { notification in
            guard let userInfo = notification.userInfo else {
                return false
            }

            return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
                guard let objects = userInfo[key] as? Set<NSManagedObject> else {
                    return false
                }

                return objects.contains { NSManagedObjectContext.recordEntityNames.contains($0.entity.name ?? "") }
            }
        }
        .map { _ in () }
        .receive(on: DispatchQueue.main)
        .share()
}

extension NSManagedObject {
    /// Deleted, here or by a change synced from another device, so it can't be changed, linked or deleted.
    var isGone: Bool {
        isDeleted || managedObjectContext == nil
    }
}

struct LogInsightsSummary: Equatable {
    var net = MoneyTotal()
    var spent = MoneyTotal()
    var income = MoneyTotal()
    var lineGraph: [LineGraphDataPoint] = []
}

struct LineGraphDataPoint: Equatable {
    let date: Date
    let amount: Double

    var dateString: String {
        CachedFormatter.date(format: "d MMM").string(from: date)
    }

    var monthString: String {
        CachedFormatter.date(format: "MMM yy").string(from: date)
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
// Launch with `-demoData minimal` or `-demoData varied` to run against a seeded in-memory store, or
// `-demoData empty` against an empty one, as on a new install.
enum DemoDataset: String {
    case minimal
    case varied
    case empty

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-demoData"), index + 1 < arguments.count else {
            return nil
        }

        self.init(rawValue: arguments[index + 1])
    }
}

/// Demo data in the app's language. `-demoCurrency JPY` also makes that the main currency, with amounts
/// scaled so they look natural in it, for localized App Store screenshots.
enum DemoLocale {
    static let currencyCode: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoCurrency"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].uppercased()
    }()

    /// Roughly how many units of the currency buy a dollar, and the steps amounts and budgets are rounded to.
    private static let scaling: (factor: Double, amountStep: Double, budgetStep: Double) = {
        switch currencyCode {
        case "BRL": return (5, 0.1, 50)
        case "CNY": return (7, 0.1, 50)
        case "TWD": return (30, 1, 100)
        case "TRY": return (40, 1, 500)
        case "RUB": return (90, 1, 1000)
        case "JPY": return (150, 10, 1000)
        case "KRW": return (1400, 100, 10000)
        default: return (1, 0.01, 10)
        }
    }()

    static var budgetStep: Double { scaling.budgetStep }

    static func amount(_ dollars: Double) -> Double {
        guard scaling.factor != 1 else { return dollars }
        return (dollars * scaling.factor / scaling.amountStep).rounded() * scaling.amountStep
    }

    static func text(_ english: String) -> String {
        guard let language = Bundle.main.preferredLocalizations.first else { return english }
        return translations[language]?[english] ?? english
    }

    // US-only shops become generic names outside English.
    private static let translations: [String: [String: String]] = [
        "de": [
            "Food": "Essen", "Groceries": "Lebensmittel", "Transport": "Verkehr", "Coffee": "Kaffee", "Shopping": "Shopping",
            "Entertainment": "Freizeit", "Bills": "Rechnungen", "Health": "Gesundheit", "Salary": "Gehalt", "Freelance": "Freiberuflich",
            "Blue Bottle": "Café", "Flat white": "Flat White", "Oat latte": "Hafer-Latte", "Cold brew": "Cold Brew",
            "Dinner – Ramen": "Abendessen – Ramen", "Thai with Mia": "Thai mit Mia", "Pizza night": "Pizzaabend", "Sushi": "Sushi",
            "Lunch": "Mittagessen", "Lunch with Sam": "Mittagessen mit Sam", "Poke bowl": "Poke Bowl", "Sandwich": "Sandwich",
            "Whole Foods": "Supermarkt", "Trader Joe's": "Wocheneinkauf", "Costco": "Großeinkauf", "Farmers market": "Wochenmarkt",
            "Metro card": "U-Bahn-Ticket", "Lyft": "Taxi", "Parking": "Parken", "New sneakers": "Neue Sneaker", "Desk lamp": "Schreibtischlampe",
            "Cinema": "Kino", "Concert tickets": "Konzertkarten", "Bowling": "Bowling", "Museum": "Museum",
            "Pharmacy": "Apotheke", "Dentist": "Zahnarzt", "Vitamins": "Vitamine", "Electricity": "Strom", "Phone plan": "Handyvertrag",
            "Logo design": "Logodesign", "Ramen": "Ramen", "Bakery": "Bäckerei",
        ],
        "es": [
            "Food": "Comida", "Groceries": "Súper", "Transport": "Transporte", "Coffee": "Café", "Shopping": "Compras",
            "Entertainment": "Ocio", "Bills": "Facturas", "Health": "Salud", "Salary": "Salario", "Freelance": "Freelance",
            "Blue Bottle": "Cafetería", "Flat white": "Flat white", "Oat latte": "Latte de avena", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Cena – Ramen", "Thai with Mia": "Tailandés con Mia", "Pizza night": "Noche de pizza", "Sushi": "Sushi",
            "Lunch": "Almuerzo", "Lunch with Sam": "Almuerzo con Sam", "Poke bowl": "Poke", "Sandwich": "Sándwich",
            "Whole Foods": "Supermercado", "Trader Joe's": "Compra semanal", "Costco": "Compra grande", "Farmers market": "Mercado",
            "Metro card": "Metro", "Lyft": "Taxi", "Parking": "Aparcamiento", "New sneakers": "Zapatillas nuevas", "Desk lamp": "Lámpara de escritorio",
            "Cinema": "Cine", "Concert tickets": "Entradas de concierto", "Bowling": "Bolos", "Museum": "Museo",
            "Pharmacy": "Farmacia", "Dentist": "Dentista", "Vitamins": "Vitaminas", "Electricity": "Luz", "Phone plan": "Tarifa móvil",
            "Logo design": "Diseño de logo", "Ramen": "Ramen", "Bakery": "Panadería",
        ],
        "fr": [
            "Food": "Repas", "Groceries": "Courses", "Transport": "Transports", "Coffee": "Café", "Shopping": "Shopping",
            "Entertainment": "Loisirs", "Bills": "Factures", "Health": "Santé", "Salary": "Salaire", "Freelance": "Freelance",
            "Blue Bottle": "Café du coin", "Flat white": "Flat white", "Oat latte": "Latte avoine", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Dîner – Ramen", "Thai with Mia": "Thaï avec Mia", "Pizza night": "Soirée pizza", "Sushi": "Sushis",
            "Lunch": "Déjeuner", "Lunch with Sam": "Déjeuner avec Sam", "Poke bowl": "Poke bowl", "Sandwich": "Sandwich",
            "Whole Foods": "Supermarché", "Trader Joe's": "Courses de la semaine", "Costco": "Grosses courses", "Farmers market": "Marché",
            "Metro card": "Ticket de métro", "Lyft": "Taxi", "Parking": "Parking", "New sneakers": "Nouvelles baskets", "Desk lamp": "Lampe de bureau",
            "Cinema": "Cinéma", "Concert tickets": "Billets de concert", "Bowling": "Bowling", "Museum": "Musée",
            "Pharmacy": "Pharmacie", "Dentist": "Dentiste", "Vitamins": "Vitamines", "Electricity": "Électricité", "Phone plan": "Forfait mobile",
            "Logo design": "Création de logo", "Ramen": "Ramen", "Bakery": "Boulangerie",
        ],
        "it": [
            "Food": "Pasti", "Groceries": "Spesa", "Transport": "Trasporti", "Coffee": "Caffè", "Shopping": "Shopping",
            "Entertainment": "Svago", "Bills": "Bollette", "Health": "Salute", "Salary": "Stipendio", "Freelance": "Freelance",
            "Blue Bottle": "Bar", "Flat white": "Flat white", "Oat latte": "Latte d’avena", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Cena – Ramen", "Thai with Mia": "Thai con Mia", "Pizza night": "Serata pizza", "Sushi": "Sushi",
            "Lunch": "Pranzo", "Lunch with Sam": "Pranzo con Sam", "Poke bowl": "Poke", "Sandwich": "Panino",
            "Whole Foods": "Supermercato", "Trader Joe's": "Spesa settimanale", "Costco": "Spesa grossa", "Farmers market": "Mercato",
            "Metro card": "Biglietto metro", "Lyft": "Taxi", "Parking": "Parcheggio", "New sneakers": "Sneakers nuove", "Desk lamp": "Lampada da scrivania",
            "Cinema": "Cinema", "Concert tickets": "Biglietti concerto", "Bowling": "Bowling", "Museum": "Museo",
            "Pharmacy": "Farmacia", "Dentist": "Dentista", "Vitamins": "Vitamine", "Electricity": "Luce", "Phone plan": "Abbonamento telefono",
            "Logo design": "Design logo", "Ramen": "Ramen", "Bakery": "Panetteria",
        ],
        "ja": [
            "Food": "外食", "Groceries": "食料品", "Transport": "交通費", "Coffee": "コーヒー", "Shopping": "買い物",
            "Entertainment": "娯楽", "Bills": "固定費", "Health": "医療", "Salary": "給料", "Freelance": "副業",
            "Blue Bottle": "カフェ", "Flat white": "フラットホワイト", "Oat latte": "オーツラテ", "Cold brew": "コールドブリュー",
            "Dinner – Ramen": "夕食 – ラーメン", "Thai with Mia": "ミアとタイ料理", "Pizza night": "ピザパーティー", "Sushi": "寿司",
            "Lunch": "ランチ", "Lunch with Sam": "サムとランチ", "Poke bowl": "ポキ丼", "Sandwich": "サンドイッチ",
            "Whole Foods": "スーパー", "Trader Joe's": "週末の買い出し", "Costco": "まとめ買い", "Farmers market": "マルシェ",
            "Metro card": "地下鉄", "Lyft": "タクシー", "Parking": "駐車場", "New sneakers": "新しいスニーカー", "Desk lamp": "デスクライト",
            "Cinema": "映画", "Concert tickets": "コンサートチケット", "Bowling": "ボウリング", "Museum": "美術館",
            "Pharmacy": "薬局", "Dentist": "歯医者", "Vitamins": "サプリ", "Electricity": "電気代", "Phone plan": "携帯代",
            "Logo design": "ロゴデザイン", "Ramen": "ラーメン", "Bakery": "パン屋", "Uniqlo": "ユニクロ",
        ],
        "ko": [
            "Food": "식비", "Groceries": "장보기", "Transport": "교통", "Coffee": "커피", "Shopping": "쇼핑",
            "Entertainment": "여가", "Bills": "공과금", "Health": "건강", "Salary": "월급", "Freelance": "프리랜스",
            "Blue Bottle": "카페", "Flat white": "플랫 화이트", "Oat latte": "오트 라테", "Cold brew": "콜드브루",
            "Dinner – Ramen": "저녁 – 라멘", "Thai with Mia": "미아와 태국 음식", "Pizza night": "피자 파티", "Sushi": "초밥",
            "Lunch": "점심", "Lunch with Sam": "샘과 점심", "Poke bowl": "포케", "Sandwich": "샌드위치",
            "Whole Foods": "마트", "Trader Joe's": "주간 장보기", "Costco": "대용량 구매", "Farmers market": "시장",
            "Metro card": "지하철", "Lyft": "택시", "Parking": "주차", "New sneakers": "새 운동화", "Desk lamp": "책상 조명",
            "Cinema": "영화", "Concert tickets": "콘서트 티켓", "Bowling": "볼링", "Museum": "미술관",
            "Pharmacy": "약국", "Dentist": "치과", "Vitamins": "비타민", "Electricity": "전기 요금", "Phone plan": "휴대폰 요금",
            "Logo design": "로고 디자인", "Ramen": "라멘", "Bakery": "빵집", "Uniqlo": "유니클로", "Amazon": "온라인 쇼핑",
        ],
        "nl": [
            "Food": "Eten", "Groceries": "Boodschappen", "Transport": "Vervoer", "Coffee": "Koffie", "Shopping": "Winkelen",
            "Entertainment": "Uitjes", "Bills": "Rekeningen", "Health": "Gezondheid", "Salary": "Salaris", "Freelance": "Freelance",
            "Blue Bottle": "Koffiebar", "Flat white": "Flat white", "Oat latte": "Haverlatte", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Diner – Ramen", "Thai with Mia": "Thais met Mia", "Pizza night": "Pizza-avond", "Sushi": "Sushi",
            "Lunch": "Lunch", "Lunch with Sam": "Lunch met Sam", "Poke bowl": "Poke bowl", "Sandwich": "Broodje",
            "Whole Foods": "Supermarkt", "Trader Joe's": "Weekboodschappen", "Costco": "Groothandel", "Farmers market": "Markt",
            "Metro card": "Metrokaartje", "Lyft": "Taxi", "Parking": "Parkeren", "New sneakers": "Nieuwe sneakers", "Desk lamp": "Bureaulamp",
            "Cinema": "Bioscoop", "Concert tickets": "Concertkaartjes", "Bowling": "Bowling", "Museum": "Museum",
            "Pharmacy": "Apotheek", "Dentist": "Tandarts", "Vitamins": "Vitamines", "Electricity": "Stroom", "Phone plan": "Telefoonabonnement",
            "Logo design": "Logo-ontwerp", "Ramen": "Ramen", "Bakery": "Bakker",
        ],
        "pt-BR": [
            "Food": "Comida", "Groceries": "Mercado", "Transport": "Transporte", "Coffee": "Café", "Shopping": "Compras",
            "Entertainment": "Lazer", "Bills": "Contas", "Health": "Saúde", "Salary": "Salário", "Freelance": "Freela",
            "Blue Bottle": "Cafeteria", "Flat white": "Flat white", "Oat latte": "Latte de aveia", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Jantar – Lámen", "Thai with Mia": "Tailandês com a Mia", "Pizza night": "Noite da pizza", "Sushi": "Sushi",
            "Lunch": "Almoço", "Lunch with Sam": "Almoço com Sam", "Poke bowl": "Poke", "Sandwich": "Sanduíche",
            "Whole Foods": "Supermercado", "Trader Joe's": "Compras da semana", "Costco": "Compra do mês", "Farmers market": "Feira",
            "Metro card": "Metrô", "Lyft": "Táxi", "Parking": "Estacionamento", "New sneakers": "Tênis novo", "Desk lamp": "Luminária",
            "Cinema": "Cinema", "Concert tickets": "Ingressos do show", "Bowling": "Boliche", "Museum": "Museu",
            "Pharmacy": "Farmácia", "Dentist": "Dentista", "Vitamins": "Vitaminas", "Electricity": "Conta de luz", "Phone plan": "Plano de celular",
            "Logo design": "Design de logo", "Ramen": "Lámen", "Bakery": "Padaria",
        ],
        "ru": [
            "Food": "Еда", "Groceries": "Продукты", "Transport": "Транспорт", "Coffee": "Кофе", "Shopping": "Покупки",
            "Entertainment": "Развлечения", "Bills": "Счета", "Health": "Здоровье", "Salary": "Зарплата", "Freelance": "Фриланс",
            "Blue Bottle": "Кофейня", "Flat white": "Флэт уайт", "Oat latte": "Латте на овсяном", "Cold brew": "Колд брю",
            "Dinner – Ramen": "Ужин – рамен", "Thai with Mia": "Тайская кухня с Мией", "Pizza night": "Вечер пиццы", "Sushi": "Суши",
            "Lunch": "Обед", "Lunch with Sam": "Обед с Сэмом", "Poke bowl": "Поке", "Sandwich": "Сэндвич",
            "Whole Foods": "Супермаркет", "Trader Joe's": "Продукты на неделю", "Costco": "Закупка впрок", "Farmers market": "Рынок",
            "Metro card": "Метро", "Lyft": "Такси", "Parking": "Парковка", "New sneakers": "Новые кроссовки", "Desk lamp": "Настольная лампа",
            "Cinema": "Кино", "Concert tickets": "Билеты на концерт", "Bowling": "Боулинг", "Museum": "Музей",
            "Pharmacy": "Аптека", "Dentist": "Стоматолог", "Vitamins": "Витамины", "Electricity": "Электричество", "Phone plan": "Мобильная связь",
            "Logo design": "Дизайн логотипа", "Ramen": "Рамен", "Bakery": "Пекарня",
        ],
        "tr": [
            "Food": "Yemek", "Groceries": "Market", "Transport": "Ulaşım", "Coffee": "Kahve", "Shopping": "Alışveriş",
            "Entertainment": "Eğlence", "Bills": "Faturalar", "Health": "Sağlık", "Salary": "Maaş", "Freelance": "Serbest iş",
            "Blue Bottle": "Kafe", "Flat white": "Flat white", "Oat latte": "Yulaf sütlü latte", "Cold brew": "Cold brew",
            "Dinner – Ramen": "Akşam yemeği – Ramen", "Thai with Mia": "Mia ile Tayland yemeği", "Pizza night": "Pizza gecesi", "Sushi": "Suşi",
            "Lunch": "Öğle yemeği", "Lunch with Sam": "Sam ile öğle yemeği", "Poke bowl": "Poke", "Sandwich": "Sandviç",
            "Whole Foods": "Süpermarket", "Trader Joe's": "Haftalık alışveriş", "Costco": "Toplu alışveriş", "Farmers market": "Pazar",
            "Metro card": "Metro", "Lyft": "Taksi", "Parking": "Otopark", "New sneakers": "Yeni spor ayakkabı", "Desk lamp": "Masa lambası",
            "Cinema": "Sinema", "Concert tickets": "Konser bileti", "Bowling": "Bowling", "Museum": "Müze",
            "Pharmacy": "Eczane", "Dentist": "Diş hekimi", "Vitamins": "Vitamin", "Electricity": "Elektrik", "Phone plan": "Telefon faturası",
            "Logo design": "Logo tasarımı", "Ramen": "Ramen", "Bakery": "Fırın",
        ],
        "zh-Hans": [
            "Food": "餐饮", "Groceries": "买菜", "Transport": "交通", "Coffee": "咖啡", "Shopping": "购物",
            "Entertainment": "娱乐", "Bills": "账单", "Health": "医疗", "Salary": "工资", "Freelance": "副业",
            "Blue Bottle": "咖啡馆", "Flat white": "澳白", "Oat latte": "燕麦拿铁", "Cold brew": "冷萃",
            "Dinner – Ramen": "晚餐 – 拉面", "Thai with Mia": "和 Mia 吃泰餐", "Pizza night": "披萨之夜", "Sushi": "寿司",
            "Lunch": "午餐", "Lunch with Sam": "和 Sam 吃午饭", "Poke bowl": "波奇饭", "Sandwich": "三明治",
            "Whole Foods": "超市", "Trader Joe's": "每周采购", "Costco": "囤货", "Farmers market": "菜市场",
            "Uber": "网约车", "Metro card": "地铁", "Lyft": "打车", "Parking": "停车", "New sneakers": "新球鞋", "Uniqlo": "优衣库",
            "Amazon": "网购", "Desk lamp": "台灯", "Cinema": "电影", "Concert tickets": "演唱会门票", "Bowling": "保龄球", "Museum": "博物馆",
            "Pharmacy": "药店", "Dentist": "牙医", "Vitamins": "维生素", "Electricity": "电费", "Phone plan": "话费",
            "Logo design": "Logo 设计", "Netflix": "视频会员", "Ramen": "拉面", "Bakery": "面包店",
        ],
        "zh-Hant": [
            "Food": "餐飲", "Groceries": "買菜", "Transport": "交通", "Coffee": "咖啡", "Shopping": "購物",
            "Entertainment": "娛樂", "Bills": "帳單", "Health": "醫療", "Salary": "薪水", "Freelance": "接案",
            "Blue Bottle": "咖啡廳", "Flat white": "馥列白", "Oat latte": "燕麥拿鐵", "Cold brew": "冷萃",
            "Dinner – Ramen": "晚餐 – 拉麵", "Thai with Mia": "和 Mia 吃泰式料理", "Pizza night": "披薩之夜", "Sushi": "壽司",
            "Lunch": "午餐", "Lunch with Sam": "和 Sam 吃午餐", "Poke bowl": "波奇碗", "Sandwich": "三明治",
            "Whole Foods": "超市", "Trader Joe's": "每週採買", "Costco": "大量採購", "Farmers market": "傳統市場",
            "Metro card": "捷運", "Lyft": "計程車", "Parking": "停車", "New sneakers": "新球鞋", "Desk lamp": "檯燈",
            "Cinema": "電影", "Concert tickets": "演唱會門票", "Bowling": "保齡球", "Museum": "博物館",
            "Pharmacy": "藥局", "Dentist": "牙醫", "Vitamins": "維他命", "Electricity": "電費", "Phone plan": "電信費",
            "Logo design": "Logo 設計", "Ramen": "拉麵", "Bakery": "麵包店",
        ],
    ]
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

        if let currencyCode = DemoLocale.currencyCode {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(currencyCode, forKey: "currency")
        }

        func category(_ name: String, _ emoji: String, _ colour: String, income: Bool = false) -> Category {
            let category = Category(context: context)
            category.id = UUID()
            category.name = DemoLocale.text(name)
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
            transaction.note = DemoLocale.text(note)
            transaction.category = category
            transaction.income = category.income
            transaction.amount = DemoLocale.amount(amount)
            transaction.currencyCode = currencyCode
            transaction.date = date
            transaction.day = calendar.startOfDay(for: date)
            transaction.month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        }

        switch dataset {
        case .empty:
            return
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
            streaming.note = DemoLocale.text("Netflix")
            streaming.category = fun
            streaming.amount = DemoLocale.amount(15.49)
            streaming.date = calendar.date(byAdding: .month, value: -3, to: calendar.date(byAdding: .day, value: 6, to: firstOfMonth) ?? now)
            streaming.day = calendar.startOfDay(for: streaming.wrappedDate)
            streaming.month = calendar.date(from: calendar.dateComponents([.year, .month], from: streaming.wrappedDate))
            streaming.onceRecurring = true
            streaming.recurringType = 3
            streaming.recurringCoefficient = 1
            updateRecurringTransaction(transaction: streaming)

            // `-demoAccounts none` leaves everything in Main, as for someone updating from before accounts.
            if !ProcessInfo.processInfo.arguments.contains("-demoAccounts") {
                seedDemoAccounts(groceries: groceries, shopping: shopping, coffee: coffee, firstOfMonth: firstOfMonth)
                seedDemoGoals(firstOfMonth: firstOfMonth)
            }
            seedDemoBudgets(food: food, groceries: groceries, coffee: coffee, shopping: shopping, health: health)

            // Groceries all go on the card, so limiting its budget to the card shows the account line
            // without changing what it has spent.
            if let budget = groceries.budget, let card = accounts().first(where: { $0.wrappedName == "Card" }) {
                budget.countedAccounts = AccountScope([.account(card)])
            }
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

        func account(_ name: String, symbol: String, order: Int64) -> Account {
            let account = Account(context: context)
            account.id = UUID()
            account.name = name
            account.symbol = symbol
            account.order = order
            account.dateCreated = now
            return account
        }

        let card = account("Card", symbol: "creditcard", order: 0)
        let cash = account("Cash", symbol: "banknote", order: 1)
        let savings = account("Savings", symbol: "building.columns", order: 2)

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

    /// Goals and debts in every state the Budget tab shows: a trip on track for its deadline and saved into every
    /// month by a repeating transfer, an emergency fund without a deadline, a monthly investing goal halfway through
    /// this month, a reached laptop goal and one marked done; a car loan with a rate and monthly payments, a card
    /// owing a balance, and one paid off. Savings stays an everyday account, to convert. `-demoGoals none` leaves
    /// them all out.
    private func seedDemoGoals(firstOfMonth: Date) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demoGoals"), index + 1 < arguments.count, arguments[index + 1] == "none" {
            return
        }

        let calendar = Calendar.current
        let now = Date.now
        let currencyCode = currencyConverter.mainCurrency

        func date(monthsAgo: Int, day: Int, hour: Int = 9) -> Date? {
            guard let month = calendar.date(byAdding: .month, value: -monthsAgo, to: firstOfMonth),
                  let dayOfMonth = calendar.date(byAdding: .day, value: day - 1, to: month),
                  let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayOfMonth),
                  date < now
            else { return nil }
            return date
        }

        /// A transfer from Main on `day` of each month, the latest repeating monthly when `repeats`.
        @discardableResult
        func monthly(_ amount: Double, into account: Account, months: [Int], day: Int, repeats: Bool = false) -> [(outgoing: Transaction, incoming: Transaction)] {
            var legs: [(outgoing: Transaction, incoming: Transaction)] = []
            for monthsAgo in months.sorted(by: >) {
                guard let date = date(monthsAgo: monthsAgo, day: day) else { continue }
                let transfer = saveTransfer(from: .main, to: .account(account), amount: DemoLocale.amount(amount), currencyCode: currencyCode, date: date, note: "")
                legs.append(transfer)
            }
            if repeats, let latest = legs.last?.outgoing {
                latest.recurringType = 3
                latest.recurringCoefficient = 1
                latest.onceRecurring = true
            }
            return legs
        }

        let deadline = calendar.date(byAdding: .month, value: 7, to: firstOfMonth) ?? now

        let trip = addGoal(named: "Japan trip", symbol: "airplane", target: DemoLocale.amount(3_000), repeatsMonthly: false, deadline: deadline, alreadySaved: DemoLocale.amount(600))
        monthly(300, into: trip, months: [0, 1, 2, 3], day: 2, repeats: true)
        if let flights = date(monthsAgo: 0, day: 1, hour: 18) ?? date(monthsAgo: 1, day: 20, hour: 18) {
            _ = insertTransaction(note: "Flights to Tokyo", category: nil, income: false, amount: DemoLocale.amount(420), currencyCode: currencyCode, account: trip, date: flights)
        }
        SavingsReminders.set(2, for: trip)

        let emergency = addGoal(named: "Emergency fund", symbol: "umbrella", target: DemoLocale.amount(6_000), repeatsMonthly: false, deadline: nil, alreadySaved: DemoLocale.amount(2_500))
        monthly(250, into: emergency, months: [0, 1, 2, 3], day: 2)

        let investing = addGoal(named: "Investing", symbol: "chart.line.uptrend.xyaxis", target: DemoLocale.amount(300), repeatsMonthly: true, deadline: nil, alreadySaved: DemoLocale.amount(2_100))
        monthly(300, into: investing, months: [1, 2, 3], day: 1)
        if let thisMonth = date(monthsAgo: 0, day: 1, hour: 10) {
            saveTransfer(from: .main, to: .account(investing), amount: DemoLocale.amount(150), currencyCode: currencyCode, date: thisMonth, note: "")
        }

        addGoal(named: "New laptop", symbol: "star", target: DemoLocale.amount(1_200), repeatsMonthly: false, deadline: nil, alreadySaved: DemoLocale.amount(1_200))

        let concert = addGoal(named: "Concert tickets", symbol: "gift", target: DemoLocale.amount(250), repeatsMonthly: false, deadline: nil, alreadySaved: DemoLocale.amount(250))
        concert.closedAt = now

        let car = addDebt(named: "Car loan", symbol: "car", owed: DemoLocale.amount(7_480), yearlyRate: 6.9, payment: DemoLocale.amount(310))
        car.targetAmount = DemoLocale.amount(12_000)
        for legs in monthly(310, into: car, months: [0, 1, 2], day: 15, repeats: true) {
            logInterest(forPayment: legs.incoming)
        }
        SavingsReminders.set(15, for: car)

        let visa = addDebt(named: "Visa", symbol: "creditcard", owed: DemoLocale.amount(1_340), yearlyRate: 0, payment: 0)
        if let hotel = date(monthsAgo: 0, day: 1, hour: 21) ?? date(monthsAgo: 1, day: 25, hour: 21) {
            _ = insertTransaction(note: "Hotel", category: nil, income: false, amount: DemoLocale.amount(180), currencyCode: currencyCode, account: visa, date: hotel)
        }

        let phone = addDebt(named: "Phone", symbol: "iphone", owed: 0, yearlyRate: 0, payment: 0)
        phone.targetAmount = DemoLocale.amount(900)
        phone.closedAt = now

        save()
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
            let step = DemoLocale.budgetStep
            return max(step, (value / step).rounded(.up) * step)
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
        let coffeeBudget = budget(coffee, type: 2, start: week, amount: DemoLocale.amount(max(5, (spent(coffee, since: week) * 0.75 / DemoLocale.amount(1)).rounded())), order: 2)
        coffeeBudget.rolloverEnabled = true
        coffeeBudget.rolloverAnchor = week
        coffeeBudget.rolloverBalance = DemoLocale.amount(-6)
        budget(shopping, type: 4, start: year, amount: rounded(spent(shopping, since: year) / elapsed(since: year, component: .year, value: 1) * 1.3), order: 3)
        if spent(health, since: month) == 0 {
            budget(health, type: 3, start: month, amount: DemoLocale.amount(60), order: 4)
        }
    }
}
#endif
