//
//  BackupRoundTripTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class BackupRoundTripTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRestoringIntoAnEmptyStoreRecreatesEverything() throws {
        let source = try makeContext()
        try populate(source)
        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source, mainCurrency: nil)

        let target = try makeContext()
        let result = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(result.transactions, 3)
        XCTAssertEqual(result.categories, 2)
        XCTAssertEqual(result.budgets, 2)
        XCTAssertEqual(result.templates, 1)
        XCTAssertEqual(try transactionValues(in: target), try transactionValues(in: source))
        XCTAssertEqual(try categoryValues(in: target), try categoryValues(in: source))

        let budget = try XCTUnwrap(all(Budget.self, in: target).first)
        XCTAssertEqual(budget.amount, 250.75)
        XCTAssertEqual(budget.type, 2)
        XCTAssertEqual(budget.category?.name, "Food")

        let mainBudget = try XCTUnwrap(all(MainBudget.self, in: target).first)
        XCTAssertEqual(mainBudget.amount, 1_800)
        XCTAssertEqual(mainBudget.type, 3)

        let template = try XCTUnwrap(all(TemplateTransaction.self, in: target).first)
        XCTAssertEqual(template.amount, 12.5)
        XCTAssertEqual(template.note, "Lunch")
        XCTAssertEqual(template.category?.name, "Food")
        XCTAssertEqual(template.currencyCode, "EUR")
    }

    func testRestoringTwiceAddsNothingTheSecondTime() throws {
        let source = try makeContext()
        try populate(source)
        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source)

        let target = try makeContext()
        _ = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(try store.restore(backup, into: target).total, 0)
    }

    func testRestoringNeverChangesExistingTransactions() throws {
        let source = try makeContext()
        try populate(source)
        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source)

        let target = try makeContext()
        let original = try XCTUnwrap(all(Transaction.self, in: source).first)
        let edited = Transaction(context: target)
        edited.id = original.id
        edited.amount = 999
        edited.note = "Edited after the backup"
        try target.save()

        _ = try store.restore(backup, into: target)

        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "id == %@", try XCTUnwrap(original.id) as CVarArg)
        let matches = try target.fetch(request)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.amount, 999)
        XCTAssertEqual(matches.first?.note, "Edited after the backup")
    }

    // A backup written by the version 1 format must keep restoring as the format grows.
    func testVersionOneBackupRestores() throws {
        let json = """
        {
          "version": 1,
          "createdAt": 700000000,
          "categories": [
            {"ref": "A1B2C3D4-0000-0000-0000-000000000001", "id": "A1B2C3D4-0000-0000-0000-000000000001", "name": "Food", "emoji": "🍜", "colour": "#FF0000", "income": false, "order": 0, "dateCreated": 700000000}
          ],
          "transactions": [
            {"id": "A1B2C3D4-0000-0000-0000-000000000002", "note": "Ramen", "amount": 18.4, "date": 700000100, "day": 699984000, "month": 699408000, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1, "categoryRef": "A1B2C3D4-0000-0000-0000-000000000001"},
            {"amount": 3.5, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1}
          ],
          "budgets": [
            {"id": "A1B2C3D4-0000-0000-0000-000000000003", "amount": 300, "green": true, "type": 3, "categoryRef": "A1B2C3D4-0000-0000-0000-000000000001"}
          ],
          "mainBudgets": [
            {"amount": 2000, "green": false, "type": 3}
          ],
          "templates": [
            {"amount": 5, "income": false, "order": 0, "recurringCoefficient": 0, "recurringType": 0}
          ]
        }
        """
        let url = directory.appendingPathComponent("backup-700000000-2.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 2)

        let target = try makeContext()
        let result = try BackupStore(directory: directory).restore(backup, into: target)
        try target.save()

        XCTAssertEqual(result.transactions, 2)
        XCTAssertEqual(result.categories, 1)
        XCTAssertEqual(result.budgets, 2)
        XCTAssertEqual(result.templates, 1)

        let ramen = try XCTUnwrap(all(Transaction.self, in: target).first { $0.note == "Ramen" })
        XCTAssertEqual(ramen.amount, 18.4)
        XCTAssertEqual(ramen.category?.name, "Food")
        XCTAssertEqual(ramen.date, Date(timeIntervalSinceReferenceDate: 700_000_100))
        XCTAssertTrue(try all(Transaction.self, in: target).allSatisfy { $0.currencyCode == nil })
        XCTAssertNil(try XCTUnwrap(all(TemplateTransaction.self, in: target).first).currencyCode)
    }

    func testVersionTwoBackupKeepsTheCurrency() throws {
        let source = try makeContext()
        try populate(source)
        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source, mainCurrency: nil)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: backup.url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        let codes = try XCTUnwrap(json["transactions"] as? [[String: Any]]).map { $0["currencyCode"] as? String }
        XCTAssertEqual(codes.compactMap { $0 }.sorted(), ["EUR", "JPY"])

        let target = try makeContext()
        _ = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(try transactionValues(in: target), try transactionValues(in: source))
        XCTAssertEqual(try all(Transaction.self, in: target).compactMap(\.currencyCode).sorted(), ["EUR", "JPY"])
    }

    // Restored after the main currency changed, a transaction without one must keep meaning the old main currency.
    func testRestoreGivesTransactionsWithoutACurrencyTheBackupsMainCurrency() throws {
        let source = try makeContext()
        try populate(source)
        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source, mainCurrency: "usd")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: backup.url)) as? [String: Any])
        XCTAssertEqual(json["mainCurrency"] as? String, "USD")

        let target = try makeContext()
        _ = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(try all(Transaction.self, in: target).compactMap(\.currencyCode).sorted(), ["EUR", "JPY", "USD"])
    }

    // A transaction from a version that didn't assign ids still matches its backup copy, whatever its currency.
    func testIdLessTransactionsStillMatchByContent() throws {
        let json = """
        {
          "version": 2,
          "createdAt": 700000000,
          "categories": [],
          "transactions": [
            {"note": "Taxi", "amount": 3.5, "date": 700000100, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1, "currencyCode": "EUR"}
          ],
          "budgets": [],
          "mainBudgets": [],
          "templates": []
        }
        """
        let url = directory.appendingPathComponent("backup-700000000-1.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 1)

        let target = try makeContext()
        let existing = Transaction(context: target)
        existing.note = "Taxi"
        existing.amount = 3.5
        existing.date = Date(timeIntervalSinceReferenceDate: 700_000_100)
        try target.save()

        XCTAssertEqual(try BackupStore(directory: directory).restore(backup, into: target).transactions, 0)
        XCTAssertNil(existing.currencyCode)
    }

    func testBackupFromANewerFormatIsNotRestored() throws {
        let json = """
        {"version": 3, "createdAt": 700000000, "categories": [], "transactions": [{"amount": 1, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1}], "budgets": [], "mainBudgets": [], "templates": []}
        """
        let url = directory.appendingPathComponent("backup-700000000-1.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 1)

        let target = try makeContext()
        XCTAssertThrowsError(try BackupStore(directory: directory).restore(backup, into: target))
        XCTAssertFalse(target.hasChanges)
    }

    // MARK: - Helpers

    private func makeContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataController.shared.container.managedObjectModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func all<T: NSManagedObject>(_: T.Type, in context: NSManagedObjectContext) throws -> [T] {
        try context.fetch(NSFetchRequest<T>(entityName: String(describing: T.self)))
    }

    private func populate(_ context: NSManagedObjectContext) throws {
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000.5)

        let food = Category(context: context)
        food.id = UUID()
        food.name = "Food"
        food.emoji = "🍜"
        food.colour = "#FF0000"
        food.order = 0
        food.dateCreated = start

        let salary = Category(context: context)
        salary.id = UUID()
        salary.name = "Salary"
        salary.emoji = "💰"
        salary.colour = "#0000FF"
        salary.income = true
        salary.order = 1
        salary.dateCreated = start

        let rows: [(Double, String?, dime.Category, String?)] = [(0.1 + 0.2, "Café ☕️", food, "EUR"), (5_000, "Pay", salary, nil), (1_200, nil, food, "JPY")]

        for (index, (amount, note, category, currencyCode)) in rows.enumerated() {
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = amount
            transaction.currencyCode = currencyCode
            transaction.note = note
            transaction.date = start.addingTimeInterval(TimeInterval(index) * 86400)
            transaction.day = transaction.date
            transaction.month = start
            transaction.income = category.income
            transaction.onceRecurring = index == 2
            transaction.recurringType = Int16(index)
            transaction.recurringCoefficient = 1
            transaction.category = category
        }

        let budget = Budget(context: context)
        budget.id = UUID()
        budget.amount = 250.75
        budget.type = 2
        budget.green = true
        budget.startDate = start
        budget.dateCreated = start
        budget.category = food

        let mainBudget = MainBudget(context: context)
        mainBudget.amount = 1_800
        mainBudget.type = 3
        mainBudget.startDate = start

        let template = TemplateTransaction(context: context)
        template.id = UUID()
        template.amount = 12.5
        template.note = "Lunch"
        template.order = 0
        template.category = food
        template.currencyCode = "EUR"

        try context.save()
    }

    private func transactionValues(in context: NSManagedObjectContext) throws -> [String] {
        try all(Transaction.self, in: context).map {
            "\($0.id!)|\($0.amount)|\($0.note ?? "nil")|\($0.date!.timeIntervalSinceReferenceDate)|\($0.day!.timeIntervalSinceReferenceDate)|\($0.month!.timeIntervalSinceReferenceDate)|\($0.income)|\($0.onceRecurring)|\($0.recurringType)|\($0.recurringCoefficient)|\($0.category?.name ?? "nil")|\($0.currencyCode ?? "nil")"
        }.sorted()
    }

    private func categoryValues(in context: NSManagedObjectContext) throws -> [String] {
        try all(Category.self, in: context).map {
            "\($0.id!)|\($0.name ?? "")|\($0.emoji ?? "")|\($0.colour ?? "")|\($0.income)|\($0.order)"
        }.sorted()
    }
}
