//
//  AccountsTests.swift
//  dimeTests
//
//  Accounts must never cost a transaction, and transfers must never count as spending or income.
//

import CoreData
@testable import dime
import XCTest

final class AccountsTests: XCTestCase {
    private let dataController = DataController.shared
    private var inserted: [NSManagedObject] = []
    private var mainCurrency: String!

    private var context: NSManagedObjectContext {
        dataController.container.viewContext
    }

    override func setUpWithError() throws {
        mainCurrency = CurrencyConverter.mainCurrency(in: UserDefaults(suiteName: CurrencyConverter.appGroup))
    }

    override func tearDownWithError() throws {
        for object in inserted where !object.isDeleted && object.managedObjectContext != nil {
            context.delete(object)
        }
        inserted = []
        try context.save()
    }

    // MARK: - Helpers

    private func makeAccount(_ name: String) -> Account {
        let account = dataController.addAccount(named: name)
        inserted.append(account)
        return account
    }

    @discardableResult
    private func add(_ amount: Double, income: Bool = false, account: Account? = nil, category: dime.Category? = nil, minutesAgo: Double = 1) -> Transaction {
        let transaction = dataController.insertTransaction(note: "Test", category: category, income: income, amount: amount, currencyCode: mainCurrency, account: account, date: Date.now.addingTimeInterval(-minutesAgo * 60))
        inserted.append(transaction)
        return transaction
    }

    @discardableResult
    private func transfer(_ amount: Double, from: AccountChoice, to: AccountChoice, minutesAgo: Double = 1) -> (outgoing: Transaction, incoming: Transaction) {
        let legs = dataController.saveTransfer(from: from, to: to, amount: amount, currencyCode: mainCurrency, date: Date.now.addingTimeInterval(-minutesAgo * 60), note: "")
        inserted.append(legs.outgoing)
        inserted.append(legs.incoming)
        return legs
    }

    private func count(_ predicate: NSPredicate) throws -> Int {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = predicate
        return try context.count(for: request)
    }

