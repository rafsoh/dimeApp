//
//  AutoCategorizerTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

/// Stands in for Apple Intelligence: answers what it's told to, and remembers what it was asked.
private final class FakeChooser: AutoCategoryChooser {
    struct Question {
        let note: String
        let income: Bool
        let options: [AutoCategoryOption]
    }

    var answer: String?
    var error: Error?
    /// Runs on the main thread before the answer comes back, to change things while the model "thinks".
    var whileThinking: (() -> Void)?
    private(set) var questions: [Question] = []

    func chooseCategory(for note: String, income: Bool, from options: [AutoCategoryOption]) async throws -> String? {
        // Decided when asked, so changing it while thinking only affects the next question.
        let answer = self.answer
        let error = self.error
        questions.append(Question(note: note, income: income, options: options))

        if let whileThinking {
            await MainActor.run { whileThinking() }
        }

        if let error {
            throw error
        }

        return answer
    }
}

private struct ModelUnavailable: Error {}

final class AutoCategorizerTests: XCTestCase {
    private let dataController = DataController.shared
    private var context: NSManagedObjectContext { dataController.container.viewContext }
    private var created: [NSManagedObject] = []

    private let suiteName = "AutoCategorizerTests"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!
    private lazy var queue = AutoCategoryQueue(defaults: defaults)
    private let chooser = FakeChooser()
    private lazy var categorizer = AutoCategorizer(queue: queue, minimumGlimmer: 0, makeChooser: { [chooser] in chooser })

    /// Category names unique to the run, as the store can hold the user's own.
    private let tag = UUID().uuidString.prefix(6)

