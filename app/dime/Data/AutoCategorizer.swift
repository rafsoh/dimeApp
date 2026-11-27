//
//  AutoCategorizer.swift
//  dime
//
//  Feature Lab: files a transaction logged with a note but no category under one of the user's
//  categories, using the on-device Apple Intelligence model.
//

import CoreData
import Foundation
import os
import SwiftUI
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One of the user's categories, as offered to the model.
struct AutoCategoryOption: Equatable {
    let name: String
    let emoji: String
    /// Notes the user filed under it lately, so the model learns how they use it.
    let examples: [String]
}

/// Picks which of the options a note belongs under.
protocol AutoCategoryChooser {
    /// The name of the chosen option, exactly as given, or nil when the note doesn't suggest any of them.
    func chooseCategory(for note: String, income: Bool, from options: [AutoCategoryOption]) async throws -> String?
}

/// Whether Apple Intelligence can categorise transactions here, and if not, why.
enum AutoCategoryAvailability: Equatable {
    case available
    /// The device supports it, but it's turned off in the Settings app.
    case turnedOff
    /// It's on, but the model is still downloading.
    case notReady
    /// The OS or the device doesn't support it.
    case unsupported
}

final class AutoCategorizer: ObservableObject {
    static let shared = AutoCategorizer()

    /// The Feature Lab switch.
    static let enabledKey = "autoCategorise"

    /// Transactions waiting on the model, so their rows can glimmer.
    @Published private(set) var pending: Set<NSManagedObjectID> = []

    /// The latest run for each pending transaction. An older run that finishes late leaves it alone.
    private var runs: [NSManagedObjectID: UUID] = [:]

