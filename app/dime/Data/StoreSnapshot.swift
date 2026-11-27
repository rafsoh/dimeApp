//
//  StoreSnapshot.swift
//  dime
//

import CoreData
import Foundation
import SQLite3

// Before Core Data migrates the store to a newer model, a copy of the untouched file is kept so the data can
// still be recovered by hand if the migration goes wrong. JSON backups can't do this: they need the store open.
enum StoreSnapshot {
    enum SnapshotError: Error {
        case unknownSourceModel
        /// Too little free space for a copy and the migration after it. Copying would only use up the
        /// space the migration needs, and a migration that runs out of space can't open the store at all.
        case notEnoughSpace
    }

    /// Room for a copy of the store and its write-ahead log, and as much again for the migration.
    static func bytesNeededForSnapshot(storeAt storeURL: URL) -> Int64 {
        func size(_ url: URL) -> Int64 {
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        let store = size(storeURL) + size(URL(fileURLWithPath: storeURL.path + "-wal"))
        return store * 2 + 20 * 1024 * 1024
    }

    /// Free space on the store's volume, or nil when it can't be read.
    static func availableCapacity(forStoreAt storeURL: URL) -> Int64? {
        let values = try? storeURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private final class CountBox {
        var values: [String: Int] = [:]
        var failed = false
    }

    static let maximumCount = 3

    static func directory(forStoreAt storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("PreMigrationSnapshots", isDirectory: true)
    }

    /// The model the file was written with, when one of the shipped versions matches its metadata.
    static func sourceModel(forStoreAt storeURL: URL, among models: [NSManagedObjectModel] = modelVersions()) -> NSManagedObjectModel? {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        else {
            return nil
        }

        return models.first { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }
    }

    /// Counts rows without migrating. The model has to be one the file can open as-is.
    /// Keys are fixed (`transactions`, `categories`, …) and values are counts, never record contents.
    static func recordCounts(storeAt storeURL: URL, model: NSManagedObjectModel) -> [String: Int]? {
        let names = [
            "Transaction": "transactions",
            "Category": "categories",
            "Budget": "budgets",
            "MainBudget": "mainBudgets",
            "TemplateTransaction": "templates",
            "Account": "accounts"
        ]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        do {
            let store = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [
                    NSReadOnlyPersistentStoreOption: true as NSNumber,
                    NSMigratePersistentStoresAutomaticallyOption: false as NSNumber,
                    NSInferMappingModelAutomaticallyOption: false as NSNumber
                ]
            )
            defer { try? coordinator.remove(store) }

            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let counts = CountBox()

            context.performAndWait {
                for (entityName, key) in names where model.entitiesByName[entityName] != nil {
                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    do {
                        counts.values[key] = try context.count(for: request)
                    } catch {
                        counts.failed = true
                    }
                }
            }

            return counts.failed ? nil : counts.values
        } catch {
            return nil
        }
    }

    static func needsMigration(storeAt storeURL: URL, to model: NSManagedObjectModel) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        else {
            return false
        }

        return !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }

    // Every version in the compiled model bundle, so the store can be opened with the model it was written by.
    //
    // Their entities are plain NSManagedObject. Each version otherwise also claims Transaction, Category and the
    // other app classes, and while more than one model claiming a class is alive, +[Transaction entity] can't
    // pick one and returns nil. Every @FetchRequest built from sort descriptors then crashes with "A fetch
    // request must have an entity", which is what happened on the first launch after a migration.
    // Class names aren't part of the version hashes, so these still match the store's metadata.
    static func modelVersions(named name: String = "MainModel", in bundle: Bundle = Bundle(for: DataController.self)) -> [NSManagedObjectModel] {
        guard let directory = bundle.url(forResource: name, withExtension: "momd"),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return []
        }

        let models = urls.filter { $0.pathExtension == "mom" }.compactMap(NSManagedObjectModel.init(contentsOf:))
        let genericClassName = NSStringFromClass(NSManagedObject.self)

        for model in models {
            for entity in model.entities {
                entity.managedObjectClassName = genericClassName
            }
        }

