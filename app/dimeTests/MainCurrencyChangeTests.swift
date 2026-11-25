//
//  MainCurrencyChangeTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class MainCurrencyChangeTests: XCTestCase {
    private func makeContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataController.shared.container.managedObjectModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func insert(_ codes: [String?], into context: NSManagedObjectContext) throws {
        let category = Category(context: context)
        category.id = UUID()
        category.name = "Food"

        for (index, code) in codes.enumerated() {
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = Double(index) + 0.25
            transaction.note = "Row \(index)"
            transaction.date = Date(timeIntervalSinceReferenceDate: 700_000_000 + Double(index) * 3_600)
            transaction.income = index % 5 == 0
            transaction.currencyCode = code
            transaction.category = index.isMultiple(of: 2) ? category : nil
        }

        try context.save()
    }

    private func snapshot(_ context: NSManagedObjectContext) throws -> [String] {
        try context.fetch(NSFetchRequest<Transaction>(entityName: "Transaction")).map {
            "\($0.id!)|\($0.amount)|\($0.note ?? "")|\($0.date!.timeIntervalSinceReferenceDate)|\($0.income)|\($0.category?.name ?? "nil")"
        }.sorted()
    }

    private func codes(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]

        for transaction in try context.fetch(NSFetchRequest<Transaction>(entityName: "Transaction")) {
            counts[transaction.currencyCode ?? "nil", default: 0] += 1
        }

        return counts
    }

    func testRelabelOnlyRewritesTheOldCurrency() throws {
        let context = try makeContext()
        try insert([nil, nil, nil, "USD", "usd", "USD", "USD", "EUR", "EUR"], into: context)
        let before = try snapshot(context)
        let plan = MainCurrencyChangePlan(kind: .relabel, oldCurrency: "USD", newCurrency: "SGD")

        XCTAssertEqual(try MainCurrencyChanger.count(plan, in: context), 4)
        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context), 4)
        XCTAssertEqual(try codes(context), ["nil": 3, "SGD": 4, "EUR": 2])
        XCTAssertEqual(try snapshot(context), before)
        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context), 0)
    }

    func testConvertOnlyLabelsTransactionsWithoutACurrency() throws {
        let context = try makeContext()
        try insert([nil, nil, nil, "USD", "EUR", "EUR"], into: context)
        let before = try snapshot(context)
        let plan = MainCurrencyChangePlan(kind: .convert, oldCurrency: "USD", newCurrency: "SGD")

        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context), 3)
        XCTAssertEqual(try codes(context), ["USD": 4, "EUR": 2])
        XCTAssertEqual(try snapshot(context), before)
        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context), 0)
    }

    func testTemplatesFollowTheSameRuleAsTransactions() throws {
        for (kind, expected) in [(MainCurrencyChangePlan.Kind.relabel, ["nil", "SGD", "SGD", "EUR"]), (.convert, ["USD", "USD", "USD", "EUR"])] {
            let context = try makeContext()

            for (index, code) in [nil, "USD", "usd", "EUR"].enumerated() {
                let template = TemplateTransaction(context: context)
                template.id = UUID()
                template.order = Int16(index)
                template.amount = 5
                template.currencyCode = code
            }
            try context.save()

            try MainCurrencyChanger.applyToTemplates(MainCurrencyChangePlan(kind: kind, oldCurrency: "USD", newCurrency: "SGD"), in: context)

            let request = NSFetchRequest<TemplateTransaction>(entityName: "TemplateTransaction")
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
            XCTAssertEqual(try context.fetch(request).map { $0.currencyCode ?? "nil" }, expected, "\(kind)")
        }
    }

    func testChangesInBatchesAndResumesAfterAnInterruption() throws {
        let context = try makeContext()
        try insert(Array(repeating: nil, count: 1_234) + ["EUR"], into: context)
        let before = try snapshot(context)
        let plan = MainCurrencyChangePlan(kind: .convert, oldCurrency: "USD", newCurrency: "JPY")

        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context, batchSize: 500, maximumBatches: 1), 500)
        XCTAssertEqual(try codes(context), ["nil": 734, "USD": 500, "EUR": 1])

        XCTAssertEqual(try MainCurrencyChanger.apply(plan, in: context, batchSize: 500), 734)
        XCTAssertEqual(try codes(context), ["USD": 1_234, "EUR": 1])
        XCTAssertEqual(try snapshot(context), before)
    }

    func testPlansSurviveBeingStored() throws {
        let plan = MainCurrencyChangePlan(kind: .relabel, oldCurrency: "USD", newCurrency: "EUR")
        let decoded = try JSONDecoder().decode(MainCurrencyChangePlan.self, from: JSONEncoder().encode(plan))

        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.target, "EUR")
        XCTAssertEqual(MainCurrencyChangePlan(kind: .convert, oldCurrency: "USD", newCurrency: "EUR").target, "USD")
    }

    func testNewTransactionsNameTheirCurrency() throws {
        let dataController = DataController.shared
        let transaction = dataController.insertTransaction(note: "Coffee", category: nil, income: false, amount: 4.5, date: .now)
        defer { dataController.container.viewContext.delete(transaction) }

        XCTAssertEqual(transaction.currencyCode, dataController.currencyForNewTransaction())
        XCTAssertNotNil(transaction.currencyCode)

        let foreign = dataController.insertTransaction(note: "Ramen", category: nil, income: false, amount: 1_200, currencyCode: "JPY", date: .now)
        defer { dataController.container.viewContext.delete(foreign) }
        XCTAssertEqual(foreign.currencyCode, "JPY")
    }

    func testExportNamesEveryTransactionsCurrency() throws {
        let context = DataController.shared.container.viewContext
        let legacy = Transaction(context: context)
        legacy.note = "Lunch, with Sam"
        legacy.amount = 12.5
        legacy.date = Date(timeIntervalSince1970: 1_700_000_000)
        let foreign = Transaction(context: context)
        foreign.note = "Taxi"
        foreign.amount = 1.25
        foreign.currencyCode = "kwd"
        foreign.date = Date(timeIntervalSince1970: 1_700_000_100)
        defer { [legacy, foreign].forEach(context.delete) }

        let lines = ExportCSV.text(for: [legacy, foreign], mainCurrency: "usd").split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, "Date,Note,Amount,Category,Type,Currency")
        XCTAssertTrue(lines[1].hasSuffix(",Taxi,1.250,,Expense,KWD"), lines[1])
        XCTAssertTrue(lines[2].hasSuffix(",\"Lunch, with Sam\",12.50,,Expense,USD"), lines[2])
    }

    // A recurring transaction from before currencies existed must not pass its missing currency on.
    func testOccurrencesOfALegacyRecurringTransactionNameTheMainCurrency() throws {
        let dataController = DataController.shared
        let context = dataController.container.viewContext
        let note = "Gym \(UUID().uuidString)"

        let parent = Transaction(context: context)
        parent.id = UUID()
        parent.note = note
        parent.amount = 30
        parent.date = Calendar.current.date(byAdding: .day, value: -3, to: .now)
        parent.day = parent.date
        parent.month = parent.date
        parent.recurringType = 1
        parent.recurringCoefficient = 1
        XCTAssertNil(parent.currencyCode)

        XCTAssertTrue(dataController.updateRecurringTransaction(transaction: parent))

        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "note == %@", note)
        let rows = try context.fetch(request)
        defer {
            rows.forEach(context.delete)
            dataController.save()
        }

        let occurrences = rows.filter { $0 != parent }
        XCTAssertFalse(occurrences.isEmpty)
        XCTAssertTrue(occurrences.allSatisfy { $0.currencyCode == dataController.currencyConverter.mainCurrency })
        XCTAssertNil(parent.currencyCode)
    }

    // A Shortcut or automation that names no currency must not pick up one last used on a trip.
    func testTransactionsWithoutAChosenCurrencyUseTheMainOne() throws {
        let dataController = DataController.shared
        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let savedRecent = defaults?.object(forKey: CurrencyPreferences.recentCurrenciesKey)
        defer { defaults?.set(savedRecent, forKey: CurrencyPreferences.recentCurrenciesKey) }

        let main = dataController.currencyConverter.mainCurrency
        let foreignCode = main == "JPY" ? "EUR" : "JPY"
        defaults?.set([foreignCode], forKey: CurrencyPreferences.recentCurrenciesKey)

        let transaction = dataController.insertTransaction(note: "Automation", category: nil, income: false, amount: 9, date: .now)
        defer { dataController.container.viewContext.delete(transaction) }

        XCTAssertEqual(transaction.currencyCode, main)
        XCTAssertEqual(dataController.currencyForNewEntry(), foreignCode)
    }
}
