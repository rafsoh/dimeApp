//
//  DeleteCategoryTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

final class DeleteCategoryTests: XCTestCase {
    private let dataController = DataController.shared
    private var context: NSManagedObjectContext { dataController.container.viewContext }

    private var doomed: dime.Category!
    private var keeper: dime.Category!
    private var created: [NSManagedObject] = []

    override func setUpWithError() throws {
        doomed = makeCategory("Doomed")
        keeper = makeCategory("Keeper")
        try context.save()
    }

    override func tearDownWithError() throws {
        for object in created where object.managedObjectContext != nil && !object.isDeleted {
            context.delete(object)
        }
        try context.save()
        created = []
    }

    func testMovingToAnotherCategoryKeepsTransactionsAndTemplates() throws {
        let first = makeTransaction(in: doomed)
        let second = makeTransaction(in: doomed)
        let template = makeTemplate(in: doomed)
        try context.save()

        dataController.deleteCategory(doomed, fate: .move(to: keeper))

        XCTAssertTrue(doomed.isDeleted || doomed.managedObjectContext == nil)
        let kept: [NSManagedObject] = [first, second, template]
        for object in kept {
            XCTAssertNotNil(object.managedObjectContext)
            XCTAssertFalse(object.isDeleted)
        }
        XCTAssertEqual(first.category, keeper)
        XCTAssertEqual(second.category, keeper)
        XCTAssertEqual(template.category, keeper)
        XCTAssertEqual(keeper.transactionCount, 2)
    }

    func testMovingToNoCategoryLeavesTransactionsUncategorised() throws {
        let transaction = makeTransaction(in: doomed)
        let template = makeTemplate(in: doomed)
        try context.save()

        dataController.deleteCategory(doomed, fate: .move(to: nil))

        XCTAssertNotNil(transaction.managedObjectContext)
        XCTAssertNil(transaction.category)
        XCTAssertNotNil(template.managedObjectContext)
        XCTAssertNil(template.category)
    }

    func testDeletingRemovesTransactionsAndTemplatesWithTheCategory() throws {
        let transaction = makeTransaction(in: doomed)
        let template = makeTemplate(in: doomed)
        let elsewhere = makeTransaction(in: keeper)
        try context.save()

        dataController.deleteCategory(doomed, fate: .delete)

        XCTAssertNil(transaction.managedObjectContext)
        XCTAssertNil(template.managedObjectContext)
        XCTAssertNotNil(elsewhere.managedObjectContext)
        XCTAssertEqual(elsewhere.category, keeper)
    }

    // MARK: Helpers

    private func makeCategory(_ name: String) -> dime.Category {
        let category = Category(context: context)
        category.id = UUID()
        category.name = name
        category.emoji = "🧪"
        category.colour = "#279AF4"
        category.income = false
        category.order = 900
        category.dateCreated = .now
        created.append(category)
        return category
    }

    private func makeTransaction(in category: dime.Category) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.note = "Test"
        transaction.amount = 5
        transaction.income = false
        transaction.category = category
        transaction.date = .now
        transaction.day = Calendar.current.startOfDay(for: .now)
        created.append(transaction)
        return transaction
    }

    private func makeTemplate(in category: dime.Category) -> TemplateTransaction {
        let template = TemplateTransaction(context: context)
        template.id = UUID()
        template.note = "Test"
        template.amount = 5
        template.income = false
        template.category = category
        template.order = 99
        created.append(template)
        return template
    }
}
