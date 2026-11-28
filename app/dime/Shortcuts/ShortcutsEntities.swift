//
//  ShortcutsEntities.swift
//  dime
//
//  Created by Rafael Soh on 1/8/23.
//

import AppIntents
import CoreData
import Foundation
import UIKit

// @available(iOS 16, *)
// struct IncomeCategoryEntity: AppEntity, Identifiable {
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Income Category")
//    static var defaultQuery: IncomeCategoryQuery = IncomeCategoryQuery()
//
//
//    var id: UUID
//
//    @Property(title: "Name")
//    var name: String
//
//    @Property(title: "Emoji")
//    var emoji: String
//
//    var displayRepresentation: DisplayRepresentation {
//        DisplayRepresentation(title: "\(emoji)  \(name)")
//    }
//
//    init(id: UUID, name: String, emoji: String) {
//        self.id = id
//        self.name = name
//        self.emoji = emoji
//    }
//
// }
//
// @available(iOS 16, *)
// struct IncomeCategoryQuery: EntityQuery {
//    func entities(for identifiers: [IncomeCategoryEntity.ID]) async throws -> [IncomeCategoryEntity] {
//        let dataController = DataController()
//        return identifiers.compactMap { identifier in
//            if let match = try? dataController.findCategory(withId: identifier) {
//                if let id = match.id {
//                    return IncomeCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji)
//                } else {
//                    return nil
//                }
//            } else {
//                return nil
//            }
//        }
//    }
//
//    func suggestedEntities() async throws -> [IncomeCategoryEntity] {
//        let dataController = DataController()
//        let categories = dataController.getAllCategories(income: true)
//        return categories.compactMap { category in
//            if let id = category.id {
//                return IncomeCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji)
//            } else {
//                return nil
//            }
//        }
//    }
// }
//
// @available(iOS 16, *)
// struct ExpenseCategoryEntity: AppEntity, Identifiable {
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Expense Category")
//    static var defaultQuery: ExpenseCategoryQuery = ExpenseCategoryQuery()
//
//
//    var id: UUID
//
//    @Property(title: "Name")
//    var name: String
//
//    @Property(title: "Emoji")
//    var emoji: String
//
//    var displayRepresentation: DisplayRepresentation {
//        DisplayRepresentation(title: "\(emoji)  \(name)")
//    }
//
//    init(id: UUID, name: String, emoji: String) {
//        self.id = id
//        self.name = name
//        self.emoji = emoji
//    }
//
// }
//
// @available(iOS 16, *)
// struct ExpenseCategoryQuery: EntityQuery {
//    func entities(for identifiers: [ExpenseCategoryEntity.ID]) async throws -> [ExpenseCategoryEntity] {
//        let dataController = DataController()
//        return identifiers.compactMap { identifier in
//            if let match = try? dataController.findCategory(withId: identifier) {
//                if let id = match.id {
//                    return ExpenseCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji)
//                } else {
//                    return nil
//                }
//            } else {
//                return nil
//            }
//        }
//    }
//
//    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
//        let dataController = DataController()
//        let categories = dataController.getAllCategories(income: true)
//        return categories.compactMap { category in
//            if let id = category.id {
//                return ExpenseCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji)
//            } else {
//                return nil
//            }
//        }
//    }
// }

/// The "No Category" choice offered alongside real categories in Shortcuts. It has a fixed id no category can have.
enum CategoryEntityOptions {
    static let noCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static func matchesNoCategory(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || Uncategorised.name.localizedCaseInsensitiveContains(trimmed)
    }
}

@available(iOS 16, *)
struct IncomeCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = IncomeCategoryQuery
    static var defaultQuery: IncomeCategoryQuery = .init()

    static let noCategory = IncomeCategoryEntity(id: CategoryEntityOptions.noCategoryID, name: Uncategorised.name, emoji: "", income: true)

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        emoji.isEmpty ? DisplayRepresentation(title: "\(name)") : DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.income = income
    }
}

