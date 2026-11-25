//
//  QuickAddTemplateTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class QuickAddTemplateTests: XCTestCase {
    private let dataController = DataController.shared
    private var context: NSManagedObjectContext { dataController.container.viewContext }
    private var category: dime.Category!

    override func setUpWithError() throws {
        try removeAll()

        category = Category(context: context)
        category.id = UUID()
        category.name = "Coffee"
        category.emoji = "☕️"
        category.order = 99
        try context.save()
    }

    override func tearDownWithError() throws {
        try removeAll()
        context.delete(category)
        try context.save()
    }

    func testAddingFromATransactionCopiesItsDetailsWithoutLinkingThem() throws {
        let source = makeTransaction(note: "Flat white", amount: 4.5, currencyCode: "EUR")

        let template = try XCTUnwrap(dataController.addQuickAddTemplate(from: source))
        XCTAssertEqual(template.note, "Flat white")
        XCTAssertEqual(template.amount, 4.5)
        XCTAssertEqual(template.currencyCode, "EUR")
        XCTAssertEqual(template.category, category)
        XCTAssertFalse(template.income)
        XCTAssertNotNil(template.id)

        source.amount = 6
        dataController.save()
        XCTAssertEqual(template.amount, 4.5)
    }

    func testLoggingATemplateMakesAnUnlinkedTransaction() throws {
        let template = try XCTUnwrap(dataController.addQuickAddTemplate(from: makeTransaction(note: "Flat white", amount: 4.5, currencyCode: "EUR")))

        let logged = dataController.logQuickAddTemplate(template)
        XCTAssertEqual(logged.note, "Flat white")
        XCTAssertEqual(logged.amount, 4.5)
        XCTAssertEqual(logged.currencyCode, "EUR")
        XCTAssertEqual(logged.category, category)
        XCTAssertEqual(logged.recurringType, 0)
        XCTAssertEqual(logged.wrappedDate.timeIntervalSinceNow, 0, accuracy: 60)

        template.amount = 9
        dataController.save()
        XCTAssertEqual(logged.amount, 4.5)

        dataController.deleteQuickAddTemplate(template)
        XCTAssertFalse(logged.isDeleted)
        XCTAssertEqual(try context.count(for: fetchRequest(Transaction.self, note: "Flat white")), 2)
    }

    func testATemplateWithoutACurrencyLogsInTheMainCurrency() throws {
        let template = try XCTUnwrap(dataController.addQuickAddTemplate(from: makeTransaction(note: "Bus", amount: 2.9, currencyCode: nil)))
        XCTAssertNil(template.currencyCode)

        XCTAssertEqual(dataController.logQuickAddTemplate(template).currencyCode, CurrencyConverter.current().mainCurrency)
    }

    func testThereAreNeverMoreThanFourTemplates() throws {
        let source = makeTransaction(note: "Lunch", amount: 12, currencyCode: nil)

        for _ in 0 ..< TemplateTransaction.quickAddLimit {
            XCTAssertNotNil(dataController.addQuickAddTemplate(from: source))
        }

        XCTAssertFalse(dataController.canAddQuickAddTemplate)
        XCTAssertNil(dataController.addQuickAddTemplate(from: source))
        XCTAssertEqual(dataController.quickAddTemplates().count, TemplateTransaction.quickAddLimit)
    }

    func testDeletingATemplateKeepsTheRestInOrderFromZero() throws {
        let templates = try ["A", "B", "C"].map { note in
            try XCTUnwrap(dataController.addQuickAddTemplate(from: makeTransaction(note: note, amount: 1, currencyCode: nil)))
        }
        XCTAssertEqual(templates.map(\.order), [0, 1, 2])

        dataController.deleteQuickAddTemplate(templates[0])

        let remaining = dataController.quickAddTemplates()
        XCTAssertEqual(remaining.map(\.wrappedNote), ["B", "C"])
        XCTAssertEqual(remaining.map(\.order), [0, 1])
        XCTAssertEqual(dataController.nextQuickAddOrder, 2)
    }

    func testAWidgetButtonFindsItsTemplateUntilItIsDeleted() throws {
        let template = try XCTUnwrap(dataController.addQuickAddTemplate(from: makeTransaction(note: "Bus", amount: 2.9, currencyCode: nil)))
        let uri = template.objectID.uriRepresentation()

        XCTAssertEqual(dataController.quickAddTemplate(withURI: uri), template)

        dataController.deleteQuickAddTemplate(template)
        XCTAssertNil(dataController.quickAddTemplate(withURI: uri))
    }

    func testATemplateWithoutANoteIsNamedAfterItsCategoryOrItsType() {
        let template = TemplateTransaction(context: context)
        template.category = category
        XCTAssertEqual(template.displayTitle, "Coffee")

        template.category = nil
        XCTAssertEqual(template.displayTitle, String(localized: "Expense"))

        template.income = true
        XCTAssertEqual(template.displayTitle, String(localized: "Income"))

        context.delete(template)
    }

    private func makeTransaction(note: String, amount: Double, currencyCode: String?) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.note = note
        transaction.amount = amount
        transaction.currencyCode = currencyCode
        transaction.category = category
        transaction.date = Date.now.addingTimeInterval(-3600)
        return transaction
    }

    private func fetchRequest<T: NSManagedObject>(_: T.Type, note: String) -> NSFetchRequest<T> {
        let request = NSFetchRequest<T>(entityName: String(describing: T.self))
        request.predicate = NSPredicate(format: "note == %@", note)
        return request
    }

    /// Clears templates, and transactions these tests made, from the shared in-memory store.
    private func removeAll() throws {
        try context.fetch(TemplateTransaction.fetchRequest() as NSFetchRequest<TemplateTransaction>).forEach(context.delete)

        if let category {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category)
            try context.fetch(request).forEach(context.delete)
        }

        try context.save()
    }
}
