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
        XCTAssertTrue(budget.rolloverEnabled)
        XCTAssertEqual(budget.rolloverAnchor, Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertEqual(budget.rolloverBalance, -12.5)

        let mainBudget = try XCTUnwrap(all(MainBudget.self, in: target).first)
        XCTAssertEqual(mainBudget.amount, 1_800)
        XCTAssertEqual(mainBudget.type, 3)
        XCTAssertFalse(mainBudget.rolloverEnabled)
        XCTAssertNil(mainBudget.rolloverAnchor)

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
        XCTAssertEqual(json["version"] as? Int, 3)
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
        {"version": 4, "createdAt": 700000000, "categories": [], "transactions": [{"amount": 1, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1}], "budgets": [], "mainBudgets": [], "templates": []}
        """
        let url = directory.appendingPathComponent("backup-700000000-1.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 1)

        let target = try makeContext()
        XCTAssertThrowsError(try BackupStore(directory: directory).restore(backup, into: target))
        XCTAssertFalse(target.hasChanges)
    }

    func testAccountsTransfersAndBudgetScopesRoundTrip() throws {
        let source = try makeContext()
        try populate(source)

        let card = Account(context: source)
        card.id = UUID()
        card.name = "Card"
        card.symbol = "banknote"
        card.order = 0
        let savings = Account(context: source)
        savings.id = UUID()
        savings.name = "Savings"
        savings.order = 1

        let spend = try XCTUnwrap(all(Transaction.self, in: source).first { $0.note == "Café ☕️" })
        spend.account = card

        let transferID = UUID()
        for (income, account) in [(false, nil), (true, savings)] as [(Bool, Account?)] {
            let leg = Transaction(context: source)
            leg.id = UUID()
            leg.amount = 400
            leg.income = income
            leg.date = Date(timeIntervalSinceReferenceDate: 700_100_000)
            leg.day = leg.date
            leg.month = leg.date
            leg.transferID = transferID
            leg.account = account
        }

        let mainBudget = try XCTUnwrap(all(MainBudget.self, in: source).first)
        mainBudget.countedAccounts = AccountScope([.main, .account(card)])
        try XCTUnwrap(all(TemplateTransaction.self, in: source).first).account = savings
        try source.save()

        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source, mainCurrency: nil)

        let target = try makeContext()
        let result = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(result.accounts, 2)
        XCTAssertEqual(try transactionValues(in: target), try transactionValues(in: source))
        XCTAssertEqual(Set(try all(Account.self, in: target).compactMap(\.name)), ["Card", "Savings"])
        // The icon picked is kept; one from before icons is guessed from the name.
        XCTAssertEqual(try all(Account.self, in: target).first { $0.name == "Card" }?.symbol, "banknote")
        XCTAssertEqual(try all(Account.self, in: target).first { $0.name == "Savings" }?.wrappedSymbol, "building.columns")

        let legs = try all(Transaction.self, in: target).filter { $0.transferID == transferID }
        XCTAssertEqual(legs.count, 2)
        XCTAssertNil(legs.first { !$0.income }?.account)
        XCTAssertEqual(legs.first { $0.income }?.account?.name, "Savings")

        let restoredCard = try XCTUnwrap(all(Account.self, in: target).first { $0.name == "Card" })
        XCTAssertEqual(try XCTUnwrap(all(MainBudget.self, in: target).first).countedAccounts, AccountScope([.main, .account(restoredCard)]))
        XCTAssertEqual(try XCTUnwrap(all(TemplateTransaction.self, in: target).first).account?.name, "Savings")
        XCTAssertEqual(try store.restore(backup, into: target).total, 0)
    }

    // A store that lost its accounts but kept one by name reuses it, and the budget scope follows the new id.
    func testRestoreMatchesAccountsByNameAndRemapsScopes() throws {
        let source = try makeContext()
        try populate(source)
        let card = Account(context: source)
        card.id = UUID()
        card.name = "Card"
        try XCTUnwrap(all(Budget.self, in: source).first).countedAccounts = AccountScope([.account(card)])
        try source.save()

        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source)

        let target = try makeContext()
        let recreated = Account(context: target)
        recreated.id = UUID()
        recreated.name = "card"
        try target.save()

        let result = try store.restore(backup, into: target)
        try target.save()

        XCTAssertEqual(result.accounts, 0)
        XCTAssertEqual(try all(Account.self, in: target).count, 1)
        XCTAssertEqual(try XCTUnwrap(all(Budget.self, in: target).first).countedAccounts, AccountScope([.account(recreated)]))
    }

    // A transaction that lost its account, such as to a sync problem, goes back into it. One that's in an account
    // stays where it is, even if the backup had it elsewhere.
    func testRestoreFillsInLostAccountsButNeverMovesTransactions() throws {
        let source = try makeContext()
        try populate(source)
        let card = Account(context: source)
        card.id = UUID()
        card.name = "Card"
        let cash = Account(context: source)
        cash.id = UUID()
        cash.name = "Cash"

        let transactions = try all(Transaction.self, in: source)
        let lost = transactions[0]
        let moved = transactions[1]
        lost.account = card
        moved.account = card
        try source.save()

        let store = BackupStore(directory: directory)
        let backup = try store.write(from: source, mainCurrency: nil)

        lost.account = nil
        moved.account = cash
        try source.save()

        let result = try store.restore(backup, into: source)
        try source.save()

        XCTAssertEqual(result.transactions, 0)
        XCTAssertEqual(result.relinked, 1)
        XCTAssertEqual(lost.account, card)
        XCTAssertEqual(moved.account, cash)
        XCTAssertEqual(try store.restore(backup, into: source).total, 0)
    }

    // Main has no object to restore, so its name comes back in the result for the manager to adopt.
    func testRestoreHandsBackMainsName() throws {
        let json = """
        {
          "version": 3,
          "createdAt": 700000000,
          "categories": [],
          "transactions": [],
          "budgets": [],
          "mainBudgets": [],
          "templates": [],
          "accounts": [],
          "mainAccountName": "Checking",
          "mainAccountSymbol": "building.columns"
        }
        """
        let url = directory.appendingPathComponent("backup-700000000-0.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 0)

        let result = try BackupStore(directory: directory).restore(backup, into: try makeContext())

        XCTAssertEqual(result.mainAccountName, "Checking")
        XCTAssertEqual(result.mainAccountSymbol, "building.columns")
        XCTAssertEqual(result.total, 0)
    }

    // Backups from before accounts put everything in Main.
    func testVersionTwoBackupRestoresIntoMain() throws {
        let json = """
        {
          "version": 2,
          "createdAt": 700000000,
          "categories": [],
          "transactions": [
            {"id": "A1B2C3D4-0000-0000-0000-000000000009", "note": "Taxi", "amount": 3.5, "date": 700000100, "income": false, "onceRecurring": false, "recurringType": 0, "recurringCoefficient": 1, "currencyCode": "EUR"}
          ],
          "budgets": [],
          "mainBudgets": [{"amount": 900, "green": false, "type": 3}],
          "templates": []
        }
        """
        let url = directory.appendingPathComponent("backup-700000000-1.json")
        try Data(json.utf8).write(to: url)
        let backup = BackupSummary(url: url, createdAt: Date(timeIntervalSince1970: 700_000_000), transactionCount: 1)

        let target = try makeContext()
        let result = try BackupStore(directory: directory).restore(backup, into: target)
        try target.save()

        XCTAssertEqual(result.transactions, 1)
        XCTAssertEqual(result.accounts, 0)
        let taxi = try XCTUnwrap(all(Transaction.self, in: target).first)
        XCTAssertNil(taxi.account)
        XCTAssertNil(taxi.transferID)
        XCTAssertTrue(try XCTUnwrap(all(MainBudget.self, in: target).first).countedAccounts.isAll)
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
        budget.rolloverEnabled = true
        budget.rolloverAnchor = Date(timeIntervalSinceReferenceDate: 700_000_000)
        budget.rolloverBalance = -12.5

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
            "\($0.id!)|\($0.amount)|\($0.note ?? "nil")|\($0.date!.timeIntervalSinceReferenceDate)|\($0.day!.timeIntervalSinceReferenceDate)|\($0.month!.timeIntervalSinceReferenceDate)|\($0.income)|\($0.onceRecurring)|\($0.recurringType)|\($0.recurringCoefficient)|\($0.category?.name ?? "nil")|\($0.currencyCode ?? "nil")|\($0.account?.name ?? "main")|\($0.transferID?.uuidString ?? "nil")"
        }.sorted()
    }

    private func categoryValues(in context: NSManagedObjectContext) throws -> [String] {
        try all(Category.self, in: context).map {
            "\($0.id!)|\($0.name ?? "")|\($0.emoji ?? "")|\($0.colour ?? "")|\($0.income)|\($0.order)"
        }.sorted()
    }
}
