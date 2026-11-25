//
//  Accounts.swift
//  dime
//
//  Accounts and transfers. Built into the app, the widget and both intent extensions.
//

import CoreData
import Foundation

// MARK: - Main account

/// The account every transaction without an `Account` belongs to.
///
/// Main is never stored as an object. Transactions from before accounts existed, from older app versions still
/// syncing, and from accounts that were deleted all have no account, so they're all Main without anything having
/// to be migrated or backfilled. Two devices can't each create a Main and end up with duplicates.
enum MainAccount {
    /// Stands for Main wherever accounts are saved by key: budget scopes and the last used account.
    static let key = "main"

    static let nameKey = "mainAccountName"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")
    }

    static var defaultName: String {
        String(localized: "Main")
    }

    /// Main's name: the user's own, or "Main".
    static var name: String {
        let custom = defaults?.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultName : custom
    }

    /// Renames Main on this device and, through iCloud key-value storage, on the user's other devices.
    /// An empty name goes back to "Main".
    static func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed == defaultName ? "" : trimmed

        if stored.isEmpty {
            defaults?.removeObject(forKey: nameKey)
            NSUbiquitousKeyValueStore.default.removeObject(forKey: nameKey)
        } else {
            defaults?.set(stored, forKey: nameKey)
            NSUbiquitousKeyValueStore.default.set(stored, forKey: nameKey)
        }
    }

    /// Takes the name another device set. At launch iCloud may not have delivered anything yet, so a missing
    /// name only clears this device's when iCloud says it changed.
    static func adoptNameFromICloud(clearingIfMissing: Bool) {
        let store = NSUbiquitousKeyValueStore.default

        if let name = store.string(forKey: nameKey), !name.isEmpty {
            defaults?.set(name, forKey: nameKey)
        } else if clearingIfMissing {
            defaults?.removeObject(forKey: nameKey)
        }
    }
}

// MARK: - Choosing an account

/// An account a transaction can be in: Main, or one of the user's accounts.
enum AccountChoice: Hashable, Identifiable {
    case main
    case account(Account)

    init(_ account: Account?) {
        if let account {
            self = .account(account)
        } else {
            self = .main
        }
    }

    var account: Account? {
        if case let .account(account) = self {
            return account
        }
        return nil
    }

    var isMain: Bool {
        account == nil
    }

    /// Saved in budget scopes and preferences. An account's id, or "main".
    var key: String {
        switch self {
        case .main:
            return MainAccount.key
        case let .account(account):
            return account.key
        }
    }

    var id: String {
        key
    }

    var name: String {
        account?.wrappedName ?? MainAccount.name
    }

    /// Matches the transactions in this account.
    var predicate: NSPredicate {
        if let account {
            return NSPredicate(format: "%K == %@", #keyPath(Transaction.account), account)
        }
        return NSPredicate(format: "%K == nil", #keyPath(Transaction.account))
    }
}

extension Account {
    var wrappedName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Account") : trimmed
    }

    /// Accounts are matched by id everywhere they're saved by key, so one made before ids (never, today) still has a key.
    var key: String {
        id?.uuidString ?? objectID.uriRepresentation().absoluteString
    }

    var transactionCount: Int {
        transactions?.count ?? 0
    }
}

// MARK: - Scopes

/// Which accounts something counts, such as a budget. Saved as a comma-separated list of account keys;
/// nothing saved means every account, so budgets from before accounts existed keep counting everything.
struct AccountScope: Equatable, Hashable {
    /// Nil for every account.
    let keys: Set<String>?

    static let all = AccountScope(keys: nil)

    init(keys: Set<String>?) {
        if let keys, !keys.isEmpty {
            self.keys = keys
        } else {
            self.keys = nil
        }
    }