    /// Every total a transfer must leave alone.
    private func totals(budget: MainBudget) -> [Double] {
        var values: [Double] = []

        for type in 1 ... 5 {
            values.append(dataController.getLogViewTotalSpent(type: type))
            values.append(dataController.getLogViewTotalIncome(type: type))
            values.append(dataController.getLogViewTotalNet(type: type).value)
            values.append(dataController.getShortcutInsights(type: 1, timeframe: type, optionalIncome: nil, categories: []))
        }

        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now))!

        for income in [false, true] {
            values.append(dataController.getInsights(type: 2, date: month, income: income).amount)
            values.append(dataController.results(for: dataController.fetchRequestForLineGraph(optionalIncome: income)).total(using: .current()).value)
            values.append(dataController.results(for: dataController.fetchRequestForWidgetInsights(type: .month, income: income).fetchRequest).total(using: .current()).value)
        }

        let summary = dataController.getInsightsSummary(type: 2, date: month)
        values += [summary.spent, summary.income, summary.net]
        values.append(dataController.budgetLeftover(overallBudget: budget).value)
        values.append(dataController.lineGraphNet(type: 2).points.map(\.amount).reduce(0, +))

        return values
    }

    // MARK: - Transfers

    func testTransfersLeaveEveryTotalUnchanged() throws {
        let savings = makeAccount("Savings")
        add(42.5)
        add(1_000, income: true)

        let budget = MainBudget(context: context)
        budget.amount = 500
        budget.type = 3
        budget.startDate = Calendar.current.date(byAdding: .day, value: -3, to: Date.now)
        inserted.append(budget)
        try context.save()

        let before = totals(budget: budget)

        transfer(750, from: .main, to: .account(savings))
        transfer(120, from: .account(savings), to: .main, minutesAgo: 2)

        XCTAssertEqual(totals(budget: budget), before)
    }

    func testATransferIsTwoLegsInTheirAccounts() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(300, from: .main, to: .account(savings))

        XCTAssertEqual(legs.outgoing.transferID, legs.incoming.transferID)
        XCTAssertNotNil(legs.outgoing.transferID)
        XCTAssertFalse(legs.outgoing.income)
        XCTAssertTrue(legs.incoming.income)
        XCTAssertNil(legs.outgoing.account)
        XCTAssertEqual(legs.incoming.account, savings)
        XCTAssertNil(legs.outgoing.category)
        XCTAssertEqual(legs.outgoing.recurringType, 0)
        XCTAssertEqual(legs.outgoing.transferCounterpart, legs.incoming)
        XCTAssertEqual(legs.incoming.transferCounterpart, legs.outgoing)
        XCTAssertEqual(legs.incoming.transferAccounts?.from, .main)
        XCTAssertEqual(legs.incoming.transferAccounts?.to, .account(savings))
        XCTAssertEqual(legs.outgoing.displayTitle, "\(MainAccount.name) → Savings")
    }

    func testListsShowATransferOnce() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(300, from: .main, to: .account(savings))
        let request = dataController.fetchRequestForRecentTransactions(type: .day)
        let shown = dataController.results(for: request).oneLegPerTransfer()

        XCTAssertTrue(shown.contains(legs.outgoing))
        XCTAssertFalse(shown.contains(legs.incoming))
    }

    // An incoming leg whose outgoing one is gone, such as deleted on a device from before transfers, still shows.
    func testATransferMissingItsOutgoingLegStillShows() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(300, from: .main, to: .account(savings))
        context.delete(legs.outgoing)
        try context.save()

        let request = dataController.fetchRequestForRecentTransactions(type: .day)
        let shown = dataController.results(for: request).oneLegPerTransfer()

        XCTAssertTrue(shown.contains(legs.incoming))
    }

    func testDeletingEitherLegDeletesTheTransfer() throws {
        let savings = makeAccount("Savings")
        let first = transfer(80, from: .main, to: .account(savings))
        let id = try XCTUnwrap(first.outgoing.transferID)

        dataController.deleteTransaction(first.incoming)
        XCTAssertEqual(try count(NSPredicate(format: "transferID == %@", id as CVarArg)), 0)

        let second = transfer(80, from: .main, to: .account(savings))
        let secondID = try XCTUnwrap(second.outgoing.transferID)

        dataController.deleteTransaction(second.outgoing)
        XCTAssertEqual(try count(NSPredicate(format: "transferID == %@", secondID as CVarArg)), 0)
    }

    func testEditingAnExpenseIntoATransferKeepsItAndAddsTheOtherLeg() throws {
        let savings = makeAccount("Savings")
        let expense = add(55)
        let id = expense.id

        let legs = dataController.saveTransfer(editing: expense, from: .main, to: .account(savings), amount: 60, currencyCode: mainCurrency, date: Date.now.addingTimeInterval(-30), note: "Top up")
        inserted.append(legs.incoming)

        XCTAssertEqual(legs.outgoing, expense)
        XCTAssertEqual(expense.id, id)
        XCTAssertEqual(expense.amount, 60)
        XCTAssertEqual(legs.incoming.amount, 60)
        XCTAssertEqual(legs.incoming.note, "Top up")
        XCTAssertEqual(legs.incoming.account, savings)
    }

    func testEditingALegWhoseOtherHalfIsMissingRecreatesIt() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(90, from: .main, to: .account(savings))
        let id = try XCTUnwrap(legs.outgoing.transferID)
        context.delete(legs.outgoing)
        try context.save()

        let edited = dataController.saveTransfer(editing: legs.incoming, from: .main, to: .account(savings), amount: 95, currencyCode: mainCurrency, date: Date.now.addingTimeInterval(-30), note: "")
        inserted.append(edited.outgoing)

        XCTAssertEqual(edited.incoming, legs.incoming)
        XCTAssertEqual(edited.outgoing.transferID, id)
        XCTAssertFalse(edited.outgoing.income)
        XCTAssertNil(edited.outgoing.account)
        XCTAssertEqual(try count(NSPredicate(format: "transferID == %@", id as CVarArg)), 2)
    }

    func testEndingATransferKeepsOneLegAsATransaction() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(70, from: .main, to: .account(savings))

        dataController.endTransfer(keeping: legs.outgoing)
        try context.save()

        XCTAssertNil(legs.outgoing.transferID)
        XCTAssertTrue(legs.incoming.isDeleted || legs.incoming.managedObjectContext == nil)
        XCTAssertFalse(legs.outgoing.isDeleted)
    }

    func testRecurringGenerationSkipsTransferLegs() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(10, from: .main, to: .account(savings), minutesAgo: 60 * 24 * 5)
        legs.outgoing.recurringType = 1
        legs.outgoing.recurringCoefficient = 1
        try context.save()

        let request = dataController.fetchRequestForRecurringTransactions()
        XCTAssertFalse(dataController.results(for: request).contains(legs.outgoing))
    }

    // MARK: - Accounts

    func testDeletingAnAccountMovesEverythingInItToMain() throws {
        let card = makeAccount("Card")
        let spend = add(12, account: card)
        let template = TemplateTransaction(context: context)
        template.id = UUID()
        template.amount = 4
        template.account = card
        inserted.append(template)
        try context.save()

        dataController.deleteAccount(card)

        XCTAssertFalse(spend.isDeleted)
        XCTAssertNotNil(spend.managedObjectContext)
        XCTAssertNil(spend.account)
        XCTAssertEqual(spend.accountChoice, .main)
        XCTAssertFalse(template.isDeleted)
        XCTAssertNil(template.account)
        XCTAssertEqual(try count(NSPredicate(format: "self == %@", spend)), 1)
    }

    // A transfer with Main would be from Main to Main, so it goes with the account. One with another account
    // stays, now from Main, and everything else in the account moves to Main.
    func testDeletingAnAccountRemovesOnlyItsTransfersWithMain() throws {
        let savings = makeAccount("Savings")
        let card = makeAccount("Card")
        let withMain = transfer(100, from: .main, to: .account(savings))
        let withCard = transfer(40, from: .account(savings), to: .account(card))
        let spend = add(12, account: savings)

        XCTAssertEqual(dataController.transfersWithMain(of: savings), [withMain.incoming])

        dataController.deleteAccount(savings)

        XCTAssertNil(withMain.outgoing.managedObjectContext)
        XCTAssertNil(withMain.incoming.managedObjectContext)
        XCTAssertNil(withCard.outgoing.account)
        XCTAssertEqual(withCard.incoming.account, card)
        XCTAssertEqual(withCard.outgoing.transferID, withCard.incoming.transferID)
        XCTAssertNil(spend.account)
        XCTAssertNotNil(spend.managedObjectContext)
    }

    func testDeletingAnAccountNeverCountsAsABulkDeletion() throws {
        let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
        let previous = defaults?.object(forKey: DataController.lastBulkDeletionKey)
        defer { defaults?.set(previous, forKey: DataController.lastBulkDeletionKey) }
        defaults?.removeObject(forKey: DataController.lastBulkDeletionKey)

        let card = makeAccount("Card")
        for _ in 0 ..< 12 {
            add(1, account: card)
        }
        try context.save()

        dataController.deleteAccount(card)

        XCTAssertNil(defaults?.object(forKey: DataController.lastBulkDeletionKey))
    }

    // Sync can delete an account while a page that picked it is still open.
    func testAnAccountDeletedMeanwhileIsNeitherDeletedAgainNorLinked() throws {
        let savings = makeAccount("Savings")
        dataController.deleteAccount(savings)
        XCTAssertNil(savings.managedObjectContext)

        dataController.deleteAccount(savings)
        dataController.renameAccount(.account(savings), to: "Renamed")

        let legs = transfer(50, from: .main, to: .account(savings))

        XCTAssertNil(legs.outgoing.account)
        XCTAssertNil(legs.incoming.account)
        XCTAssertFalse(context.hasChanges)
    }

    func testNewAccountsGoLastAndMainStaysFirst() throws {
        let first = makeAccount("First")
        let second = makeAccount("Second")

        XCTAssertGreaterThan(second.order, first.order)

        let choices = dataController.accountChoices()
        XCTAssertEqual(choices.first, .main)
        XCTAssertLessThan(try XCTUnwrap(choices.firstIndex(of: .account(first))), try XCTUnwrap(choices.firstIndex(of: .account(second))))
    }

    func testAccountNamesMustBeUniqueIncludingMain() throws {
        let card = makeAccount("Card")

        XCTAssertEqual(dataController.accountNameCheck("  "), .missingName)
        XCTAssertEqual(dataController.accountNameCheck("card"), .duplicateName)
        XCTAssertEqual(dataController.accountNameCheck(MainAccount.name.uppercased()), .duplicateName)
        XCTAssertEqual(dataController.accountNameCheck("Card", editing: .account(card)), .none)
        XCTAssertEqual(dataController.accountNameCheck("Savings"), .none)
    }

    func testRecurringOccurrencesStayInTheirAccount() throws {
        let card = makeAccount("Card")
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -3, to: Date.now)!
        let recurring = dataController.insertTransaction(note: "Gym (accounts test)", category: nil, income: false, amount: 9, currencyCode: mainCurrency, account: card, date: start, repeatType: 1, repeatCoefficient: 1)
        inserted.append(recurring)
        try context.save()

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "note == %@", "Gym (accounts test)")
        let occurrences = try context.fetch(request)
        inserted += occurrences

        XCTAssertGreaterThan(occurrences.count, 1)
        XCTAssertTrue(occurrences.allSatisfy { $0.account == card })
    }

    func testQuickAddTemplatesKeepTheirAccount() throws {
        let card = makeAccount("Card")
        let spend = add(6.5, account: card)
        let template = try XCTUnwrap(dataController.addQuickAddTemplate(from: spend))
        inserted.append(template)

        XCTAssertEqual(template.account, card)

        let logged = dataController.logQuickAddTemplate(template)
        inserted.append(logged)
        XCTAssertEqual(logged.account, card)
    }

    func testLastUsedAccountFallsBackToMainOnceDeleted() throws {
        let card = makeAccount("Card")
        AccountPreferences.record(.account(card))
        XCTAssertEqual(AccountPreferences.lastUsed(among: dataController.accounts()), .account(card))

        dataController.deleteAccount(card)
        XCTAssertEqual(AccountPreferences.lastUsed(among: dataController.accounts()), .main)
    }

    // MARK: - Scopes

    func testScopeStorageIsStable() {
        let scope = AccountScope(keys: ["B", "main", "A"])
        XCTAssertEqual(scope.storage, "A,B,main")
        XCTAssertEqual(AccountScope(storage: scope.storage), scope)
        XCTAssertEqual(AccountScope(storage: nil), .all)
        XCTAssertEqual(AccountScope(storage: ""), .all)
        XCTAssertEqual(AccountScope(storage: " , "), .all)
        XCTAssertNil(AccountScope.all.storage)
    }

    func testBudgetsCountOnlyTheirAccounts() throws {
        let card = makeAccount("Card")
        let cash = makeAccount("Cash")
        add(10)
        add(20, account: card)
        add(40, account: cash)
        transfer(1_000, from: .account(card), to: .account(cash))

        let budget = MainBudget(context: context)
        budget.amount = 100
        budget.type = 3
        budget.startDate = Calendar.current.date(byAdding: .day, value: -2, to: Date.now)
        inserted.append(budget)
        try context.save()

        let everything = 100 - dataController.budgetLeftover(overallBudget: budget).value

        budget.countedAccounts = AccountScope([.account(card)])
        XCTAssertEqual(100 - dataController.budgetLeftover(overallBudget: budget).value, 20, accuracy: 0.0001)

        budget.countedAccounts = AccountScope([.main, .account(cash)])
        XCTAssertEqual(100 - dataController.budgetLeftover(overallBudget: budget).value, everything - 20, accuracy: 0.0001)

        // With every account it counts deleted, the budget counts everything rather than nothing.
        budget.countedAccounts = AccountScope([.account(card)])
        dataController.deleteAccount(card)
        XCTAssertNil(budget.countedAccounts.predicate(in: context))
        XCTAssertEqual(100 - dataController.budgetLeftover(overallBudget: budget).value, everything, accuracy: 0.0001)
    }

    func testDeletedAccountsSpendingCountsWhereMainDoes() throws {
        let card = makeAccount("Card")
        let spend = add(33, account: card)

        let mainOnly = try XCTUnwrap(AccountScope([.main]).predicate(in: context))
        XCTAssertFalse(mainOnly.evaluate(with: spend))

        dataController.deleteAccount(card)
        XCTAssertTrue(mainOnly.evaluate(with: spend))
    }

    // MARK: - Import

    func testExportedTransfersPairUpOnImport() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let rows = [
            ImportedRow(date: date, amount: 50, note: "", categoryName: "", income: false, currencyCode: "EUR", accountName: "Main", isTransferLeg: true),
            ImportedRow(date: date, amount: 12, note: "Lunch", categoryName: "Food", income: false, currencyCode: "EUR", accountName: "Card"),
            ImportedRow(date: date, amount: 50, note: "", categoryName: "", income: true, currencyCode: "EUR", accountName: "Savings", isTransferLeg: true),
            // A lone leg stays an ordinary row.
            ImportedRow(date: date, amount: 7, note: "", categoryName: "", income: true, currencyCode: "EUR", accountName: "Savings", isTransferLeg: true)
        ]

        let pairs = ImportedRow.transferPairs(in: rows)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.outgoing, 0)
        XCTAssertEqual(pairs.first?.incoming, 2)
    }

    func testExportWritesAccountsAndTransferTypes() throws {
        let savings = makeAccount("Savings")
        let legs = transfer(25, from: .main, to: .account(savings))
        let spend = add(3, account: savings)

        let csv = ExportCSV.text(for: [legs.outgoing, legs.incoming, spend], mainCurrency: mainCurrency)
        let table = try XCTUnwrap(CSVTable.parse(csv))
        let mapping = ColumnMapping.detect(in: table)

        XCTAssertNotNil(mapping[.account])
        let parsed = ImportParseResult.build(table: table, mapping: mapping, dateFormat: ExportCSV.dateFormat)
        XCTAssertEqual(parsed.rows.count, 3)
        XCTAssertEqual(parsed.rows.filter(\.isTransferLeg).count, 2)
        XCTAssertEqual(Set(parsed.rows.map(\.accountName)), [MainAccount.name, "Savings"])
        XCTAssertEqual(ImportedRow.transferPairs(in: parsed.rows).count, 1)
    }

    // MARK: - Icons

    func testEveryIconExistsAndAppearsOnce() {
        XCTAssertEqual(Set(AccountIcons.all).count, AccountIcons.all.count)
        XCTAssertTrue(AccountIcons.all.contains(AccountIcons.defaultSymbol))

        for symbol in AccountIcons.all {
            XCTAssertEqual(AccountIcons.displayable(symbol), symbol, "\(symbol) isn't an SF Symbol here")
        }
    }

    func testIconsAreGuessedFromNames() {
        XCTAssertEqual(AccountIcons.guess(for: "Amex Gold"), "creditcard")
        XCTAssertEqual(AccountIcons.guess(for: "Gift card"), "giftcard")
        XCTAssertEqual(AccountIcons.guess(for: "Rainy day fund"), "umbrella")
        XCTAssertEqual(AccountIcons.guess(for: "Brokerage"), "chart.line.uptrend.xyaxis")
        XCTAssertEqual(AccountIcons.guess(for: "Joint account"), "person.2")
        // Whole words: a card isn't a car.
        XCTAssertEqual(AccountIcons.guess(for: "Car loan"), "car")
        XCTAssertEqual(AccountIcons.guess(for: "Wallet"), AccountIcons.defaultSymbol)
        XCTAssertTrue(AccountIcons.all.contains(AccountIcons.guess(for: "Anything at all")))
    }

    func testAccountsKeepThePickedIconAndGuessOneOtherwise() throws {
        let picked = dataController.addAccount(named: "Travel", symbol: "globe")
        inserted.append(picked)
        let guessed = makeAccount("Holiday")

        XCTAssertEqual(picked.wrappedSymbol, "globe")
        XCTAssertEqual(guessed.wrappedSymbol, "airplane")

        dataController.renameAccount(.account(picked), to: "Trips", symbol: "airplane")
        XCTAssertEqual(picked.wrappedName, "Trips")
        XCTAssertEqual(picked.wrappedSymbol, "airplane")

        // An account without one, such as from before icons, still has an icon.
        guessed.symbol = nil
        XCTAssertEqual(guessed.wrappedSymbol, "airplane")
    }

    // MARK: - Import

    func testImportListsAccountNamesOnceEachMostUsedFirst() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let rows = [
            ImportedRow(date: date, amount: 1, note: "", categoryName: "Food", income: false, accountName: "Card"),
            ImportedRow(date: date, amount: 2, note: "", categoryName: "Food", income: false, accountName: " cash "),
            ImportedRow(date: date, amount: 3, note: "", categoryName: "Food", income: false, accountName: "CARD"),
            ImportedRow(date: date, amount: 4, note: "", categoryName: "Food", income: false, accountName: "")
        ]

        let names = ImportParseResult(rows: rows, skipped: [:]).accountNames

        XCTAssertEqual(names.map(\.name), ["Card", "cash", ""])
        XCTAssertEqual(names.map(\.count), [2, 1, 1])
    }

    // Transfers take no category, so linking categories leaves them out; a lone leg is an ordinary row and stays.
    func testImportedTransfersAreLeftOutOfCategories() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let rows = [
            ImportedRow(date: date, amount: 50, note: "", categoryName: "", income: false, accountName: "Main", isTransferLeg: true),
            ImportedRow(date: date, amount: 50, note: "", categoryName: "", income: true, accountName: "Savings", isTransferLeg: true),
            ImportedRow(date: date, amount: 12, note: "Lunch", categoryName: "Food", income: false, accountName: "Card"),
            ImportedRow(date: date, amount: 7, note: "", categoryName: "", income: true, accountName: "Savings", isTransferLeg: true)
        ]

        let parsed = ImportParseResult(rows: rows, skipped: [:])

        XCTAssertEqual(parsed.pairedTransferRows, [0, 1])
        XCTAssertEqual(parsed.categoryKeys.map(\.key.name), ["Food", ""])
        XCTAssertEqual(parsed.categoryKeys.map(\.count), [1, 1])
    }

    // Shortcuts' New Transaction saves on a background context (DIME-IOS-Y); the app must see it in Main.
    @MainActor
    func testShortcutTransactionsAreSavedInTheBackgroundAndSeenInMain() async throws {
        guard #available(iOS 16, *) else { throw XCTSkip("Shortcuts actions need iOS 16.") }

        let category = dime.Category(context: context)
        category.id = UUID()
        category.name = "Shortcut test"
        category.emoji = "⚡️"
        inserted.append(category)
        try context.save()

        let objectID = try await dataController.newTransactionInBackground(note: "", categoryID: category.objectID, income: false, amount: 12.5, currencyCode: mainCurrency, repeatType: 2)
        let transaction = try XCTUnwrap(try context.existingObject(with: objectID) as? Transaction)
        inserted.append(transaction)

        XCTAssertFalse(objectID.isTemporaryID)
        XCTAssertEqual(transaction.amount, 12.5)
        XCTAssertEqual(transaction.currencyCode, mainCurrency)
        XCTAssertEqual(transaction.category, category)
        XCTAssertEqual(transaction.note, "Shortcut test")
        XCTAssertNil(transaction.account)
        XCTAssertEqual(transaction.recurringType, 2)
        XCTAssertTrue(transaction.onceRecurring)
        XCTAssertNotNil(transaction.id)
    }
}