    override func setUpWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: AutoCategoryQueue.enabledKey)
        // What Shortcuts, Quick Add and recurring transactions queue lands in this test's queue.
        dataController.autoCategoryQueue = queue
    }

    override func tearDownWithError() throws {
        dataController.autoCategoryQueue = AutoCategoryQueue()
        for object in created where !object.isGone {
            context.delete(object)
        }
        try context.save()
        created = []
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Filing

    @MainActor
    func testFilesTheTransactionUnderTheChosenCategory() async throws {
        let food = makeCategory("Food")
        _ = makeCategory("Transport")
        let lunch = makeTransaction(note: "Chicken rice ")
        try context.save()
        chooser.answer = food.wrappedName

        let run = try XCTUnwrap(categorizer.categoriseIfNeeded([lunch]))
        XCTAssertTrue(categorizer.pending.contains(lunch.objectID), "The row glimmers while the model thinks")

        await run.value

        XCTAssertEqual(lunch.category, food)
        XCTAssertFalse(lunch.hasChanges, "The category is saved")
        XCTAssertTrue(categorizer.pending.isEmpty)
        XCTAssertEqual(chooser.questions.first?.note, "Chicken rice")
        XCTAssertEqual(chooser.questions.first?.income, false)
    }

    @MainActor
    func testLeavesANoteThatFitsNoCategoryUncategorised() async throws {
        _ = makeCategory("Food")
        let mash = makeTransaction(note: "asdfjkl")
        try context.save()
        chooser.answer = nil

        await categorizer.categoriseIfNeeded([mash])?.value

        XCTAssertNil(mash.category)
        XCTAssertTrue(categorizer.pending.isEmpty)
    }

    @MainActor
    func testAModelErrorLeavesItUncategorised() async throws {
        let food = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        chooser.answer = food.wrappedName
        chooser.error = ModelUnavailable()

        await categorizer.categoriseIfNeeded([lunch])?.value

        XCTAssertNil(lunch.category)
        XCTAssertTrue(categorizer.pending.isEmpty)
    }

    @MainActor
    func testAnAnswerThatIsNoCategoryIsIgnored() async throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        chooser.answer = "Not a category"

        await categorizer.categoriseIfNeeded([lunch])?.value

        XCTAssertNil(lunch.category)
    }

    @MainActor
    func testACategoryPickedMeanwhileWins() async throws {
        let food = makeCategory("Food")
        let treats = makeCategory("Treats")
        let cake = makeTransaction(note: "Cake")
        try context.save()
        chooser.answer = food.wrappedName
        chooser.whileThinking = { cake.category = treats }

        await categorizer.categoriseIfNeeded([cake])?.value

        XCTAssertEqual(cake.category, treats)
        XCTAssertTrue(categorizer.pending.isEmpty)
    }

    @MainActor
    func testANoteChangedMeanwhileIsLeftAlone() async throws {
        let food = makeCategory("Food")
        let entry = makeTransaction(note: "Lunch")
        try context.save()
        chooser.answer = food.wrappedName
        chooser.whileThinking = { entry.note = "Taxi" }

        await categorizer.categoriseIfNeeded([entry])?.value

        XCTAssertNil(entry.category)
    }

    @MainActor
    func testATransactionDeletedMeanwhileIsLeftAlone() async throws {
        let food = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        chooser.answer = food.wrappedName
        chooser.whileThinking = { [context] in
            context.delete(lunch)
            try? context.save()
        }

        await categorizer.categoriseIfNeeded([lunch])?.value

        XCTAssertTrue(lunch.isGone)
        XCTAssertTrue(categorizer.pending.isEmpty)
        XCTAssertEqual(food.transactions?.count ?? 0, 0)
    }

    @MainActor
    func testOnlyTheLatestRunFilesIt() async throws {
        let food = makeCategory("Food")
        let cake = makeTransaction(note: "Cake")
        try context.save()

        // The first run is still thinking when the transaction is saved again, and the second run finds
        // no category fits. Whichever finishes first, the first run's answer is out of date.
        chooser.answer = food.wrappedName
        var secondRun: Task<Void, Never>?
        chooser.whileThinking = { [chooser, categorizer] in
            chooser.whileThinking = nil
            chooser.answer = nil
            secondRun = categorizer.categoriseIfNeeded([cake])
        }

        await categorizer.categoriseIfNeeded([cake])?.value
        let second = try XCTUnwrap(secondRun)
        await second.value

        XCTAssertEqual(chooser.questions.count, 2)
        XCTAssertNil(cake.category)
        XCTAssertTrue(categorizer.pending.isEmpty)
    }

    @MainActor
    func testRecurringOccurrencesAreFiledToo() async throws {
        let fun = makeCategory("Fun")
        let streaming = makeRecurring(note: "Netflix", monthsAgo: 2)

        var occurrences: [Transaction] = []
        dataController.updateRecurringTransaction(transaction: streaming) { occurrences.append($0) }
        for occurrence in occurrences {
            created.append(occurrence)
        }
        XCTAssertEqual(occurrences.count, 2, "Last month's and this month's are due")

        chooser.answer = fun.wrappedName
        await categorizer.categoriseIfNeeded([streaming] + occurrences)?.value

        XCTAssertEqual(streaming.category, fun)
        for occurrence in occurrences {
            XCTAssertEqual(occurrence.category, fun)
        }
    }

    // MARK: When it asks

    func testDoesNothingWhenSwitchedOff() throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        defaults.set(false, forKey: AutoCategoryQueue.enabledKey)

        XCTAssertNil(categorizer.categoriseIfNeeded([lunch]))
        XCTAssertTrue(categorizer.pending.isEmpty)
        XCTAssertTrue(chooser.questions.isEmpty)
    }

    func testDoesNothingWithoutAModel() throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        let noModel = AutoCategorizer(queue: queue, minimumGlimmer: 0, makeChooser: { nil })

        XCTAssertNil(noModel.categoriseIfNeeded([lunch]))
        XCTAssertTrue(noModel.pending.isEmpty)
    }

    func testDoesNothingForAChosenCategoryOrAMeaninglessNote() throws {
        let food = makeCategory("Food")
        let filed = makeTransaction(note: "Lunch", category: food)
        let blank = makeTransaction(note: "")
        let numbers = makeTransaction(note: "12.50 - #3")
        try context.save()

        XCTAssertNil(categorizer.categoriseIfNeeded([filed]))
        XCTAssertNil(categorizer.categoriseIfNeeded([blank]))
        XCTAssertNil(categorizer.categoriseIfNeeded([numbers]))
        XCTAssertTrue(chooser.questions.isEmpty)
    }

    func testMeaningfulText() {
        XCTAssertTrue(AutoCategoryQueue.hasMeaningfulText("Kopi"))
        XCTAssertTrue(AutoCategoryQueue.hasMeaningfulText("拉面"))
        XCTAssertTrue(AutoCategoryQueue.hasMeaningfulText("🍕"))
        XCTAssertFalse(AutoCategoryQueue.hasMeaningfulText("  "))
        XCTAssertFalse(AutoCategoryQueue.hasMeaningfulText("123 #4 - 5.00"))
    }

    // MARK: The user's choice sticks

    func testACategoryTheUserRemovedIsNeverPutBack() throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()

        queue.keepUncategorised(lunch)

        XCTAssertFalse(queue.wantsCategory(lunch))
        XCTAssertNil(categorizer.categoriseIfNeeded([lunch]))
        XCTAssertFalse(queue.add([lunch]))
        XCTAssertTrue(chooser.questions.isEmpty)
    }

    @MainActor
    func testARemovalWhileTheModelThinksWins() async throws {
        let food = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        chooser.answer = food.wrappedName
        chooser.whileThinking = { [queue] in queue.keepUncategorised(lunch) }

        await categorizer.categoriseIfNeeded([lunch])?.value

        XCTAssertNil(lunch.category)
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testOccurrencesOfARecurringTransactionLeftUncategorisedStayThatWay() throws {
        _ = makeCategory("Fun")
        let streaming = makeRecurring(note: "Netflix", monthsAgo: 2)
        queue.keepUncategorised(streaming)

        var occurrences: [Transaction] = []
        dataController.updateRecurringTransaction(transaction: streaming) { occurrences.append($0) }
        for occurrence in occurrences {
            created.append(occurrence)
        }

        XCTAssertFalse(occurrences.isEmpty)
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertTrue(occurrences.allSatisfy { queue.isKeptUncategorised($0) })
    }

    // MARK: Shortcuts, Quick Add and recurring transactions

    @MainActor
    func testAShortcutOrQuickAddTransactionIsQueuedThenFiled() async throws {
        let coffee = makeCategory("Coffee")
        let template = TemplateTransaction(context: context)
        template.id = UUID()
        template.note = "Flat white"
        template.amount = 5
        template.order = 99
        created.append(template)
        try context.save()
        chooser.answer = coffee.wrappedName

        // Quick Add and the New Transaction shortcut both log through newTransaction.
        let logged = dataController.logQuickAddTemplate(template)
        created.append(logged)

        XCTAssertNotNil(queue.entries[try XCTUnwrap(logged.id)], "Queued, so a widget's transaction is categorised when Dime opens")

        await categorizer.waitForCategory(of: logged, upTo: 5)

        XCTAssertEqual(logged.category, coffee)
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testImportsAndSwitchedOffSavesAreNotQueued() throws {
        _ = makeCategory("Food")

        let imported = dataController.insertTransaction(note: "Imported lunch", category: nil, income: false, amount: 5, date: .now)
        created.append(imported)
        try context.save()
        XCTAssertTrue(queue.entries.isEmpty)

        defaults.set(false, forKey: AutoCategoryQueue.enabledKey)
        let logged = dataController.newTransaction(note: "Lunch", category: nil, income: false, amount: 5, date: .now, repeatType: 0, repeatCoefficient: 1, delay: false)
        created.append(logged)
        XCTAssertTrue(queue.entries.isEmpty)
    }

    @MainActor
    func testNewRecurringOccurrencesAreFiledWithOneQuestion() async throws {
        let fun = makeCategory("Fun")
        let streaming = makeRecurring(note: "Spotify", monthsAgo: 2)
        try context.save()
        chooser.answer = fun.wrappedName

        // As when Dime opens and logs the occurrences that came due.
        var occurrences: [Transaction] = []
        dataController.updateRecurringTransaction(transaction: streaming) { occurrences.append($0) }
        for occurrence in occurrences {
            created.append(occurrence)
        }
        XCTAssertEqual(queue.entries.count, occurrences.count)

        let first = try XCTUnwrap(occurrences.first)
        await categorizer.waitForCategory(of: first, upTo: 5)

        XCTAssertEqual(chooser.questions.count, 1, "Occurrences with the same note are asked about together")
        XCTAssertTrue(occurrences.allSatisfy { $0.category == fun })
        XCTAssertTrue(queue.entries.isEmpty)
    }

    @MainActor
    func testFailedTriesAreRetriedThenForgotten() async throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        chooser.error = ModelUnavailable()
        let id = try XCTUnwrap(lunch.id)

        for attempt in 1 ..< AutoCategoryQueue.maximumAttempts {
            await categorizer.categoriseIfNeeded([lunch])?.value
            XCTAssertEqual(queue.entries[id]?.attempts, attempt, "Kept for another try")
        }

        await categorizer.categoriseIfNeeded([lunch])?.value
        XCTAssertNil(queue.entries[id])
        XCTAssertNil(lunch.category)
    }

    func testTheQueueForgetsWhatNoLongerNeedsACategory() throws {
        let food = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        try context.save()
        XCTAssertTrue(queue.add([lunch], announce: false))

        lunch.category = food
        try context.save()
        categorizer.processQueue()

        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertTrue(chooser.questions.isEmpty)
    }

    func testOldEntriesExpireAndSwitchingOffClearsTheQueue() throws {
        _ = makeCategory("Food")
        let lunch = makeTransaction(note: "Lunch")
        let dinner = makeTransaction(note: "Dinner")
        try context.save()
        XCTAssertTrue(queue.add([lunch, dinner], announce: false))

        queue.removeExpired(now: .now.addingTimeInterval(AutoCategoryQueue.lifetime + 60))
        XCTAssertTrue(queue.entries.isEmpty)

        XCTAssertTrue(queue.add([lunch], announce: false))
        defaults.set(false, forKey: AutoCategoryQueue.enabledKey)
        categorizer.processQueue()
        XCTAssertTrue(queue.entries.isEmpty)
    }

    // MARK: What it offers

    func testOffersCategoriesOfTheSameKindWithRecentNotes() throws {
        let food = makeCategory("Food")
        let salary = makeCategory("Salary", income: true)
        _ = makeTransaction(note: "Ramen", category: food, date: .now.addingTimeInterval(-60))
        _ = makeTransaction(note: "ramen", category: food, date: .now.addingTimeInterval(-120))
        _ = makeTransaction(note: food.wrappedName, category: food, date: .now.addingTimeInterval(-180))
        _ = makeTransaction(note: "Bubble tea", category: food, date: .now.addingTimeInterval(-240))
        _ = makeTransaction(note: "Payday", income: true, category: salary)
        try context.save()

        let options = AutoCategorizer.candidates(income: false, in: context).map(\.option)
        let foodOption = try XCTUnwrap(options.first { $0.name == food.wrappedName })

        XCTAssertEqual(foodOption.emoji, "🧪")
        XCTAssertEqual(Array(foodOption.examples.prefix(2)), ["Ramen", "Bubble tea"], "Newest first, without repeats or the category's own name")
        XCTAssertFalse(options.contains { $0.name == salary.wrappedName }, "Income categories aren't offered for an expense")
    }

    func testCategoriesWithTheSameNameAreOfferedOnce() throws {
        _ = makeCategory("Food")
        _ = makeCategory("Food")
        try context.save()

        let names = AutoCategorizer.candidates(income: false, in: context).map(\.option.name)

        XCTAssertEqual(names.filter { $0 == "Food \(tag)" }.count, 1)
    }

    // MARK: Prompt

    func testNoneChoiceAvoidsTheUsersCategories() {
        XCTAssertEqual(AutoCategoryPrompt.noneChoice(avoiding: ["Food"]), "None")
        XCTAssertEqual(AutoCategoryPrompt.noneChoice(avoiding: ["Food", "none"]), "None of these")
        XCTAssertEqual(AutoCategoryPrompt.noneChoice(avoiding: ["None", "None of these"]), "No category fits")
    }

    func testPromptListsEveryOptionAndNone() {
        let options = [
            AutoCategoryOption(name: "Food", emoji: "🍜", examples: ["Ramen", "Kopi"]),
            AutoCategoryOption(name: "Transport", emoji: "🚕", examples: []),
        ]

        let prompt = AutoCategoryPrompt.prompt(note: "Grab", income: false, options: options, none: "None")

        XCTAssertTrue(prompt.contains("Note: \"Grab\""))
        XCTAssertTrue(prompt.contains("- Food 🍜 (earlier notes: \"Ramen\", \"Kopi\")"))
        XCTAssertTrue(prompt.contains("- Transport 🚕\n"))
        XCTAssertTrue(prompt.contains("- None"))
    }

    // MARK: Helpers

    private func makeCategory(_ name: String, income: Bool = false) -> dime.Category {
        let category = Category(context: context)
        category.id = UUID()
        category.name = "\(name) \(tag)"
        category.emoji = "🧪"
        category.colour = "#279AF4"
        category.income = income
        category.order = 900
        category.dateCreated = .now
        created.append(category)
        return category
    }

    /// A monthly transaction that started some months ago, so occurrences have come due since.
    private func makeRecurring(note: String, monthsAgo: Int) -> Transaction {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -monthsAgo, to: calendar.startOfDay(for: .now)) ?? .now
        let recurring = makeTransaction(note: note, date: start)
        recurring.onceRecurring = true
        recurring.recurringType = 3
        recurring.recurringCoefficient = 1
        return recurring
    }

    private func makeTransaction(note: String, income: Bool = false, category: dime.Category? = nil, date: Date = .now) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.note = note
        transaction.amount = 5
        transaction.income = income
        transaction.category = category
        transaction.date = date
        transaction.day = Calendar.current.startOfDay(for: date)
        transaction.month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))
        created.append(transaction)
        return transaction
    }
}