@available(iOS 16, *)
struct IncomeCategoryQuery: EntityStringQuery {
    @MainActor
    func entities(matching query: String) async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: true).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        let matches = categories.compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
            } else {
                return nil
            }
        }

        return matches + (CategoryEntityOptions.matchesNoCategory(query) ? [IncomeCategoryEntity.noCategory] : [])
    }

    @MainActor
    func entities(for identifiers: [IncomeCategoryEntity.ID]) async throws -> [IncomeCategoryEntity] {
        return identifiers.compactMap { identifier in
            if identifier == CategoryEntityOptions.noCategoryID {
                return IncomeCategoryEntity.noCategory
            }

            let dataController = DataController.shared

            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return IncomeCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: true).compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
            } else {
                return nil
            }
        }

        return categories + [IncomeCategoryEntity.noCategory]
    }
}

@available(iOS 16, *)
struct ExpenseCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = ExpenseCategoryQuery
    static var defaultQuery: ExpenseCategoryQuery = .init()

    static let noCategory = ExpenseCategoryEntity(id: CategoryEntityOptions.noCategoryID, name: Uncategorised.name, emoji: "", income: false)

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        emoji.isEmpty ? DisplayRepresentation(title: "\(name)") : DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.income = income
    }
}

@available(iOS 16, *)
struct ExpenseCategoryQuery: EntityStringQuery {
    @MainActor
    func entities(matching query: String) async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        let matches = categories.compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
            } else {
                return nil
            }
        }

        return matches + (CategoryEntityOptions.matchesNoCategory(query) ? [ExpenseCategoryEntity.noCategory] : [])
    }

    @MainActor
    func entities(for identifiers: [ExpenseCategoryEntity.ID]) async throws -> [ExpenseCategoryEntity] {
        return identifiers.compactMap { identifier in
            if identifier == CategoryEntityOptions.noCategoryID {
                return ExpenseCategoryEntity.noCategory
            }

            let dataController = DataController.shared
            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return ExpenseCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false).compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
            } else {
                return nil
            }
        }

        return categories + [ExpenseCategoryEntity.noCategory]
    }
}

@available(iOS 16, *)
struct BudgetEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Budget")
    typealias DefaultQueryType = BudgetQuery
    static var defaultQuery: BudgetQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

@available(iOS 16, *)
struct BudgetQuery: EntityStringQuery {
    @MainActor
    func entities(matching query: String) async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        let budgets = dataController.getAllBudgets().filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        return budgets.compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, emoji: budget.wrappedEmoji)
            } else {
                return nil
            }
        }
    }

    @MainActor
    func entities(for identifiers: [BudgetEntity.ID]) async throws -> [BudgetEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared

            if let match = try? dataController.findBudget(withId: identifier) {
                if let id = match.id {
                    return BudgetEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        return dataController.getAllBudgets().compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, emoji: budget.wrappedEmoji)
            } else {
                return nil
            }
        }
    }
}