        return models
    }

    // Call before loading the store. Returns the snapshot's location, or nil when no migration is pending.
    // `copiedBySQLite` is told when Core Data refused the copy and SQLite made it instead, with Core Data's error.
    @discardableResult
    static func snapshotIfMigrationNeeded(storeAt storeURL: URL, to model: NSManagedObjectModel, sourceModels: [NSManagedObjectModel] = modelVersions(), in directory: URL, at date: Date = .now, copiedBySQLite: ((Error) -> Void)? = nil) throws -> URL? {
        guard needsMigration(storeAt: storeURL, to: model) else {
            return nil
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)

        guard let sourceModel = sourceModels.first(where: { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }) else {
            throw SnapshotError.unknownSourceModel
        }

        let needed = bytesNeededForSnapshot(storeAt: storeURL)

        if let available = availableCapacity(forStoreAt: storeURL), available < needed {
            // Older copies are the first space to give back. The newest stays, since it's the last copy
            // of the data from before a migration.
            if let newest = list(in: directory).first {
                prune(directory, keeping: newest, maximum: 1)
            }

            if let available = availableCapacity(forStoreAt: storeURL), available < needed {
                throw SnapshotError.notEnoughSpace
            }
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("Main-\(Int(date.timeIntervalSince1970)).sqlite")
        let options: [AnyHashable: Any] = [NSPersistentHistoryTrackingKey: true as NSNumber]

        // A SQLite-level copy that folds in the write-ahead log, unlike copying the files.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: sourceModel)

        do {
            try coordinator.replacePersistentStore(at: destination, destinationOptions: options, withPersistentStoreFrom: storeURL, sourceOptions: options, ofType: NSSQLiteStoreType)
        } catch {
            // A copy cut short (for one, by a full disk) is useless and holds space the migration needs.
            removeFiles(of: destination)

            // Core Data has refused a store it had just counted, with NSCocoaErrorDomain 134000 (DIME-IOS-P),
            // leaving no copy before the migration. SQLite's own backup reads the same file through its
            // write-ahead log. Out of space, it would only fail the same way.
            guard !DataIntegrityLog.isOutOfSpace(error) else {
                throw error
            }

            do {
                try copyWithSQLite(from: storeURL, to: destination)
            } catch let copyError {
                removeFiles(of: destination)
                let sqliteError = copyError as NSError

                // Core Data's error is the one reported, with SQLite's result code beneath it.
                let coreDataError = error as NSError
                var underlyingInfo: [String: Any] = [:]
                underlyingInfo[NSUnderlyingErrorKey] = coreDataError.userInfo[NSUnderlyingErrorKey]
                var userInfo = coreDataError.userInfo
                userInfo[NSUnderlyingErrorKey] = NSError(domain: sqliteError.domain, code: sqliteError.code, userInfo: underlyingInfo)
                throw NSError(domain: coreDataError.domain, code: coreDataError.code, userInfo: userInfo)
            }

            copiedBySQLite?(error)
        }

        prune(directory, keeping: destination)
        return destination
    }

    /// Copies the database with SQLite's online backup, write-ahead log included, into a new file.
    static func copyWithSQLite(from source: URL, to destination: URL) throws {
        var sourceDatabase: OpaquePointer?
        var destinationDatabase: OpaquePointer?
        defer {
            sqlite3_close(sourceDatabase)
            sqlite3_close(destinationDatabase)
        }

        func failure(_ code: Int32) -> NSError {
            NSError(domain: NSSQLiteErrorDomain, code: Int(code))
        }

        var result = sqlite3_open_v2(source.path, &sourceDatabase, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else { throw failure(result) }

        result = sqlite3_open_v2(destination.path, &destinationDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK else { throw failure(result) }

        guard let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
            throw failure(sqlite3_errcode(destinationDatabase))
        }

        // Every page in one step, so a write from another process can't restart the copy halfway.
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)

        guard step == SQLITE_DONE else { throw failure(step) }
        guard finish == SQLITE_OK else { throw failure(finish) }
    }

    static func list(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        return urls
            .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("Main-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    private static func removeFiles(of storeURL: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private static func prune(_ directory: URL, keeping newest: URL, maximum: Int = maximumCount) {
        for url in list(in: directory).filter({ $0 != newest }).dropFirst(maximum - 1) {
            removeFiles(of: url)
        }
    }
}
