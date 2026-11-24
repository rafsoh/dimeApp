//
//  StoreMigrationTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class StoreMigrationTests: XCTestCase {
    private struct TransactionValues: Equatable {
        var amount: Double?
        var note: String?
        var date: Date?
        var day: Date?
        var month: Date?
        var recurringType: Int16?
        var categoryName: String?
    }

    private var directory: URL!

    private var currentModel: NSManagedObjectModel {
        DataController.shared.container.managedObjectModel
    }

    private var earlierModels: [NSManagedObjectModel] {
        StoreSnapshot.modelVersions().filter { $0.entityVersionHashesByName != currentModel.entityVersionHashesByName }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEveryEarlierModelVersionMigratesWithoutLosingData() throws {
        XCTAssertFalse(earlierModels.isEmpty)

        for (index, model) in earlierModels.enumerated() {
            let storeURL = directory.appendingPathComponent("v\(index)", isDirectory: true).appendingPathComponent("Main.sqlite")
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let expected = try writeFixture(to: storeURL, model: model)

            let snapshot = try XCTUnwrap(StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: currentModel, in: StoreSnapshot.directory(forStoreAt: storeURL)))
            XCTAssertEqual(try readTransactions(at: snapshot, model: model), expected, "The snapshot of model \(index) differs from the original")

            XCTAssertEqual(try readTransactions(at: storeURL, model: currentModel), expected, "Migrating model \(index) changed transactions")
            XCTAssertFalse(StoreSnapshot.needsMigration(storeAt: storeURL, to: currentModel))

            let context = try openStore(at: storeURL, model: currentModel)
            XCTAssertEqual(try context.count(for: NSFetchRequest(entityName: "Category")), 3)
            let budgets = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Budget"))
            XCTAssertEqual(budgets.count, 1)
            XCTAssertEqual(budgets.first?.value(forKey: "amount") as? Double, 420.5)
            XCTAssertEqual((budgets.first?.value(forKey: "category") as? NSManagedObject)?.value(forKey: "name") as? String, "Food")
            try close(context)
        }
    }

    func testStoreOnTheCurrentModelIsNotSnapshotted() throws {
        let storeURL = directory.appendingPathComponent("Main.sqlite")
        _ = try writeFixture(to: storeURL, model: currentModel)

        XCTAssertNil(try StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: currentModel, in: StoreSnapshot.directory(forStoreAt: storeURL)))
        XCTAssertTrue(StoreSnapshot.list(in: StoreSnapshot.directory(forStoreAt: storeURL)).isEmpty)
    }

    func testMissingStoreIsNotSnapshotted() throws {
        let storeURL = directory.appendingPathComponent("Main.sqlite")

        XCTAssertNil(try StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: currentModel, in: StoreSnapshot.directory(forStoreAt: storeURL)))
    }

    func testOnlyTheNewestSnapshotsAreKept() throws {
        let model = try XCTUnwrap(earlierModels.first)
        let storeURL = directory.appendingPathComponent("Main.sqlite")
        let snapshots = StoreSnapshot.directory(forStoreAt: storeURL)
        _ = try writeFixture(to: storeURL, model: model)

        for day in 1 ... 5 {
            try StoreSnapshot.snapshotIfMigrationNeeded(storeAt: storeURL, to: currentModel, in: snapshots, at: Date(timeIntervalSince1970: TimeInterval(day * 86400)))
        }

        XCTAssertEqual(StoreSnapshot.list(in: snapshots).map(\.lastPathComponent), ["Main-432000.sqlite", "Main-345600.sqlite", "Main-259200.sqlite"])
    }

    // MARK: - Helpers

    private func openStore(at url: URL, model: NSManagedObjectModel) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentHistoryTrackingKey: true as NSNumber
        ])

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func close(_ context: NSManagedObjectContext) throws {
        let coordinator = try XCTUnwrap(context.persistentStoreCoordinator)

        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }

    // Older models lack some attributes, so only the ones the model has are set.
    private func set(_ object: NSManagedObject, _ values: [String: Any?]) {
        for (key, value) in values where object.entity.propertiesByName[key] != nil {
            object.setValue(value, forKey: key)
        }
    }

    private func writeFixture(to url: URL, model: NSManagedObjectModel) throws -> [UUID: TransactionValues] {
        let context = try openStore(at: url, model: model)
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000.123)

        let categories = [("Food", "🍜", "#FF0000", false), ("Travel", "✈️", "#00FF00", false), ("Salary", "💰", "#0000FF", true)].enumerated().map { order, item in
            let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
            set(category, ["id": UUID(), "name": item.0, "emoji": item.1, "colour": item.2, "income": item.3, "order": Int64(order), "dateCreated": start])
            return category
        }

        var expected: [UUID: TransactionValues] = [:]

        for index in 0 ..< 60 {
            let id = UUID()
            let category = categories[index % categories.count]
            let date = start.addingTimeInterval(TimeInterval(index) * 3_600 * 7)
            let amount = [0.1 + 0.2, 1_234_567.89, 0, 4.5, 1e-7, 99_999_999.99][index % 6]
            let note = index % 5 == 0 ? nil : "Café ☕️ \(index) – \"quoted\""
            let day = calendar.startOfDay(for: date)
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))

            let transaction = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: context)
            set(transaction, [
                "id": id, "amount": amount, "note": note, "date": date, "day": day, "month": month,
                "income": category.value(forKey: "name") as? String == "Salary",
                "onceRecurring": index % 7 == 0, "recurringType": Int16(index % 4), "recurringCoefficient": Int16(1),
                "category": category
            ])

            expected[id] = TransactionValues(amount: amount, note: note, date: date, day: day, month: month, recurringType: Int16(index % 4), categoryName: category.value(forKey: "name") as? String)
        }

        let budget = NSEntityDescription.insertNewObject(forEntityName: "Budget", into: context)
        set(budget, ["id": UUID(), "amount": 420.5, "dateCreated": start, "startDate": start, "type": Int16(2), "green": true, "category": categories[0]])

        try context.save()
        try close(context)
        return expected
    }

    private func readTransactions(at url: URL, model: NSManagedObjectModel) throws -> [UUID: TransactionValues] {
        let context = try openStore(at: url, model: model)
        defer { try? close(context) }

        let transactions = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Transaction"))
        var values: [UUID: TransactionValues] = [:]

        for transaction in transactions {
            let id = try XCTUnwrap(transaction.value(forKey: "id") as? UUID)
            values[id] = TransactionValues(
                amount: transaction.value(forKey: "amount") as? Double,
                note: transaction.value(forKey: "note") as? String,
                date: transaction.value(forKey: "date") as? Date,
                day: transaction.value(forKey: "day") as? Date,
                month: transaction.value(forKey: "month") as? Date,
                recurringType: transaction.value(forKey: "recurringType") as? Int16,
                categoryName: (transaction.value(forKey: "category") as? NSManagedObject)?.value(forKey: "name") as? String
            )
        }

        return values
    }
}