// @available(iOS 16, *)
// struct CategoryEntity: AppEntity, Identifiable, Hashable, Equatable {
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
//    typealias DefaultQueryType = CategoryQuery
//    static var defaultQuery: CategoryQuery = CategoryQuery()
//
//    var id: UUID
//
//    @Property(title: "Name")
//    var name: String
//
//    @Property(title: "Emoji")
//    var emoji: String
//
//    @Property(title: "Income")
//    var income: Bool
//
//    var displayRepresentation: DisplayRepresentation {
//        DisplayRepresentation(title: "\(emoji) \(name)")
//    }
//
//    init(id: UUID, name: String, emoji: String, income: Bool) {
//        self.id = id
//        self.name = name
//        self.emoji = emoji
//        self.income = income
//    }
//
// }
//
// @available(iOS 16, *)
// extension CategoryEntity {
//
//    // Hashable conformance
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//    }
//
//    // Equtable conformance
//    static func ==(lhs: CategoryEntity, rhs: CategoryEntity) -> Bool {
//        return lhs.id == rhs.id
//    }
//
// }
//
// @available(iOS 16, *)
// struct CategoryQuery: EntityPropertyQuery {
//    init() {
//        self.expense = false
//    }
//
//    init(expense: Bool) {
//        self.expense = expense
//    }
//
//    var expense: Bool
//
//    func entities(matching query: String) async throws -> [CategoryEntity] {
//        let dataController = DataController()
//        let categories = dataController.getAllCategories().filter {
//            ($0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query))
//        }
//
//        return categories.compactMap { category in
//            if let id = category.id {
//                return CategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
//            } else {
//                return nil
//            }
//        }
//    }
//
//    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
//        let dataController = DataController()
//        return identifiers.compactMap { identifier in
//            if let match = try? dataController.findCategory(withId: identifier) {
//                if let id = match.id {
//                    return CategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, income: match.income)
//                } else {
//                    return nil
//                }
//            } else {
//                return nil
//            }
//        }
//    }
//
//    func suggestedEntities() async throws -> [CategoryEntity] {
//        let dataController = DataController()
//        let categories = dataController.getAllCategories()
//        return categories.compactMap { category in
//            if category.income == expense {
//                if let id = category.id {
//                    return CategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
//                } else {
//                    return nil
//                }
//            } else {
//                return nil
//            }
//
//        }
//    }
//
//    static var properties = EntityQueryProperties<CategoryEntity, NSPredicate> {
//        Property(\CategoryEntity.$name) {
//            EqualToComparator { NSPredicate(format: "name = %@", $0) }
//            ContainsComparator { NSPredicate(format: "name CONTAINS %@", $0) }
//
//        }
//        Property(\CategoryEntity.$emoji) {
//            EqualToComparator { NSPredicate(format: "emoji = %@", $0) }
//            ContainsComparator { NSPredicate(format: "emoji CONTAINS %@", $0) }
//        }
//    }
//
//    static var sortingOptions = SortingOptions {
//        SortableBy(\CategoryEntity.$name)
//        SortableBy(\CategoryEntity.$emoji)
//    }
//
//    func entities(
//        matching comparators: [NSPredicate],
//        mode: ComparatorMode,
//        sortedBy: [Sort<CategoryEntity>],
//        limit: Int?
//    ) async throws -> [CategoryEntity] {
//        let context = DataController().container.viewContext
//        let request: NSFetchRequest<Category> = Category.fetchRequest()
//        let predicate = NSCompoundPredicate(type: mode == .and ? .and : .or, subpredicates: comparators)
//        request.fetchLimit = limit ?? 5
//        request.predicate = predicate
//
//        let matchingCategories = try context.fetch(request)
//        return matchingCategories.compactMap { category in
//            if let id = category.id {
//                return CategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, income: category.income)
//            } else {
//                return nil
//            }
//        }
//    }
//
// }

// MARK: - Accounts

/// Main or one of the user's accounts, as Shortcuts offers them. Identified by `AccountChoice.key`: an account's
/// id, or "main" for Main, which has no object of its own.
@available(iOS 16, *)
struct AccountEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Account")
    typealias DefaultQueryType = AccountQuery
    static var defaultQuery: AccountQuery = .init()

    var id: String

    @Property(title: "Name")
    var name: String

    /// The account's SF Symbol, or a stand-in where this iOS version lacks it.
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ choice: AccountChoice) {
        id = choice.key
        symbol = UIImage(systemName: choice.symbol) != nil ? choice.symbol : "wallet.pass"
        name = choice.name
    }
}

@available(iOS 16, *)
struct AccountQuery: EntityStringQuery {
    @MainActor
    func entities(matching query: String) async throws -> [AccountEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        return DataController.shared.accountChoices()
            .filter { trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed) }
            .map(AccountEntity.init)
    }

    /// An account deleted since the shortcut was set up isn't found, so the action can ask for another.
    @MainActor
    func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        let choices = DataController.shared.accountChoices()

        return identifiers.compactMap { identifier in
            choices.first { $0.key == identifier }.map(AccountEntity.init)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        DataController.shared.accountChoices().map(AccountEntity.init)
    }
}
