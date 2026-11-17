//
//  ShortcutsEntities.swift
//  dime
//
//  Created by Rafael Soh on 1/8/23.
//

import AppIntents
import CoreData
import Foundation

@available(iOS 16, *)
struct IncomeCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = IncomeCategoryQuery
    static var defaultQuery: IncomeCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    /// SF Symbol used when Shortcuts shows the item.
    var icon: String = CategorySymbols.fallback

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }

    init(id: UUID, name: String, emoji: String, icon: String = CategorySymbols.fallback, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.icon = icon
        self.income = income
    }
}

@available(iOS 16, *)
struct IncomeCategoryQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: true).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        return categories.compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, icon: category.wrappedIcon, income: category.income)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [IncomeCategoryEntity.ID]) async throws -> [IncomeCategoryEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared

            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return IncomeCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, icon: match.wrappedIcon, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        return dataController.getAllCategories(income: true).compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, icon: category.wrappedIcon, income: category.income)
            } else {
                return nil
            }
        }
    }
}

@available(iOS 16, *)
struct ExpenseCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = ExpenseCategoryQuery
    static var defaultQuery: ExpenseCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    /// SF Symbol used when Shortcuts shows the item.
    var icon: String = CategorySymbols.fallback

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }

    init(id: UUID, name: String, emoji: String, icon: String = CategorySymbols.fallback, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.icon = icon
        self.income = income
    }
}

@available(iOS 16, *)
struct ExpenseCategoryQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        return categories.compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, icon: category.wrappedIcon, income: category.income)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [ExpenseCategoryEntity.ID]) async throws -> [ExpenseCategoryEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared
            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return ExpenseCategoryEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, icon: match.wrappedIcon, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        return dataController.getAllCategories(income: false).compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, icon: category.wrappedIcon, income: category.income)
            } else {
                return nil
            }
        }
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

    /// SF Symbol used when Shortcuts shows the item.
    var icon: String = CategorySymbols.fallback

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }

    init(id: UUID, name: String, emoji: String, icon: String = CategorySymbols.fallback) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.icon = icon
    }
}

@available(iOS 16, *)
struct BudgetQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        let budgets = dataController.getAllBudgets().filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedEmoji.localizedCaseInsensitiveContains(query)
        }

        return budgets.compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, emoji: budget.wrappedEmoji, icon: budget.wrappedIcon)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [BudgetEntity.ID]) async throws -> [BudgetEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared

            if let match = try? dataController.findBudget(withId: identifier) {
                if let id = match.id {
                    return BudgetEntity(id: id, name: match.wrappedName, emoji: match.wrappedEmoji, icon: match.wrappedIcon)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        return dataController.getAllBudgets().compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, emoji: budget.wrappedEmoji, icon: budget.wrappedIcon)
            } else {
                return nil
            }
        }
    }
}

