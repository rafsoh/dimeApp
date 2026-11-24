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
}
