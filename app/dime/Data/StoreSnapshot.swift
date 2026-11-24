//
//  StoreSnapshot.swift
//  dime
//

import CoreData
import Foundation

// Before Core Data migrates the store to a newer model, a copy of the untouched file is kept so the data can
// still be recovered by hand if the migration goes wrong. JSON backups can't do this: they need the store open.
enum StoreSnapshot {
    enum SnapshotError: Error {
        case unknownSourceModel
    }

    static let maximumCount = 3

    static func directory(forStoreAt storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("PreMigrationSnapshots", isDirectory: true)
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
    static func modelVersions(named name: String = "MainModel", in bundle: Bundle = Bundle(for: DataController.self)) -> [NSManagedObjectModel] {
        guard let directory = bundle.url(forResource: name, withExtension: "momd"),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return []
        }

        return urls.filter { $0.pathExtension == "mom" }.compactMap(NSManagedObjectModel.init(contentsOf:))
    }

    // Call before loading the store. Returns the snapshot's location, or nil when no migration is pending.
    @discardableResult
    static func snapshotIfMigrationNeeded(storeAt storeURL: URL, to model: NSManagedObjectModel, sourceModels: [NSManagedObjectModel] = modelVersions(), in directory: URL, at date: Date = .now) throws -> URL? {
        guard needsMigration(storeAt: storeURL, to: model) else {
            return nil
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)

        guard let sourceModel = sourceModels.first(where: { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }) else {
            throw SnapshotError.unknownSourceModel
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("Main-\(Int(date.timeIntervalSince1970)).sqlite")
        let options: [AnyHashable: Any] = [NSPersistentHistoryTrackingKey: true as NSNumber]

        // A SQLite-level copy that folds in the write-ahead log, unlike copying the files.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: sourceModel)
        try coordinator.replacePersistentStore(at: destination, destinationOptions: options, withPersistentStoreFrom: storeURL, sourceOptions: options, ofType: NSSQLiteStoreType)

        prune(directory, keeping: destination)
        return destination
    }

    static func list(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        return urls
            .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("Main-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    private static func prune(_ directory: URL, keeping newest: URL) {
        for url in list(in: directory).filter({ $0 != newest }).dropFirst(maximumCount - 1) {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
    }
}