    init(storage: String?) {
        let keys = (storage ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        self.init(keys: Set(keys))
    }

    init(_ choices: [AccountChoice]) {
        self.init(keys: Set(choices.map(\.key)))
    }

    var isAll: Bool {
        keys == nil
    }

    /// Sorted, so saving the same scope twice gives the same string.
    var storage: String? {
        keys.map { $0.sorted().joined(separator: ",") }
    }

    func includes(_ choice: AccountChoice) -> Bool {
        keys?.contains(choice.key) ?? true
    }

    /// The scope without accounts that no longer exist. A scope left with none counts every account
    /// rather than nothing, so deleting accounts can never make a budget silently stop counting.
    func resolved(existingAccountKeys: Set<String>) -> AccountScope {
        guard let keys else {
            return .all
        }

        let remaining = keys.filter { $0 == MainAccount.key || existingAccountKeys.contains($0) }
        return AccountScope(keys: remaining)
    }

    /// Matches transactions in the scope, or nil for every account.
    ///
    /// Transactions of a deleted account have moved to Main, so they count wherever Main does.
    func predicate(existingAccountKeys: Set<String>) -> NSPredicate? {
        guard let keys = resolved(existingAccountKeys: existingAccountKeys).keys else {
            return nil
        }

        var predicates = [NSPredicate]()

        if keys.contains(MainAccount.key) {
            predicates.append(NSPredicate(format: "%K == nil", #keyPath(Transaction.account)))
        }

        let ids = keys.compactMap(UUID.init(uuidString:))

        if !ids.isEmpty {
            predicates.append(NSPredicate(format: "%K IN %@", "account.id", ids as NSArray))
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    /// The scope's predicate against the accounts in a context, or nil for every account.
    func predicate(in context: NSManagedObjectContext) -> NSPredicate? {
        guard !isAll else {
            return nil
        }

        return predicate(existingAccountKeys: AccountScope.accountKeys(in: context))
    }

    static func accountKeys(in context: NSManagedObjectContext) -> Set<String> {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        return Set(((try? context.fetch(request)) ?? []).map(\.key))
    }
}

// MARK: - Transfers

/// A transfer is two transactions sharing a `transferID`: an expense leaving one account and an income arriving
/// in the other. Keeping both legs as transactions lets each account's list and totals include it, while
/// spending, income, budgets and insights leave every transfer out.
enum TransferPredicate {
    /// Leaves transfers out. Every total of spending or income uses this: moving money between accounts is
    /// neither, and counting it would inflate both.
    static var excluded: NSPredicate {
        NSPredicate(format: "%K == nil", #keyPath(Transaction.transferID))
    }

    /// Shows each transfer once, by its outgoing leg, in lists that span every account.
    static var oneLegPerTransfer: NSPredicate {
        NSPredicate(format: "%K == nil OR income == NO", #keyPath(Transaction.transferID))
    }

    /// Adds `excluded` to a predicate.
    static func excluding(_ predicate: NSPredicate?) -> NSPredicate {
        guard let predicate else {
            return excluded
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excluded])
    }
}

extension Transaction {
    var isTransfer: Bool {
        transferID != nil
    }

    var accountChoice: AccountChoice {
        AccountChoice(account)
    }

    var accountName: String {
        accountChoice.name
    }

    /// The other leg of a transfer, or nil when this isn't one or the other leg hasn't synced yet.
    var transferCounterpart: Transaction? {
        guard let transferID, let context = managedObjectContext else {
            return nil
        }

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND self != %@", #keyPath(Transaction.transferID), transferID as CVarArg, self)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Where a transfer's money comes from and goes to. Nil when this isn't a transfer.
    /// A leg whose other half hasn't synced yet still names its own side.
    var transferAccounts: (from: AccountChoice?, to: AccountChoice?)? {
        guard isTransfer else {
            return nil
        }

        let counterpart = transferCounterpart?.accountChoice

        if income {
            return (counterpart, accountChoice)
        }
        return (accountChoice, counterpart)
    }

    /// "Main → Savings", for a transfer.
    var transferTitle: String? {
        guard let accounts = transferAccounts else {
            return nil
        }

        let from = accounts.from?.name ?? "…"
        let to = accounts.to?.name ?? "…"
        return "\(from) → \(to)"
    }
}

extension TemplateTransaction {
    var accountChoice: AccountChoice {
        AccountChoice(account)
    }
}

// MARK: - Last used account

/// New transactions go into the account the last one went into, so logging a run of card purchases
/// doesn't mean picking the card each time.
enum AccountPreferences {
    static let lastUsedKey = "lastUsedAccount"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")
    }

    static func record(_ choice: AccountChoice) {
        defaults?.set(choice.key, forKey: lastUsedKey)
    }

    /// The last used account if it still exists, otherwise Main.
    static func lastUsed(among accounts: [Account]) -> AccountChoice {
        guard let key = defaults?.string(forKey: lastUsedKey), key != MainAccount.key else {
            return .main
        }

        return accounts.first { $0.key == key }.map(AccountChoice.account) ?? .main
    }
}

// MARK: - Budgets

extension RolloverBudget {
    var countedAccounts: AccountScope {
        get { AccountScope(storage: accountScope) }
        set { accountScope = newValue.storage }
    }

    /// Matches the transactions in the budget's accounts, or nil when it counts every account.
    var accountPredicate: NSPredicate? {
        guard let context = managedObjectContext else {
            return nil
        }
        return countedAccounts.predicate(in: context)
    }
}