    private let defaults: UserDefaults?
    private let minimumGlimmer: TimeInterval
    private let makeChooser: () -> AutoCategoryChooser?
    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "AutoCategorizer")

    /// - Parameters:
    ///   - minimumGlimmer: The shortest time a row glimmers, so a quick answer doesn't just flicker.
    ///   - makeChooser: The model to ask, or nil when there's none to use.
    init(
        defaults: UserDefaults? = UserDefaults(suiteName: "group.com.rafaelsoh.dime"),
        minimumGlimmer: TimeInterval = 1.2,
        makeChooser: @escaping () -> AutoCategoryChooser? = AutoCategorizer.systemChooser
    ) {
        self.defaults = defaults
        self.minimumGlimmer = minimumGlimmer
        self.makeChooser = makeChooser
    }

    var isEnabled: Bool {
        defaults?.bool(forKey: Self.enabledKey) == true
    }

    // MARK: Availability

    static var availability: AutoCategoryAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default

            if model.isAvailable {
                return .available
            }

            if case let .unavailable(reason) = model.availability {
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .turnedOff
                case .modelNotReady:
                    return .notReady
                case .deviceNotEligible:
                    return .unsupported
                @unknown default:
                    return .unsupported
                }
            }
        }
        #endif

        return .unsupported
    }

    /// Apple Intelligence, when it can be used right now.
    static func systemChooser() -> AutoCategoryChooser? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .available {
            return AppleIntelligenceCategoryChooser()
        }
        #endif

        return nil
    }

    // MARK: Categorising

    /// Whether the transaction is one to categorise: it has no category, and its note has words or emoji in it.
    static func wantsCategory(_ transaction: Transaction) -> Bool {
        guard !transaction.isGone, transaction.category == nil, !transaction.isTransfer else {
            return false
        }

        return hasMeaningfulText(transaction.wrappedNote)
    }

    /// A note of only numbers and punctuation can't say what something was, so it isn't worth asking about.
    static func hasMeaningfulText(_ note: String) -> Bool {
        note.unicodeScalars.contains { CharacterSet.letters.contains($0) || $0.properties.isEmojiPresentation }
    }

    /// Asks the model to file the transactions under a category, when the Feature Lab switch is on and they
    /// have a note but no category. Call it once they're saved. The first is the one the user logged; any
    /// others are its recurring occurrences, saved with it, which go under the same category.
    ///
    /// - Returns: The run, for tests to wait on, or nil when there's nothing to ask.
    @discardableResult
    func categoriseIfNeeded(_ transactions: [Transaction]) -> Task<Void, Never>? {
        guard isEnabled, let logged = transactions.first, Self.wantsCategory(logged),
              let context = logged.managedObjectContext, let chooser = makeChooser()
        else {
            return nil
        }

        let note = Self.trimmed(logged.wrappedNote)
        let income = logged.income
        let batch = transactions.filter { Self.wantsCategory($0) && $0.income == income && Self.trimmed($0.wrappedNote) == note }

        let candidates = Self.candidates(income: income, in: context)

        guard !candidates.isEmpty else {
            return nil
        }

        // A row that isn't saved yet gets a new ID when it is, and its glimmer would be lost.
        let unsaved = batch.filter(\.objectID.isTemporaryID)
        if !unsaved.isEmpty {
            try? context.obtainPermanentIDs(for: unsaved)
        }

        let ids = batch.map(\.objectID)
        let run = UUID()

        for id in ids {
            runs[id] = run
        }

        // Rows animate the glimmer in themselves.
        pending.formUnion(ids)

        let options = candidates.map(\.option)

        return Task { @MainActor in
            let started = Date()
            var chosen: String?

            do {
                chosen = try await chooser.chooseCategory(for: note, income: income, from: options)
            } catch {
                // Guardrails, an unsupported language, a busy model: all leave it as the user logged it.
                self.logger.info("Couldn't categorise a transaction: \(String(describing: error), privacy: .public)")
            }

            let remaining = self.minimumGlimmer - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            let categoryID = chosen.flatMap { name in candidates.first { $0.option.name == name }?.objectID }
            self.finish(ids, run: run, note: note, income: income, categoryID: categoryID, in: context)
        }
    }

    @MainActor
    private func finish(_ ids: [NSManagedObjectID], run: UUID, note: String, income: Bool, categoryID: NSManagedObjectID?, in context: NSManagedObjectContext) {
        let current = ids.filter { runs[$0] == run }

        guard !current.isEmpty else {
            return
        }

        for id in current {
            runs[id] = nil
        }

        var category = categoryID.flatMap { try? context.existingObject(with: $0) as? Category }

        // It can be deleted, or switched between expense and income, while the model thinks.
        if let found = category, found.isGone || found.income != income {
            category = nil
        }

        var filed = false

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            pending.subtract(current)

            guard let category else {
                return
            }

            for id in current {
                // Whatever the user did meanwhile wins: a category they picked, a new note, a deletion.
                guard let transaction = try? context.existingObject(with: id) as? Transaction,
                      Self.wantsCategory(transaction),
                      transaction.income == income,
                      Self.trimmed(transaction.wrappedNote) == note
                else {
                    continue
                }

                transaction.category = category
                filed = true
            }

            if filed {
                DataController.shared.save()
            }
        }

        guard filed, let category else {
            return
        }

        if (defaults?.object(forKey: "haptics") as? Int ?? 1) != 0 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Filed under \(category.wrappedName)"))
        }
    }

    // MARK: Options

    struct Candidate {
        let objectID: NSManagedObjectID
        let option: AutoCategoryOption
    }

    /// The user's categories of the kind, in their order, each with a few notes filed under it lately.
    static func candidates(income: Bool, in context: NSManagedObjectContext) -> [Candidate] {
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        categoryRequest.predicate = NSPredicate(format: "income = %d", income)
        let categories = ((try? context.fetch(categoryRequest)) ?? []).filter { !$0.isGone }

        guard !categories.isEmpty else {
            return []
        }

        let recentRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        recentRequest.predicate = NSPredicate(format: "category != nil AND income = %d", income)
        recentRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        recentRequest.fetchLimit = 500
        let recent = (try? context.fetch(recentRequest)) ?? []

        // The model's context is small, so the more categories there are, the fewer examples each gets.
        let examplesPerCategory = categories.count > 25 ? 1 : 3
        var examples: [NSManagedObjectID: [String]] = [:]

        for transaction in recent {
            guard let category = transaction.category else {
                continue
            }

            let note = String(trimmed(transaction.wrappedNote).prefix(30))
            var list = examples[category.objectID, default: []]

            // A transaction logged without a note is noted with its category's name, which says nothing new.
            guard !note.isEmpty, list.count < examplesPerCategory,
                  note.caseInsensitiveCompare(trimmed(category.wrappedName)) != .orderedSame,
                  !list.contains(where: { $0.caseInsensitiveCompare(note) == .orderedSame })
            else {
                continue
            }

            list.append(note)
            examples[category.objectID] = list
        }

        var names = Set<String>()

        return categories.compactMap { category in
            let name = trimmed(category.wrappedName)

            // The model answers with a name, so each has to be one only a single category has.
            guard !name.isEmpty, names.insert(name.lowercased()).inserted else {
                return nil
            }

            let option = AutoCategoryOption(name: name, emoji: category.wrappedEmoji, examples: examples[category.objectID] ?? [])
            return Candidate(objectID: category.objectID, option: option)
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Prompt

/// What the model is told. Kept apart from the model so it can be tested anywhere.
enum AutoCategoryPrompt {
    /// The answer for "none of them", picked so it can't be mistaken for one of the user's categories.
    static func noneChoice(avoiding names: [String]) -> String {
        let taken = Set(names.map { $0.lowercased() })
        return ["None", "None of these", "No category fits"].first { !taken.contains($0.lowercased()) } ?? "No category fits \(UUID().uuidString.prefix(4))"
    }

    static func instructions(none: String) -> String {
        """
        You sort entries in a personal finance app into the user's own categories. Given the note the user \
        typed for one entry, choose the category it most clearly belongs to, using each category's name, its \
        emoji and the notes the user filed under it before. Notes are usually short: a shop, a brand, an item \
        or an activity, in any language.

        Choose "\(none)" when the note is gibberish, random letters, keyboard mashing, a test, too vague to \
        tell, or fits none of the categories. Don't guess: no category is better than a wrong one.
        """
    }

    static func prompt(note: String, income: Bool, options: [AutoCategoryOption], none: String) -> String {
        var lines = [
            "Entry: \(income ? "income" : "expense")",
            "Note: \"\(note)\"",
            "",
            "Categories:",
        ]

        for option in options {
            var line = "- \(option.name) \(option.emoji)"

            if !option.examples.isEmpty {
                line += " (earlier notes: " + option.examples.map { "\"\($0)\"" }.joined(separator: ", ") + ")"
            }

            lines.append(line)
        }

        lines.append("- \(none) (the note is gibberish or fits none of these)")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Apple Intelligence

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct AppleIntelligenceCategoryChooser: AutoCategoryChooser {
    func chooseCategory(for note: String, income: Bool, from options: [AutoCategoryOption]) async throws -> String? {
        let none = AutoCategoryPrompt.noneChoice(avoiding: options.map(\.name))

        // Guided generation: the model can only answer with one of these names.
        let choice = DynamicGenerationSchema(
            name: "CategoryChoice",
            description: "The category the note belongs to",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "category",
                    description: "One of the categories, or \(none) when none clearly fits",
                    schema: DynamicGenerationSchema(name: "CategoryName", anyOf: options.map(\.name) + [none])
                ),
            ]
        )

        let schema = try GenerationSchema(root: choice, dependencies: [])
        let session = LanguageModelSession(instructions: AutoCategoryPrompt.instructions(none: none))

        let response = try await session.respond(
            to: AutoCategoryPrompt.prompt(note: note, income: income, options: options, none: none),
            schema: schema,
            options: GenerationOptions(sampling: .greedy)
        )

        let chosen = try response.content.value(String.self, forProperty: "category")

        return chosen == none ? nil : chosen
    }
}
#endif
